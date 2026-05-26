-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Order Management Stored Procedures
-- =============================================================================

USE KhulisaCommerce;
GO

CREATE OR ALTER PROCEDURE dbo.usp_PlaceOrder
    @CustomerID         INT,
    @ShippingAddressID  INT,
    @DiscountCode       VARCHAR(50)     = NULL,
    @OrderLinesJson     NVARCHAR(MAX),
    @OrderID            INT             OUTPUT,
    @TotalAmount        DECIMAL(10,2)   OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ── Parse order lines from JSON ──────────────────────────────────────────
    DECLARE @Lines TABLE (
        VariantID INT NOT NULL,
        Quantity  INT NOT NULL
    );

    INSERT INTO @Lines
        (VariantID, Quantity)
    SELECT
        TRY_CAST(j.VariantID AS INT),
        TRY_CAST(j.Quantity  AS INT)
    FROM OPENJSON(@OrderLinesJson) WITH (
        VariantID   INT '$.VariantID',
        Quantity    INT '$.Quantity'
    ) j
    WHERE TRY_CAST(j.VariantID AS INT) IS NOT NULL
        AND TRY_CAST(j.Quantity  AS INT) > 0;

    IF NOT EXISTS (SELECT 1
    FROM @Lines)
    BEGIN
        RAISERROR('No valid order lines provided.', 16, 1);
        RETURN;
    END;

    -- ── Validate customer ────────────────────────────────────────────────────
    IF NOT EXISTS (SELECT 1
    FROM dbo.Customer
    WHERE CustomerID = @CustomerID AND IsActive = 1)
    BEGIN
        RAISERROR('Customer %d not found or inactive.', 16, 1, @CustomerID);
        RETURN;
    END;

    -- ── Resolve discount ─────────────────────────────────────────────────────
    DECLARE @DiscountID     INT     = NULL;
    DECLARE @DiscountType   VARCHAR(20);
    DECLARE @DiscountValue  DECIMAL(10,2) = 0;

    IF @DiscountCode IS NOT NULL
    BEGIN
        SELECT
            @DiscountID    = DiscountID,
            @DiscountType  = DiscountType,
            @DiscountValue = DiscountValue
        FROM dbo.Discount
        WHERE DiscountCode  = @DiscountCode
            AND IsActive      = 1
            AND ValidFrom    <= SYSUTCDATETIME()
            AND (ValidTo IS NULL OR ValidTo >= SYSUTCDATETIME())
            AND (MaxUsageCount IS NULL OR UsageCount < MaxUsageCount);

        IF @DiscountID IS NULL
        BEGIN
            RAISERROR('Discount code ''%s'' is invalid or expired.', 16, 1, @DiscountCode);
            RETURN;
        END;
    END;

    -- Explicitly terminate setup phase before transaction engine locks
    PRINT 'Validations passed. Beginning stock allocation.';

    BEGIN TRANSACTION PlaceOrder;
    BEGIN TRY

        -- ── Check & lock stock for each line ─────────────────────────────────
        DECLARE @StockCheck TABLE (
        VariantID    INT,
        AvailableQty INT,
        RequestedQty INT,
        UnitPrice    DECIMAL(10,2)
        );

        -- Isolated query statement to satisfy the parser
        INSERT INTO @StockCheck
        (VariantID, AvailableQty, RequestedQty, UnitPrice)
    SELECT
        sl.VariantID,
        sl.QuantityOnHand,
        l.Quantity,
        (p.BasePrice + pv.PriceAdjustment) AS UnitPrice
    FROM @Lines l
        INNER JOIN dbo.StockLevel sl WITH (UPDLOCK, ROWLOCK)
        ON sl.VariantID = l.VariantID
        INNER JOIN dbo.ProductVariant pv
        ON pv.VariantID = l.VariantID
        INNER JOIN dbo.Product p
        ON p.ProductID = pv.ProductID;

        -- ── Validate sufficient stock ─────────────────────────────────────────
        DECLARE @InsufficientVariantID INT = NULL;
        
        SELECT TOP 1
        @InsufficientVariantID = VariantID
    FROM @StockCheck
    WHERE AvailableQty < RequestedQty;

        IF @InsufficientVariantID IS NOT NULL
        BEGIN
        RAISERROR('Insufficient stock for VariantID %d.', 16, 1, @InsufficientVariantID);
        ROLLBACK TRANSACTION PlaceOrder;
        RETURN;
    END;

        -- ── Calculate totals ─────────────────────────────────────────────────
        DECLARE @Subtotal       DECIMAL(10,2) = 0;
        DECLARE @DiscountAmount DECIMAL(10,2) = 0;

        SELECT @Subtotal = SUM(UnitPrice * RequestedQty)
    FROM @StockCheck;

        SET @DiscountAmount = CASE @DiscountType
            WHEN 'PERCENTAGE'   THEN ROUND(@Subtotal * @DiscountValue / 100, 2)
            WHEN 'FIXED_AMOUNT' THEN CASE WHEN @DiscountValue > @Subtotal THEN @Subtotal ELSE @DiscountValue END
            ELSE 0
        END;

        SET @TotalAmount = @Subtotal - @DiscountAmount;

        -- ── Insert Order header ───────────────────────────────────────────────
        INSERT INTO dbo.[Order]
        (
        CustomerID, ShippingAddressID, DiscountID,
        SubtotalAmount, DiscountAmount, TotalAmount
        )
    VALUES
        (
            @CustomerID, @ShippingAddressID, @DiscountID,
            @Subtotal, @DiscountAmount, @TotalAmount
            );

        SET @OrderID = SCOPE_IDENTITY();

        -- ── Insert OrderLines ─────────────────────────────────────────────────
        INSERT INTO dbo.OrderLine
        (OrderID, VariantID, Quantity, UnitPrice)
    SELECT @OrderID, VariantID, RequestedQty, UnitPrice
    FROM @StockCheck;

        -- ── Deduct stock ──────────────────────────────────────────────────────
        MERGE dbo.StockLevel AS target
        USING (SELECT VariantID, RequestedQty
    FROM @StockCheck) AS source
            ON target.VariantID = source.VariantID
        WHEN MATCHED THEN
            UPDATE SET
                QuantityOnHand = target.QuantityOnHand - source.RequestedQty,
                UpdatedAt      = SYSUTCDATETIME();

        -- ── Record stock movements ────────────────────────────────────────────
        INSERT INTO dbo.StockMovement
        (
        StockLevelID, MovementType, QuantityChange, QuantityAfter,
        ReferenceID, ReferenceType
        )
    SELECT
        sl.StockLevelID,
        'SALE',
        -sc.RequestedQty,
        sl.QuantityOnHand,
        @OrderID,
        'ORDER'
    FROM @StockCheck sc
        INNER JOIN dbo.StockLevel sl ON sl.VariantID = sc.VariantID;

        -- ── Increment discount usage counter ──────────────────────────────────
        IF @DiscountID IS NOT NULL
        BEGIN
        UPDATE dbo.Discount
            SET UsageCount = UsageCount + 1
            WHERE DiscountID = @DiscountID;
    END;

        -- ── Award loyalty points (R10 = 1 point) ─────────────────────────────
        DECLARE @PointsEarned INT = FLOOR(@TotalAmount / 10);
        IF @PointsEarned > 0
        BEGIN
        UPDATE dbo.Customer
            SET LoyaltyPoints = LoyaltyPoints + @PointsEarned
            WHERE CustomerID = @CustomerID;
    END;

        COMMIT TRANSACTION PlaceOrder;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION PlaceOrder;

        DECLARE @ErrMsg      NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrState    INT            = ERROR_STATE();
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END;
GO

-- =============================================================================
-- SP 2: Update order status with full audit trail
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_UpdateOrderStatus
    @OrderID        INT,
    @NewStatus      VARCHAR(30),
    @CourierID      INT         = NULL,
    @TrackingNumber VARCHAR(100)= NULL,
    @Notes          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurrentStatus VARCHAR(30);

    SELECT @CurrentStatus = OrderStatus
    FROM dbo.[Order]
    WHERE OrderID = @OrderID;

    IF @CurrentStatus IS NULL
    BEGIN
        RAISERROR('Order %d not found.', 16, 1, @OrderID);
        RETURN;
    END;

    DECLARE @ValidTransition BIT = 0;

    SET @ValidTransition = CASE
        WHEN @CurrentStatus = 'PENDING' AND @NewStatus IN ('CONFIRMED','CANCELLED')     THEN 1
        WHEN @CurrentStatus = 'CONFIRMED' AND @NewStatus IN ('PROCESSING','CANCELLED')   THEN 1
        WHEN @CurrentStatus = 'PROCESSING' AND @NewStatus IN ('SHIPPED','CANCELLED')      THEN 1
        WHEN @CurrentStatus = 'SHIPPED' AND @NewStatus IN ('DELIVERED','RETURNED')     THEN 1
        WHEN @CurrentStatus = 'DELIVERED' AND @NewStatus = 'REFUNDED'                    THEN 1
        ELSE 0
    END;

    IF @ValidTransition = 0
    BEGIN
        RAISERROR('Invalid status transition from ''%s'' to ''%s'' for order %d.',
                  16, 1, @CurrentStatus, @NewStatus, @OrderID);
        RETURN;
    END;

    BEGIN TRANSACTION;
    BEGIN TRY

        UPDATE dbo.[Order]
        SET OrderStatus = @NewStatus,
            UpdatedAt   = SYSUTCDATETIME(),
            Notes       = ISNULL(@Notes, Notes)
        WHERE OrderID = @OrderID;

        IF @NewStatus = 'SHIPPED' AND @CourierID IS NOT NULL
        BEGIN
        INSERT INTO dbo.Shipment
            (OrderID, CourierID, TrackingNumber, ShipmentStatus)
        VALUES
            (@OrderID, @CourierID, @TrackingNumber, 'IN_TRANSIT');

        DECLARE @ShipmentID INT = SCOPE_IDENTITY();

        INSERT INTO dbo.ShipmentEvent
            (ShipmentID, EventStatus, EventNote)
        VALUES
            (@ShipmentID, 'IN_TRANSIT', 'Order dispatched from warehouse');
    END;

        IF @NewStatus = 'DELIVERED'
        BEGIN
        UPDATE dbo.Payment
                SET PaymentStatus = 'CAPTURED',
                    PaidAt        = SYSUTCDATETIME()
                WHERE OrderID     = @OrderID
            AND PaymentStatus = 'AUTHORISED';
    END;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================================================
-- SP 3: Process a return / refund
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ProcessReturn
    @OrderID        INT,
    @Reason         NVARCHAR(500)   = NULL,
    @RefundAmount   DECIMAL(10,2)   OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CustomerID     INT;
    DECLARE @TotalAmount    DECIMAL(10,2);
    DECLARE @OrderStatus    VARCHAR(30);

    SELECT
        @CustomerID     = CustomerID,
        @TotalAmount    = TotalAmount,
        @OrderStatus    = OrderStatus
    FROM dbo.[Order]
    WHERE OrderID = @OrderID;

    IF @OrderID IS NULL OR @OrderStatus NOT IN ('DELIVERED')
    BEGIN
        RAISERROR('Order %d cannot be refunded. Current status: %s', 16, 1, @OrderID, @OrderStatus);
        RETURN;
    END;

    SET @RefundAmount = @TotalAmount;

    BEGIN TRANSACTION;
    BEGIN TRY

        UPDATE sl
        SET sl.QuantityOnHand = sl.QuantityOnHand + ol.Quantity,
            sl.UpdatedAt      = SYSUTCDATETIME()
        FROM dbo.StockLevel sl
        INNER JOIN dbo.OrderLine ol ON ol.VariantID = sl.VariantID
        WHERE ol.OrderID = @OrderID;

        INSERT INTO dbo.StockMovement
        (
        StockLevelID, MovementType, QuantityChange, QuantityAfter,
        ReferenceID, ReferenceType, Notes
        )
    SELECT
        sl.StockLevelID,
        'RETURN',
        ol.Quantity,
        sl.QuantityOnHand,
        @OrderID,
        'RETURN',
        @Reason
    FROM dbo.OrderLine  ol
        INNER JOIN dbo.StockLevel sl ON sl.VariantID = ol.VariantID
    WHERE ol.OrderID = @OrderID;

        DECLARE @PointsToReverse INT = FLOOR(@TotalAmount / 10);
        IF @PointsToReverse > 0
        BEGIN
        UPDATE dbo.Customer
                SET LoyaltyPoints = CASE WHEN (LoyaltyPoints - @PointsToReverse) < 0 THEN 0 ELSE (LoyaltyPoints - @PointsToReverse) END
                WHERE CustomerID  = @CustomerID;
    END;

        UPDATE dbo.[Order]
        SET OrderStatus = 'REFUNDED', UpdatedAt = SYSUTCDATETIME()
        WHERE OrderID   = @OrderID;

        UPDATE dbo.Payment
        SET PaymentStatus = 'REFUNDED'
        WHERE OrderID     = @OrderID;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

PRINT 'Order management procedures created successfully.';
GO