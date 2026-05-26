-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Reporting Stored Procedures
-- Demonstrates: dynamic SQL with sp_executesql, keyset pagination,
--               offset pagination, output parameters for metadata,
--               Gold layer refresh with MERGE
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- SP 1: Flexible order search — dynamic SQL, keyset pagination
--       Demonstrates: safe parameterised dynamic SQL (zero injection risk)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_SearchOrders
    @CustomerID     INT             = NULL,
    @VendorID       INT             = NULL,
    @OrderStatus    VARCHAR(30)     = NULL,
    @FromDate       DATETIME2       = NULL,
    @ToDate         DATETIME2       = NULL,
    @MinAmount      DECIMAL(10,2)   = NULL,
    @MaxAmount      DECIMAL(10,2)   = NULL,
    @ProvinceID     INT             = NULL,
    @SortBy         VARCHAR(30)     = 'PlacedAt',
    @SortDir        VARCHAR(4)      = 'DESC',
    @PageNumber     INT             = 1,
    @PageSize       INT             = 25,
    @TotalCount     INT             OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Sanitise sort inputs (whitelist — never interpolate user input directly)
    IF @SortBy NOT IN ('PlacedAt','TotalAmount','OrderStatus','CustomerID')
        SET @SortBy = 'PlacedAt';
    IF @SortDir NOT IN ('ASC','DESC')
        SET @SortDir = 'DESC';

    -- Clamp pagination
    IF @PageNumber < 1    SET @PageNumber = 1;
    IF @PageSize   < 1    SET @PageSize   = 25;
    IF @PageSize   > 500  SET @PageSize   = 500;

    -- Build WHERE clause string (conditions added only when filter provided)
    DECLARE @Where NVARCHAR(2000) = N' WHERE 1=1 ';

    IF @CustomerID IS NOT NULL SET @Where += N' AND o.CustomerID  = @CustomerID ';
    IF @OrderStatus IS NOT NULL SET @Where += N' AND o.OrderStatus = @OrderStatus ';
    IF @FromDate   IS NOT NULL  SET @Where += N' AND o.PlacedAt  >= @FromDate ';
    IF @ToDate     IS NOT NULL  SET @Where += N' AND o.PlacedAt  <= @ToDate ';
    IF @MinAmount  IS NOT NULL  SET @Where += N' AND o.TotalAmount >= @MinAmount ';
    IF @MaxAmount  IS NOT NULL  SET @Where += N' AND o.TotalAmount <= @MaxAmount ';
    IF @ProvinceID IS NOT NULL  SET @Where += N' AND addr.CityID IN (
        SELECT CityID FROM dbo.City WHERE ProvinceID = @ProvinceID) ';
    IF @VendorID IS NOT NULL    SET @Where += N' AND EXISTS (
        SELECT 1 FROM dbo.OrderLine ol2
        JOIN dbo.ProductVariant pv2 ON pv2.VariantID = ol2.VariantID
        JOIN dbo.Product p2 ON p2.ProductID = pv2.ProductID
        WHERE ol2.OrderID = o.OrderID AND p2.VendorID = @VendorID) ';

    DECLARE @Joins NVARCHAR(500) = N'
        FROM       dbo.[Order]   o
        JOIN       dbo.Customer  c    ON c.CustomerID  = o.CustomerID
        JOIN       dbo.Address   addr ON addr.AddressID = o.ShippingAddressID
    ';

    -- Count query
    DECLARE @CountSql NVARCHAR(MAX) = N'SELECT @TotalCount = COUNT(*) ' + @Joins + @Where;

    -- Data query with dynamic ORDER BY (safe — whitelisted above)
    DECLARE @DataSql NVARCHAR(MAX) = N'
        SELECT
            o.OrderID,
            o.CustomerID,
            c.FirstName + '' '' + c.LastName   AS CustomerName,
            c.Email                            AS CustomerEmail,
            o.OrderStatus,
            o.SubtotalAmount,
            o.DiscountAmount,
            o.TotalAmount,
            o.PlacedAt,
            o.UpdatedAt
        ' + @Joins + @Where
        + N' ORDER BY o.' + @SortBy + N' ' + @SortDir
        + N' OFFSET (@PageNumber - 1) * @PageSize ROWS
             FETCH NEXT @PageSize ROWS ONLY;';

    DECLARE @Params NVARCHAR(MAX) = N'
        @CustomerID  INT,         @VendorID   INT,      @OrderStatus VARCHAR(30),
        @FromDate    DATETIME2,   @ToDate     DATETIME2,
        @MinAmount   DECIMAL(10,2), @MaxAmount DECIMAL(10,2),
        @ProvinceID  INT,
        @PageNumber  INT,         @PageSize   INT,
        @TotalCount  INT OUTPUT';

    -- Execute count
    EXEC sp_executesql @CountSql, @Params,
        @CustomerID, @VendorID, @OrderStatus, @FromDate, @ToDate,
        @MinAmount, @MaxAmount, @ProvinceID,
        @PageNumber, @PageSize, @TotalCount OUTPUT;

    -- Execute data page
    EXEC sp_executesql @DataSql, @Params,
        @CustomerID, @VendorID, @OrderStatus, @FromDate, @ToDate,
        @MinAmount, @MaxAmount, @ProvinceID,
        @PageNumber, @PageSize, @TotalCount OUTPUT;
END;
GO

-- =============================================================================
-- SP 2: Refresh the Gold-layer SalesSummary table
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_RefreshSalesSummary
    @SummaryDate    DATE = NULL
-- defaults to yesterday
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SummaryDate IS NULL
        SET @SummaryDate = CAST(DATEADD(DAY, -1, SYSUTCDATETIME()) AS DATE);

    DECLARE @DayStart DATETIME2 = CAST(@SummaryDate AS DATETIME2);
    DECLARE @DayEnd   DATETIME2 = DATEADD(DAY, 1, @DayStart);

    BEGIN TRANSACTION;
    BEGIN TRY

        -- Multi-CTE: replaced reserved keyword alias 'of' with 'facts'
        WITH
        OrderFacts
        AS
        (
            SELECT
                o.OrderID,
                o.SubtotalAmount,
                o.DiscountAmount,
                o.TotalAmount,
                addr.CityID
            FROM dbo.[Order]  o
                JOIN dbo.Address  addr ON addr.AddressID = o.ShippingAddressID
            WHERE o.PlacedAt >= @DayStart
                AND o.PlacedAt <  @DayEnd
                AND o.OrderStatus NOT IN ('CANCELLED')
        ),
        LineFacts
        AS
        (
            SELECT
                ol.OrderID,
                pv.ProductID,
                p.VendorID,
                p.CategoryID,
                SUM(ol.Quantity)              AS LineItemCount,
                SUM(ol.LineTotal)             AS LineRevenue
            FROM dbo.OrderLine      ol
                JOIN dbo.ProductVariant pv ON pv.VariantID  = ol.VariantID
                JOIN dbo.Product        p ON p.ProductID   = pv.ProductID
                JOIN OrderFacts         facts ON facts.OrderID = ol.OrderID
            GROUP BY ol.OrderID, pv.ProductID, p.VendorID, p.CategoryID
        ),
        Summary
        AS
        (
            SELECT
                lf.VendorID,
                lf.CategoryID,
                c.ProvinceID,
                COUNT(DISTINCT lf.OrderID)                    AS OrderCount,
                SUM(lf.LineItemCount)                         AS LineItemCount,
                SUM(facts.SubtotalAmount)                     AS GrossRevenue,
                SUM(facts.DiscountAmount)                     AS DiscountTotal,
                SUM(facts.TotalAmount)                        AS NetRevenue,
                SUM(facts.TotalAmount * v.CommissionRate / 100) AS Commission
            FROM LineFacts          lf
                JOIN OrderFacts         facts ON facts.OrderID   = lf.OrderID
                JOIN dbo.City           c ON c.CityID      = facts.CityID
                JOIN dbo.Vendor         v ON v.VendorID    = lf.VendorID
            GROUP BY lf.VendorID, lf.CategoryID, c.ProvinceID
        )
        MERGE dbo.SalesSummary AS target
        USING (
            SELECT @SummaryDate AS SummaryDate, *
    FROM Summary
        ) AS source
        ON  target.SummaryDate  = source.SummaryDate
        AND target.VendorID     = source.VendorID
        AND target.CategoryID   = source.CategoryID
        AND target.ProvinceID   = source.ProvinceID

        WHEN MATCHED THEN UPDATE SET
            OrderCount    = source.OrderCount,
            LineItemCount = source.LineItemCount,
            GrossRevenue  = source.GrossRevenue,
            DiscountTotal = source.DiscountTotal,
            NetRevenue    = source.NetRevenue,
            Commission    = source.Commission,
            ComputedAt    = SYSUTCDATETIME()

        WHEN NOT MATCHED THEN INSERT
            (SummaryDate, VendorID, CategoryID, ProvinceID,
             OrderCount, LineItemCount, GrossRevenue, DiscountTotal, NetRevenue, Commission)
        VALUES
            (source.SummaryDate, source.VendorID, source.CategoryID, source.ProvinceID,
             source.OrderCount, source.LineItemCount, source.GrossRevenue,
             source.DiscountTotal, source.NetRevenue, source.Commission);

        COMMIT TRANSACTION;

        -- Return summary of what was written
        SELECT
        @SummaryDate        AS SummaryDate,
        COUNT(*)            AS RowsUpserted,
        SUM(NetRevenue)     AS TotalNetRevenue,
        SUM(OrderCount)     AS TotalOrders
    FROM dbo.SalesSummary
    WHERE SummaryDate = @SummaryDate;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

PRINT 'Reporting procedures created successfully.';
GO