-- =============================================================================
-- SchemaForge Studio — Advanced SQL Queries
-- Demonstrates: recursive CTEs, correlated subqueries, CROSS APPLY,
--               EXCEPT/INTERSECT, FOR JSON, STRING_AGG, PIVOT, UNPIVOT
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- QUERY 1: Recursive CTE — full category tree with depth & breadcrumb path
-- =============================================================================
WITH CategoryTree AS (
    -- Anchor: root categories (no parent)
    SELECT
        CategoryID,
        ParentCategoryID,
        CategoryName,
        CategorySlug,
        0                                           AS Depth,
        CAST(CategoryName AS NVARCHAR(1000))        AS BreadcrumbPath,
        CAST(CategoryID AS VARCHAR(100))            AS IDPath
    FROM dbo.Category
    WHERE ParentCategoryID IS NULL
      AND IsActive = 1

    UNION ALL

    -- Recursive member: children
    SELECT
        c.CategoryID,
        c.ParentCategoryID,
        c.CategoryName,
        c.CategorySlug,
        ct.Depth + 1,
        CAST(ct.BreadcrumbPath + ' > ' + c.CategoryName AS NVARCHAR(1000)),
        CAST(ct.IDPath + '.' + CAST(c.CategoryID AS VARCHAR) AS VARCHAR(100))
    FROM dbo.Category c
    JOIN CategoryTree ct ON ct.CategoryID = c.ParentCategoryID
    WHERE c.IsActive = 1
)
SELECT
    REPLICATE('  ', Depth) + CategoryName   AS TreeDisplay,
    BreadcrumbPath,
    Depth,
    IDPath,
    -- Product count at this category (non-recursive subquery)
    (SELECT COUNT(*) FROM dbo.Product p
     WHERE p.CategoryID = ct.CategoryID AND p.IsActive = 1) AS DirectProductCount
FROM CategoryTree ct
ORDER BY IDPath;
GO

-- =============================================================================
-- QUERY 2: Correlated subquery — customers who spent more than average
--          in their own city (context-aware threshold)
-- =============================================================================
SELECT
    c.CustomerID,
    c.FirstName + ' ' + c.LastName     AS CustomerName,
    ci.CityName,
    SUM(o.TotalAmount)                 AS CustomerTotalSpend,

    -- Correlated subquery: average spend of ALL customers in the same city
    (
        SELECT AVG(o2.TotalAmount)
        FROM dbo.[Order]   o2
        JOIN dbo.Customer  c2   ON c2.CustomerID   = o2.CustomerID
        JOIN dbo.Address   a2   ON a2.CustomerID   = c2.CustomerID AND a2.IsDefault = 1
        WHERE a2.CityID = a.CityID
          AND o2.OrderStatus NOT IN ('CANCELLED')
    ) AS CityAvgSpend,

    -- How much above city average?
    SUM(o.TotalAmount) -
    (
        SELECT AVG(o2.TotalAmount)
        FROM dbo.[Order]   o2
        JOIN dbo.Customer  c2   ON c2.CustomerID   = o2.CustomerID
        JOIN dbo.Address   a2   ON a2.CustomerID   = c2.CustomerID AND a2.IsDefault = 1
        WHERE a2.CityID = a.CityID
          AND o2.OrderStatus NOT IN ('CANCELLED')
    ) AS AboveCityAvg

FROM       dbo.Customer c
JOIN       dbo.Address  a   ON a.CustomerID  = c.CustomerID AND a.IsDefault = 1
JOIN       dbo.City     ci  ON ci.CityID     = a.CityID
JOIN       dbo.[Order]  o   ON o.CustomerID  = c.CustomerID
WHERE      o.OrderStatus NOT IN ('CANCELLED')
GROUP BY   c.CustomerID, c.FirstName, c.LastName, ci.CityName, a.CityID
HAVING     SUM(o.TotalAmount) > (
               SELECT AVG(o2.TotalAmount)
               FROM dbo.[Order]   o2
               JOIN dbo.Customer  c2  ON c2.CustomerID   = o2.CustomerID
               JOIN dbo.Address   a2  ON a2.CustomerID   = c2.CustomerID AND a2.IsDefault = 1
               WHERE a2.CityID = a.CityID
                 AND o2.OrderStatus NOT IN ('CANCELLED')
           )
ORDER BY AboveCityAvg DESC;
GO

-- =============================================================================
-- QUERY 3: CROSS APPLY — top 3 products per vendor (lateral join)
-- =============================================================================
SELECT
    v.VendorID,
    v.VendorName,
    top3.ProductName,
    top3.TotalRevenue,
    top3.OrderCount,
    top3.ProductRank
FROM dbo.Vendor v
CROSS APPLY (
    -- This subquery runs once per vendor row — that's what CROSS APPLY does
    SELECT TOP 3
        p.ProductName,
        SUM(ol.LineTotal)       AS TotalRevenue,
        COUNT(DISTINCT ol.OrderID) AS OrderCount,
        ROW_NUMBER() OVER (ORDER BY SUM(ol.LineTotal) DESC) AS ProductRank
    FROM dbo.Product        p
    JOIN dbo.ProductVariant pv  ON pv.ProductID = p.ProductID
    JOIN dbo.OrderLine      ol  ON ol.VariantID = pv.VariantID
    JOIN dbo.[Order]        o   ON o.OrderID    = ol.OrderID
    WHERE p.VendorID = v.VendorID
      AND o.OrderStatus NOT IN ('CANCELLED')
    GROUP BY p.ProductName
    ORDER BY TotalRevenue DESC
) AS top3
WHERE v.IsActive = 1
ORDER BY v.VendorName, top3.ProductRank;
GO

-- =============================================================================
-- QUERY 4: EXCEPT — products that have NEVER been ordered
--          vs products that have been ordered but have zero stock
-- =============================================================================

-- Products with no orders ever
SELECT p.ProductID, p.ProductName, 'NEVER_ORDERED' AS Status
FROM dbo.Product p
WHERE p.IsActive = 1

EXCEPT

SELECT DISTINCT
    p.ProductID, p.ProductName, 'NEVER_ORDERED'
FROM dbo.Product        p
JOIN dbo.ProductVariant pv  ON pv.ProductID = p.ProductID
JOIN dbo.OrderLine      ol  ON ol.VariantID = pv.VariantID;

GO

-- Products ordered before but now out of stock everywhere
SELECT DISTINCT
    p.ProductID,
    p.ProductName,
    'ORDERED_BUT_OOS' AS Status
FROM dbo.Product        p
JOIN dbo.ProductVariant pv  ON pv.ProductID = p.ProductID
JOIN dbo.OrderLine      ol  ON ol.VariantID = pv.VariantID  -- has been ordered

INTERSECT

SELECT DISTINCT
    p.ProductID,
    p.ProductName,
    'ORDERED_BUT_OOS'
FROM dbo.Product        p
JOIN dbo.ProductVariant pv  ON pv.ProductID    = p.ProductID
JOIN dbo.StockLevel     sl  ON sl.VariantID    = pv.VariantID
WHERE sl.QuantityOnHand = 0;
GO

-- =============================================================================
-- QUERY 5: FOR JSON — generate API-ready JSON for order detail
-- =============================================================================
SELECT
    o.OrderID,
    o.OrderStatus,
    o.PlacedAt,
    o.TotalAmount,
    JSON_QUERY((
        SELECT
            c.CustomerID,
            c.FirstName + ' ' + c.LastName  AS fullName,
            c.Email
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS customer,
    JSON_QUERY((
        SELECT
            ol.OrderLineID,
            p.ProductName,
            pv.SKU,
            pv.SizeName,
            pv.ColourName,
            ol.Quantity,
            ol.UnitPrice,
            ol.LineTotal
        FROM dbo.OrderLine      ol
        JOIN dbo.ProductVariant pv  ON pv.VariantID = ol.VariantID
        JOIN dbo.Product        p   ON p.ProductID  = pv.ProductID
        WHERE ol.OrderID = o.OrderID
        FOR JSON PATH
    )) AS orderLines
FROM       dbo.[Order]   o
JOIN       dbo.Customer  c ON c.CustomerID = o.CustomerID
FOR JSON PATH;
GO

-- =============================================================================
-- QUERY 6: STRING_AGG — comma-separated product list per order (no cursor)
-- =============================================================================
SELECT
    o.OrderID,
    o.PlacedAt,
    c.FirstName + ' ' + c.LastName         AS CustomerName,
    COUNT(ol.OrderLineID)                   AS LineCount,
    o.TotalAmount,
    STRING_AGG(p.ProductName, ', ')
        WITHIN GROUP (ORDER BY p.ProductName) AS ProductsSummary
FROM       dbo.[Order]      o
JOIN       dbo.Customer     c   ON c.CustomerID = o.CustomerID
JOIN       dbo.OrderLine    ol  ON ol.OrderID   = o.OrderID
JOIN       dbo.ProductVariant pv ON pv.VariantID = ol.VariantID
JOIN       dbo.Product      p   ON p.ProductID  = pv.ProductID
WHERE      o.PlacedAt >= DATEADD(DAY, -30, SYSUTCDATETIME())
GROUP BY   o.OrderID, o.PlacedAt, c.FirstName, c.LastName, o.TotalAmount
ORDER BY   o.PlacedAt DESC;
GO

PRINT 'Advanced queries executed.';
GO
