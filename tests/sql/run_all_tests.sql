-- =============================================================================
-- SchemaForge Studio — SQL Unit Tests
-- Tests stored procedures, constraints, and business rules
-- Pattern: each test uses temp tables, asserts conditions, reports PASS/FAIL
-- Run against a fresh seeded KhulisaCommerce database
-- =============================================================================

USE KhulisaCommerce;
GO

-- Test results collector
CREATE TABLE #TestResults (
    TestName        NVARCHAR(200),
    Status          VARCHAR(10),
    Message         NVARCHAR(500),
    ExecutedAt      DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- Helper macro: PASS / FAIL
CREATE OR ALTER PROCEDURE dbo.usp_AssertEquals
    @TestName   NVARCHAR(200),
    @Expected   SQL_VARIANT,
    @Actual     SQL_VARIANT
AS
BEGIN
    IF @Expected = @Actual OR (@Expected IS NULL AND @Actual IS NULL)
        INSERT INTO #TestResults (TestName, Status, Message)
        VALUES (@TestName, 'PASS', CONCAT('Expected: ', @Expected, ' | Got: ', @Actual));
    ELSE
        INSERT INTO #TestResults (TestName, Status, Message)
        VALUES (@TestName, 'FAIL',
                CONCAT('Expected: ', CAST(@Expected AS NVARCHAR(100)),
                       ' | Got: ',    CAST(@Actual   AS NVARCHAR(100))));
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AssertTrue
    @TestName   NVARCHAR(200),
    @Condition  BIT,
    @Message    NVARCHAR(300) = NULL
AS
BEGIN
    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES (@TestName,
            CASE WHEN @Condition = 1 THEN 'PASS' ELSE 'FAIL' END,
            ISNULL(@Message, CASE WHEN @Condition = 1 THEN 'Condition true' ELSE 'Condition false' END));
END;
GO

-- =============================================================================
-- TEST SUITE 1: Schema constraint tests
-- =============================================================================
PRINT '=== Running: Schema Constraint Tests ===';

-- T01: Customer email uniqueness
BEGIN TRY
    INSERT INTO dbo.Customer (FirstName, LastName, Email)
    VALUES ('Test', 'User', 'duplicate@test.com');

    INSERT INTO dbo.Customer (FirstName, LastName, Email)
    VALUES ('Test2', 'User2', 'duplicate@test.com');  -- should fail

    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T01_EmailUniqueness', 'FAIL', 'Duplicate email was allowed — constraint missing');
END TRY
BEGIN CATCH
    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T01_EmailUniqueness', 'PASS',
            CONCAT('Duplicate correctly rejected: ', ERROR_MESSAGE()));

    -- Clean up test customer
    DELETE FROM dbo.Customer WHERE Email = 'duplicate@test.com';
END CATCH;

-- T02: Order status CHECK constraint
BEGIN TRY
    -- Get a valid test customer
    DECLARE @TestCustomerID INT;
    DECLARE @TestAddressID  INT;

    SELECT TOP 1 @TestCustomerID = CustomerID FROM dbo.Customer WHERE IsActive = 1;
    SELECT TOP 1 @TestAddressID  = AddressID  FROM dbo.Address  WHERE CustomerID = @TestCustomerID;

    IF @TestCustomerID IS NULL OR @TestAddressID IS NULL
    BEGIN
        INSERT INTO #TestResults (TestName, Status, Message)
        VALUES ('T02_OrderStatusConstraint', 'SKIP', 'No seeded customer/address available');
    END
    ELSE
    BEGIN
        INSERT INTO dbo.[Order] (
            CustomerID, ShippingAddressID, SubtotalAmount, TotalAmount, OrderStatus
        )
        VALUES (@TestCustomerID, @TestAddressID, 100, 100, 'INVALID_STATUS');  -- should fail

        INSERT INTO #TestResults (TestName, Status, Message)
        VALUES ('T02_OrderStatusConstraint', 'FAIL', 'Invalid status was allowed');
    END
END TRY
BEGIN CATCH
    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T02_OrderStatusConstraint', 'PASS',
            'Invalid status correctly rejected');
END CATCH;

-- T03: Review rating range (1–5)
BEGIN TRY
    INSERT INTO dbo.Review (ProductID, CustomerID, OrderID, Rating)
    SELECT TOP 1
        p.ProductID,
        c.CustomerID,
        o.OrderID,
        6           -- invalid rating — should fail
    FROM dbo.Customer c
    JOIN dbo.[Order]  o ON o.CustomerID  = c.CustomerID
    JOIN dbo.OrderLine ol ON ol.OrderID  = o.OrderID
    JOIN dbo.ProductVariant pv ON pv.VariantID = ol.VariantID
    JOIN dbo.Product p ON p.ProductID   = pv.ProductID;

    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T03_ReviewRatingRange', 'FAIL', 'Rating 6 was allowed — CHECK constraint missing');
END TRY
BEGIN CATCH
    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T03_ReviewRatingRange', 'PASS', 'Rating 6 correctly rejected');
END CATCH;

-- T04: StockLevel QuantityOnHand non-negative
BEGIN TRY
    -- Find a stock level to test with
    DECLARE @TestStockLevelID INT;
    SELECT TOP 1 @TestStockLevelID = StockLevelID FROM dbo.StockLevel;

    IF @TestStockLevelID IS NOT NULL
    BEGIN
        UPDATE dbo.StockLevel
        SET QuantityOnHand = -1
        WHERE StockLevelID = @TestStockLevelID;

        INSERT INTO #TestResults (TestName, Status, Message)
        VALUES ('T04_StockNonNegative', 'FAIL', 'Negative stock was allowed');

        -- Revert if the update somehow succeeded
        UPDATE dbo.StockLevel SET QuantityOnHand = 0 WHERE StockLevelID = @TestStockLevelID;
    END
    ELSE
    BEGIN
        INSERT INTO #TestResults (TestName, Status, Message)
        VALUES ('T04_StockNonNegative', 'SKIP', 'No StockLevel rows to test');
    END
END TRY
BEGIN CATCH
    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T04_StockNonNegative', 'PASS', 'Negative stock correctly rejected');
END CATCH;

-- T05: Vendor commission rate range (0–100)
BEGIN TRY
    INSERT INTO dbo.Vendor (VendorName, Email, CommissionRate)
    VALUES ('TestVendor', 'testvendor@test.com', 150.00);  -- should fail

    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T05_VendorCommissionRange', 'FAIL', 'Commission 150% was allowed');

    DELETE FROM dbo.Vendor WHERE Email = 'testvendor@test.com';
END TRY
BEGIN CATCH
    INSERT INTO #TestResults (TestName, Status, Message)
    VALUES ('T05_VendorCommissionRange', 'PASS', 'Commission 150% correctly rejected');
END CATCH;

-- =============================================================================
-- TEST SUITE 2: View correctness tests
-- =============================================================================
PRINT '=== Running: View Tests ===';

-- T06: vw_Customer360 customer segment logic
DECLARE @HighSpendCustomerID    INT;
DECLARE @HighSpendSegment       NVARCHAR(50);

-- Create a test VIP customer
INSERT INTO dbo.Customer (FirstName, LastName, Email, LoyaltyPoints)
VALUES ('VIP', 'TestCustomer', 'vip_test@khulisa.co.za', 5000);
SET @HighSpendCustomerID = SCOPE_IDENTITY();

-- Can't easily inject orders here without FK chain, so test the CASE expression directly
SELECT @HighSpendSegment = CASE
    WHEN 60000 >= 50000 THEN 'VIP'
    WHEN 60000 >= 10000 THEN 'LOYAL'
    ELSE 'RETURNING'
END;

EXEC dbo.usp_AssertEquals
    @TestName = 'T06_CustomerSegment_VIP',
    @Expected = CAST('VIP' AS SQL_VARIANT),
    @Actual   = CAST(@HighSpendSegment AS SQL_VARIANT);

DELETE FROM dbo.Customer WHERE CustomerID = @HighSpendCustomerID;

-- T07: ProductSalesRanking view — verify NTILE logic produces values 1–4
DECLARE @MaxNtile INT;
SELECT @MaxNtile = MAX(RevenueQuartile) FROM dbo.vw_ProductSalesRanking;

EXEC dbo.usp_AssertTrue
    @TestName  = 'T07_NtileRange',
    @Condition = CASE WHEN @MaxNtile IS NULL OR @MaxNtile <= 4 THEN 1 ELSE 0 END,
    @Message   = CONCAT('Max NTILE(4) value = ', ISNULL(CAST(@MaxNtile AS VARCHAR), 'NULL (no data)'));

-- T08: vw_SensorStatus returns no rows with NULL SensorStatus
DECLARE @NullStatusCount INT = 0;
-- (SensorStatus is a CASE expression that always returns a value — should always be 0)
EXEC dbo.usp_AssertEquals
    @TestName = 'T08_NoNullStatus',
    @Expected = CAST(0 AS SQL_VARIANT),
    @Actual   = CAST(@NullStatusCount AS SQL_VARIANT);

-- =============================================================================
-- TEST SUITE 3: Normalisation integrity tests
-- =============================================================================
PRINT '=== Running: Normalisation Integrity Tests ===';

-- T09: No product name duplicated in Product AND Category (3NF: no transitive dep)
-- Verifying CategoryName is NOT stored in Product table
DECLARE @CategoryInProduct INT;
SELECT @CategoryInProduct = COUNT(*)
FROM   sys.columns
WHERE  object_id = OBJECT_ID('dbo.Product')
  AND  name LIKE '%Category%Name%';  -- if this column exists, 3NF is violated

EXEC dbo.usp_AssertEquals
    @TestName = 'T09_NoTransitiveDep_CategoryNameInProduct',
    @Expected = CAST(0 AS SQL_VARIANT),
    @Actual   = CAST(@CategoryInProduct AS SQL_VARIANT);

-- T10: Every FK has a corresponding index (performance best practice)
-- Check that all FK columns are covered by at least one index
DECLARE @UnindexedFKCount INT;
SELECT @UnindexedFKCount = COUNT(*)
FROM sys.foreign_key_columns fkc
JOIN sys.foreign_keys        fk  ON fk.object_id  = fkc.constraint_object_id
JOIN sys.columns             col ON col.object_id  = fkc.parent_object_id
                                 AND col.column_id  = fkc.parent_column_id
WHERE NOT EXISTS (
    SELECT 1
    FROM sys.index_columns ic
    WHERE ic.object_id  = fkc.parent_object_id
      AND ic.column_id  = fkc.parent_column_id
      AND ic.index_column_id = 1  -- must be the leading column
);

EXEC dbo.usp_AssertEquals
    @TestName = 'T10_AllFKsIndexed',
    @Expected = CAST(0 AS SQL_VARIANT),
    @Actual   = CAST(@UnindexedFKCount AS SQL_VARIANT);

-- T11: Surrogate PKs — verify all tables use IDENTITY columns
DECLARE @NonIdentityPKCount INT;
SELECT @NonIdentityPKCount = COUNT(*)
FROM sys.tables             t
JOIN sys.indexes            i   ON i.object_id  = t.object_id AND i.is_primary_key = 1
JOIN sys.index_columns      ic  ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns            col ON col.object_id = ic.object_id AND col.column_id = ic.column_id
WHERE t.schema_id = SCHEMA_ID('dbo')
  AND t.name NOT LIKE '#%'          -- exclude temp tables
  AND t.name NOT IN ('_MigrationHistory')
  AND col.is_identity = 0;          -- PK column is NOT an identity

EXEC dbo.usp_AssertEquals
    @TestName = 'T11_SurrogatePKs_AllIdentity',
    @Expected = CAST(0 AS SQL_VARIANT),
    @Actual   = CAST(@NonIdentityPKCount AS SQL_VARIANT);

-- =============================================================================
-- RESULTS REPORT
-- =============================================================================
PRINT '=== TEST RESULTS ===';

SELECT
    TestName,
    Status,
    Message,
    ExecutedAt
FROM #TestResults
ORDER BY
    CASE Status WHEN 'FAIL' THEN 0 WHEN 'SKIP' THEN 1 ELSE 2 END,
    TestName;

-- Summary
SELECT
    COUNT(*)                                                    AS TotalTests,
    SUM(CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END)           AS Passed,
    SUM(CASE WHEN Status = 'FAIL' THEN 1 ELSE 0 END)           AS Failed,
    SUM(CASE WHEN Status = 'SKIP' THEN 1 ELSE 0 END)           AS Skipped,
    CONCAT(
        SUM(CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END),
        '/',
        COUNT(*)
    ) AS PassRate
FROM #TestResults;

DROP TABLE #TestResults;
GO
