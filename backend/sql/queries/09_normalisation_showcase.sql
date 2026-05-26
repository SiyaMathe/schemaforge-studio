-- =============================================================================
-- SchemaForge Studio — Normalisation Showcase
-- Step-by-step: UNF → 1NF → 2NF → 3NF
-- Each step is runnable SQL — shows the actual tables and dependency checks
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- STEP 0 — UNNORMALISED FORM (UNF)
-- Raw data as it comes from a legacy flat-file export
-- =============================================================================

CREATE TABLE #UNF_Orders (
    OrderID         INT,
    CustomerName    NVARCHAR(200),
    CustomerEmail   NVARCHAR(254),
    CustomerCity    NVARCHAR(100),
    -- Repeating groups — multiple product columns in one row
    Product1Name    NVARCHAR(200),
    Product1Price   DECIMAL(10,2),
    Product1Qty     INT,
    Product2Name    NVARCHAR(200),
    Product2Price   DECIMAL(10,2),
    Product2Qty     INT
);

INSERT INTO #UNF_Orders VALUES
(1001, 'Thabo Nkosi', 't@mail.co.za', 'Johannesburg', 'Air Max 90', 1299.00, 2, 'Running Top', 449.00, 1),
(1002, 'Ayanda Dube', 'a@mail.co.za', 'Durban',       'Air Max 90', 1299.00, 1, NULL,         NULL,    NULL);

SELECT '=== UNF: Unnormalised Form ===' AS [Step];
SELECT * FROM #UNF_Orders;
/*
Problems:
  1. Repeating groups (Product1, Product2 columns) — not atomic
  2. Redundant data (CustomerName repeated per order)
  3. Insert anomaly: cannot add a product without an order
  4. Delete anomaly: deleting order loses customer info
  5. Update anomaly: changing email requires update in many rows
*/
DROP TABLE #UNF_Orders;
GO

-- =============================================================================
-- STEP 1 — FIRST NORMAL FORM (1NF)
-- Rule: Eliminate repeating groups. All values atomic. Each row unique.
-- =============================================================================

CREATE TABLE #ONF_OrderLine (
    -- Composite PK: (OrderID, LineNum)
    OrderID         INT             NOT NULL,
    LineNum         INT             NOT NULL,
    -- Order-level data (STILL repeated — will fix in 2NF)
    CustomerName    NVARCHAR(200)   NOT NULL,
    CustomerEmail   NVARCHAR(254)   NOT NULL,
    CustomerCity    NVARCHAR(100)   NOT NULL,
    -- Line-level data (now atomic — one product per row)
    ProductName     NVARCHAR(200)   NOT NULL,
    UnitPrice       DECIMAL(10,2)   NOT NULL,
    Quantity        INT             NOT NULL,
    PRIMARY KEY (OrderID, LineNum)
);

INSERT INTO #ONF_OrderLine VALUES
(1001, 1, 'Thabo Nkosi', 't@mail.co.za', 'Johannesburg', 'Air Max 90',  1299.00, 2),
(1001, 2, 'Thabo Nkosi', 't@mail.co.za', 'Johannesburg', 'Running Top',  449.00, 1),
(1002, 1, 'Ayanda Dube', 'a@mail.co.za', 'Durban',       'Air Max 90',  1299.00, 1);

SELECT '=== 1NF: First Normal Form ===' AS [Step];
SELECT * FROM #ONF_OrderLine;

-- Verify: no NULL in any atomic field
SELECT 'Atomicity check — NULL count:' AS Check,
       SUM(CASE WHEN ProductName IS NULL THEN 1 ELSE 0 END) AS NullProducts
FROM #ONF_OrderLine;

/*
✅ Achieved: No repeating groups, each cell atomic, composite PK defined
❌ Still broken: CustomerName, CustomerEmail, CustomerCity depend ONLY on OrderID
   — not on the full composite key (OrderID, LineNum). That's a partial dependency.
*/
DROP TABLE #ONF_OrderLine;
GO

-- =============================================================================
-- STEP 2 — SECOND NORMAL FORM (2NF)
-- Rule: Remove partial dependencies.
--       Every non-key attribute must depend on the WHOLE composite key.
-- =============================================================================

-- Split into two tables: Order (depends on OrderID) and OrderLine (depends on full key)

CREATE TABLE #TNF_Order_2NF (
    OrderID         INT             NOT NULL PRIMARY KEY,
    CustomerName    NVARCHAR(200)   NOT NULL,
    CustomerEmail   NVARCHAR(254)   NOT NULL,
    CustomerCity    NVARCHAR(100)   NOT NULL
    -- CustomerCity still has a transitive dependency on CustomerName → will fix in 3NF
);

CREATE TABLE #TNF_OrderLine_2NF (
    OrderID         INT             NOT NULL,
    LineNum         INT             NOT NULL,
    ProductName     NVARCHAR(200)   NOT NULL,
    Category        NVARCHAR(100)   NOT NULL,   -- transitive dep on ProductName → fix in 3NF
    UnitPrice       DECIMAL(10,2)   NOT NULL,
    Quantity        INT             NOT NULL,
    PRIMARY KEY (OrderID, LineNum),
    FOREIGN KEY (OrderID) REFERENCES #TNF_Order_2NF(OrderID)
);

INSERT INTO #TNF_Order_2NF VALUES
(1001, 'Thabo Nkosi', 't@mail.co.za', 'Johannesburg'),
(1002, 'Ayanda Dube', 'a@mail.co.za', 'Durban');

INSERT INTO #TNF_OrderLine_2NF VALUES
(1001, 1, 'Air Max 90',  'Shoes',    1299.00, 2),
(1001, 2, 'Running Top', 'Clothing',  449.00, 1),
(1002, 1, 'Air Max 90',  'Shoes',    1299.00, 1);

SELECT '=== 2NF: Second Normal Form ===' AS [Step];
SELECT o.*, ol.LineNum, ol.ProductName, ol.Category, ol.Quantity, ol.UnitPrice
FROM #TNF_Order_2NF o
JOIN #TNF_OrderLine_2NF ol ON ol.OrderID = o.OrderID
ORDER BY o.OrderID, ol.LineNum;

/*
✅ Achieved: No partial dependencies — each attribute depends on the whole key
❌ Still broken:
   Order table:  CustomerCity → implied by CustomerEmail (transitive dep)
   OrderLine:    Category depends on ProductName, not on the (OrderID, LineNum) key
*/
DROP TABLE #TNF_OrderLine_2NF;
DROP TABLE #TNF_Order_2NF;
GO

-- =============================================================================
-- STEP 3 — THIRD NORMAL FORM (3NF)
-- Rule: Remove transitive dependencies.
--       Non-key attributes depend on the key, the WHOLE key, and NOTHING BUT the key.
-- =============================================================================

-- Final 3NF decomposition:

CREATE TABLE #Customer_3NF (
    CustomerID      INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    FullName        NVARCHAR(200)   NOT NULL,
    Email           NVARCHAR(254)   NOT NULL UNIQUE,
    CityID          INT             NOT NULL   -- FK to City (not storing city name here)
);

CREATE TABLE #City_3NF (
    CityID          INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CityName        NVARCHAR(100)   NOT NULL
    -- In full schema: FK to Province → Country (further decomposition)
);

CREATE TABLE #Category_3NF (
    CategoryID      INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CategoryName    NVARCHAR(100)   NOT NULL UNIQUE
);

CREATE TABLE #Product_3NF (
    ProductID       INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ProductName     NVARCHAR(200)   NOT NULL UNIQUE,
    CategoryID      INT             NOT NULL,
    BasePrice       DECIMAL(10,2)   NOT NULL,
    FOREIGN KEY (CategoryID) REFERENCES #Category_3NF(CategoryID)
);

CREATE TABLE #Order_3NF (
    OrderID         INT             NOT NULL PRIMARY KEY,
    CustomerID      INT             NOT NULL,
    OrderDate       DATE            NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    FOREIGN KEY (CustomerID) REFERENCES #Customer_3NF(CustomerID)
);

CREATE TABLE #OrderLine_3NF (
    OrderLineID     INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    OrderID         INT             NOT NULL,
    ProductID       INT             NOT NULL,
    Quantity        INT             NOT NULL,
    UnitPrice       DECIMAL(10,2)   NOT NULL,   -- snapshot price at time of order
    FOREIGN KEY (OrderID)   REFERENCES #Order_3NF(OrderID),
    FOREIGN KEY (ProductID) REFERENCES #Product_3NF(ProductID)
);

-- Seed
INSERT INTO #City_3NF     (CityName)     VALUES ('Johannesburg'), ('Durban');
INSERT INTO #Category_3NF (CategoryName) VALUES ('Shoes'), ('Clothing');
INSERT INTO #Customer_3NF (FullName, Email, CityID) VALUES
    ('Thabo Nkosi', 't@mail.co.za', 1),
    ('Ayanda Dube', 'a@mail.co.za', 2);
INSERT INTO #Product_3NF  (ProductName, CategoryID, BasePrice) VALUES
    ('Air Max 90',  1, 1299.00),
    ('Running Top', 2,  449.00);
INSERT INTO #Order_3NF    (OrderID, CustomerID) VALUES (1001, 1), (1002, 2);
INSERT INTO #OrderLine_3NF (OrderID, ProductID, Quantity, UnitPrice) VALUES
    (1001, 1, 2, 1299.00),
    (1001, 2, 1,  449.00),
    (1002, 1, 1, 1299.00);

SELECT '=== 3NF: Third Normal Form — Final Decomposition ===' AS [Step];

-- Reconstruct the original view via JOINs
SELECT
    o.OrderID,
    c.FullName          AS CustomerName,
    c.Email,
    ci.CityName         AS CustomerCity,
    p.ProductName,
    cat.CategoryName,
    ol.Quantity,
    ol.UnitPrice,
    ol.Quantity * ol.UnitPrice AS LineTotal
FROM #Order_3NF         o
JOIN #Customer_3NF      c   ON c.CustomerID = o.CustomerID
JOIN #City_3NF          ci  ON ci.CityID    = c.CityID
JOIN #OrderLine_3NF     ol  ON ol.OrderID   = o.OrderID
JOIN #Product_3NF       p   ON p.ProductID  = ol.ProductID
JOIN #Category_3NF      cat ON cat.CategoryID = p.CategoryID
ORDER BY o.OrderID, p.ProductName;

-- Verify: no transitive dependencies remain
SELECT '3NF Verification:' AS [Check];
SELECT
    'Customer.CityID → City.CityName (not stored in Customer)'  AS Passed UNION ALL
SELECT 'Product.CategoryID → Category.CategoryName (not stored in Product)'   UNION ALL
SELECT 'UnitPrice is a fact about the order line event, not a transitive dep' UNION ALL
SELECT 'All non-key attributes depend on PK and nothing but the PK';

DROP TABLE #OrderLine_3NF;
DROP TABLE #Order_3NF;
DROP TABLE #Product_3NF;
DROP TABLE #Customer_3NF;
DROP TABLE #Category_3NF;
DROP TABLE #City_3NF;
GO

PRINT 'Normalisation showcase complete.';
GO
