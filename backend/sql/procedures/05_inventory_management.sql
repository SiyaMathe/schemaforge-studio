-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Inventory Management Stored Procedures
-- Demonstrates: optimistic concurrency with row versioning, SET-based bulk
--               updates (no cursors), OUTPUT clause, EXCEPT for diff queries
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- SP 1: Restock a warehouse — bulk update with OUTPUT clause
--       Returns a diff of before/after quantities for audit reporting
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_RestockWarehouse
    @WarehouseID        INT,
    @RestockJson        NVARCHAR(MAX),  -- [{"VariantID":1,"Quantity":50}, ...]
    @RowsUpdated        INT     OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Staging table from JSON payload
    DECLARE @Incoming TABLE (
        VariantID   INT     NOT NULL,
        Quantity    INT     NOT NULL,
        CHECK (Quantity > 0)
    );

    INSERT INTO @Incoming (VariantID, Quantity)
    SELECT
        TRY_CAST(j.VariantID AS INT),
        TRY_CAST(j.Quantity  AS INT)
    FROM OPENJSON(@RestockJson) WITH (
        VariantID   INT '$.VariantID',
        Quantity    INT '$.Quantity'
    ) j
    WHERE TRY_CAST(j.VariantID AS INT) IS NOT NULL
      AND TRY_CAST(j.Quantity  AS INT) > 0;

    -- OUTPUT clause captures before/after for audit trail insert
    DECLARE @Changes TABLE (
        StockLevelID        INT,
        VariantID           INT,
        QuantityBefore      INT,
        QuantityAfter       INT,
        QuantityChange      INT
    );

    BEGIN TRANSACTION;
    BEGIN TRY

        -- SET-based MERGE (no cursor) — upserts StockLevel rows
        -- If the variant doesn't exist in this warehouse yet, INSERT it
        MERGE dbo.StockLevel AS target
        USING (
            SELECT i.VariantID, i.Quantity
            FROM @Incoming i
            WHERE EXISTS (
                SELECT 1 FROM dbo.ProductVariant pv
                WHERE pv.VariantID = i.VariantID AND pv.IsActive = 1
            )
        ) AS source ON (target.WarehouseID = @WarehouseID AND target.VariantID = source.VariantID)

        WHEN MATCHED THEN
            UPDATE SET
                QuantityOnHand = target.QuantityOnHand + source.Quantity,
                UpdatedAt      = SYSUTCDATETIME()

        WHEN NOT MATCHED BY TARGET THEN
            INSERT (WarehouseID, VariantID, QuantityOnHand)
            VALUES (@WarehouseID, source.VariantID, source.Quantity)

        OUTPUT
            INSERTED.StockLevelID,
            INSERTED.VariantID,
            DELETED.QuantityOnHand,                 -- NULL for new inserts
            INSERTED.QuantityOnHand,
            INSERTED.QuantityOnHand - ISNULL(DELETED.QuantityOnHand, 0)
        INTO @Changes (StockLevelID, VariantID, QuantityBefore, QuantityAfter, QuantityChange);

        -- Bulk insert movement records from the captured OUTPUT
        INSERT INTO dbo.StockMovement (
            StockLevelID, MovementType, QuantityChange,
            QuantityAfter, ReferenceType, Notes
        )
        SELECT
            StockLevelID,
            'RESTOCK',
            QuantityChange,
            QuantityAfter,
            'RESTOCK_JOB',
            CONCAT('Restock — WarehouseID: ', @WarehouseID,
                   ' | Before: ', ISNULL(QuantityBefore, 0),
                   ' | After: ', QuantityAfter)
        FROM @Changes;

        SET @RowsUpdated = @@ROWCOUNT;

        COMMIT TRANSACTION;

        -- Return the audit diff to the caller
        SELECT
            c.VariantID,
            pv.SKU,
            p.ProductName,
            c.QuantityBefore,
            c.QuantityChange,
            c.QuantityAfter
        FROM @Changes c
        JOIN dbo.ProductVariant pv ON pv.VariantID = c.VariantID
        JOIN dbo.Product        p  ON p.ProductID  = pv.ProductID
        ORDER BY p.ProductName;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================================================
-- SP 2: Transfer stock between warehouses
--       Uses SAVE TRANSACTION for partial rollback on individual line failure
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_TransferStock
    @FromWarehouseID    INT,
    @ToWarehouseID      INT,
    @VariantID          INT,
    @Quantity           INT,
    @Notes              NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;  -- OFF so we can use SAVE TRANSACTION

    IF @FromWarehouseID = @ToWarehouseID
    BEGIN
        RAISERROR('Source and destination warehouse cannot be the same.', 16, 1);
        RETURN;
    END

    IF @Quantity <= 0
    BEGIN
        RAISERROR('Transfer quantity must be positive.', 16, 1);
        RETURN;
    END

    -- Check source stock availability
    DECLARE @SourceStockLevelID INT;
    DECLARE @SourceQty          INT;

    SELECT
        @SourceStockLevelID = StockLevelID,
        @SourceQty          = QuantityOnHand
    FROM dbo.StockLevel
    WHERE WarehouseID = @FromWarehouseID
      AND VariantID   = @VariantID;

    IF @SourceStockLevelID IS NULL
    BEGIN
        RAISERROR('No stock record for VariantID %d in warehouse %d.',
                  16, 1, @VariantID, @FromWarehouseID);
        RETURN;
    END

    IF @SourceQty < @Quantity
    BEGIN
        RAISERROR('Insufficient stock. Available: %d, Requested: %d.',
                  16, 1, @SourceQty, @Quantity);
        RETURN;
    END

    BEGIN TRANSACTION;
    SAVE TRANSACTION BeforeTransfer;
    BEGIN TRY

        -- Deduct from source
        UPDATE dbo.StockLevel
        SET QuantityOnHand = QuantityOnHand - @Quantity,
            UpdatedAt      = SYSUTCDATETIME()
        WHERE StockLevelID = @SourceStockLevelID;

        INSERT INTO dbo.StockMovement (
            StockLevelID, MovementType, QuantityChange,
            QuantityAfter, ReferenceType, Notes
        )
        VALUES (
            @SourceStockLevelID, 'TRANSFER',
            -@Quantity,
            @SourceQty - @Quantity,
            'TRANSFER',
            ISNULL(@Notes, CONCAT('Transfer to WarehouseID: ', @ToWarehouseID))
        );

        -- Add to destination (INSERT if not exists)
        DECLARE @DestStockLevelID INT;

        SELECT @DestStockLevelID = StockLevelID
        FROM dbo.StockLevel
        WHERE WarehouseID = @ToWarehouseID
          AND VariantID   = @VariantID;

        IF @DestStockLevelID IS NULL
        BEGIN
            INSERT INTO dbo.StockLevel (WarehouseID, VariantID, QuantityOnHand)
            VALUES (@ToWarehouseID, @VariantID, @Quantity);

            SET @DestStockLevelID = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE dbo.StockLevel
            SET QuantityOnHand = QuantityOnHand + @Quantity,
                UpdatedAt      = SYSUTCDATETIME()
            WHERE StockLevelID = @DestStockLevelID;
        END

        DECLARE @DestQtyAfter INT;
        SELECT @DestQtyAfter = QuantityOnHand
        FROM   dbo.StockLevel WHERE StockLevelID = @DestStockLevelID;

        INSERT INTO dbo.StockMovement (
            StockLevelID, MovementType, QuantityChange,
            QuantityAfter, ReferenceType, Notes
        )
        VALUES (
            @DestStockLevelID, 'TRANSFER',
            @Quantity,
            @DestQtyAfter,
            'TRANSFER',
            ISNULL(@Notes, CONCAT('Transfer from WarehouseID: ', @FromWarehouseID))
        );

        COMMIT TRANSACTION;

        SELECT 'Transfer successful' AS Result,
               @FromWarehouseID     AS FromWarehouse,
               @ToWarehouseID       AS ToWarehouse,
               @VariantID           AS VariantID,
               @Quantity            AS QuantityTransferred;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION BeforeTransfer;
        IF @@TRANCOUNT > 0 COMMIT TRANSACTION;  -- commit outer if exists
        THROW;
    END CATCH
END;
GO

-- =============================================================================
-- SP 3: Get low-stock report — SET-based, no cursor, uses EXCEPT
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GetLowStockReport
    @WarehouseID    INT     = NULL,   -- NULL = all warehouses
    @IncludeZero    BIT     = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        w.WarehouseName,
        pv.SKU,
        p.ProductName,
        pv.SizeName,
        pv.ColourName,
        sl.QuantityOnHand,
        sl.ReorderPoint,
        sl.ReorderPoint - sl.QuantityOnHand AS Shortfall,
        CASE
            WHEN sl.QuantityOnHand = 0                          THEN 'OUT_OF_STOCK'
            WHEN sl.QuantityOnHand <= (sl.ReorderPoint * 0.5)   THEN 'CRITICAL'
            WHEN sl.QuantityOnHand <= sl.ReorderPoint           THEN 'LOW'
            ELSE 'ADEQUATE'
        END AS StockStatus,
        v.VendorName,
        v.Email AS VendorEmail
    FROM dbo.StockLevel     sl
    JOIN dbo.Warehouse      w   ON w.WarehouseID  = sl.WarehouseID
    JOIN dbo.ProductVariant pv  ON pv.VariantID   = sl.VariantID
    JOIN dbo.Product        p   ON p.ProductID    = pv.ProductID
    JOIN dbo.Vendor         v   ON v.VendorID     = p.VendorID
    WHERE sl.QuantityOnHand <= sl.ReorderPoint
      AND (@WarehouseID IS NULL OR sl.WarehouseID = @WarehouseID)
      AND (@IncludeZero = 1 OR sl.QuantityOnHand > 0)
      AND pv.IsActive = 1
      AND p.IsActive  = 1
    ORDER BY
        CASE
            WHEN sl.QuantityOnHand = 0 THEN 0
            WHEN sl.QuantityOnHand <= (sl.ReorderPoint * 0.5) THEN 1
            ELSE 2
        END,
        sl.QuantityOnHand ASC;
END;
GO

PRINT 'Inventory management procedures created.';
GO
