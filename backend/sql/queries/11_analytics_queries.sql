-- =============================================================================
-- SchemaForge Studio — Analytics Queries
-- Demonstrates: GROUP BY ROLLUP, GROUP BY CUBE, PIVOT, UNPIVOT,
--               running totals, Pareto analysis, ABC classification,
--               cohort LTV, basket analysis
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- QUERY 1: Sales by Province × Category with ROLLUP (subtotals + grand total)
-- =============================================================================
SELECT
    COALESCE(pr.ProvinceName, '── ALL PROVINCES')     AS Province,
    COALESCE(cat.CategoryName, '── ALL CATEGORIES')   AS Category,
    COUNT(DISTINCT o.OrderID)                          AS OrderCount,
    SUM(ol.Quantity)                                   AS UnitsSold,
    ROUND(SUM(ol.LineTotal), 2)                        AS TotalRevenue,
    ROUND(AVG(ol.LineTotal), 2)                        AS AvgLineValue,

    -- Identify which row is a subtotal / grand total
    CASE
        WHEN GROUPING(pr.ProvinceName)  = 1
         AND GROUPING(cat.CategoryName) = 1 THEN 'GRAND TOTAL'
        WHEN GROUPING(cat.CategoryName) = 1 THEN 'Province Subtotal'
        ELSE 'Detail'
    END AS RowType

FROM       dbo.OrderLine    ol
JOIN       dbo.[Order]      o   ON o.OrderID    = ol.OrderID
JOIN       dbo.ProductVariant pv ON pv.VariantID = ol.VariantID
JOIN       dbo.Product      p   ON p.ProductID  = pv.ProductID
JOIN       dbo.Category     cat ON cat.CategoryID = p.CategoryID
JOIN       dbo.Address      addr ON addr.AddressID = o.ShippingAddressID
JOIN       dbo.City         ci  ON ci.CityID    = addr.CityID
JOIN       dbo.Province     pr  ON pr.ProvinceID = ci.ProvinceID
WHERE      o.OrderStatus NOT IN ('CANCELLED')
GROUP BY ROLLUP (pr.ProvinceName, cat.CategoryName)
ORDER BY
    GROUPING(pr.ProvinceName),
    GROUPING(cat.CategoryName),
    pr.ProvinceName,
    cat.CategoryName;
GO

-- =============================================================================
-- QUERY 2: CUBE — all possible subtotals (Province × Category × Vendor)
-- =============================================================================
SELECT
    COALESCE(pr.ProvinceName,  'ALL')   AS Province,
    COALESCE(cat.CategoryName, 'ALL')   AS Category,
    COALESCE(v.VendorName,     'ALL')   AS Vendor,
    ROUND(SUM(ol.LineTotal), 2)         AS Revenue,
    COUNT(DISTINCT o.CustomerID)        AS UniqueCustomers,
    -- Grouping bitmap tells us which dimensions are aggregated
    GROUPING(pr.ProvinceName)           AS IsProvinceAgg,
    GROUPING(cat.CategoryName)          AS IsCategoryAgg,
    GROUPING(v.VendorName)              AS IsVendorAgg

FROM       dbo.OrderLine    ol
JOIN       dbo.[Order]      o   ON o.OrderID     = ol.OrderID
JOIN       dbo.ProductVariant pv ON pv.VariantID = ol.VariantID
JOIN       dbo.Product      p   ON p.ProductID   = pv.ProductID
JOIN       dbo.Category     cat ON cat.CategoryID = p.CategoryID
JOIN       dbo.Vendor       v   ON v.VendorID    = p.VendorID
JOIN       dbo.Address      addr ON addr.AddressID = o.ShippingAddressID
JOIN       dbo.City         ci  ON ci.CityID     = addr.CityID
JOIN       dbo.Province     pr  ON pr.ProvinceID = ci.ProvinceID
WHERE      o.OrderStatus NOT IN ('CANCELLED')
GROUP BY CUBE (pr.ProvinceName, cat.CategoryName, v.VendorName)
-- Only show combinations with data
HAVING SUM(ol.LineTotal) > 0
ORDER BY
    IsProvinceAgg DESC,
    IsCategoryAgg DESC,
    IsVendorAgg DESC,
    Revenue DESC;
GO

-- =============================================================================
-- QUERY 3: PIVOT — monthly revenue by category (dynamic column months)
-- =============================================================================

-- Static PIVOT for last 6 months (readable, explainable in interviews)
WITH MonthlyCategoryRevenue AS (
    SELECT
        cat.CategoryName,
        FORMAT(o.PlacedAt, 'yyyy-MM') AS YearMonth,
        SUM(ol.LineTotal)             AS Revenue
    FROM       dbo.OrderLine    ol
    JOIN       dbo.[Order]      o   ON o.OrderID     = ol.OrderID
    JOIN       dbo.ProductVariant pv ON pv.VariantID = ol.VariantID
    JOIN       dbo.Product      p   ON p.ProductID   = pv.ProductID
    JOIN       dbo.Category     cat ON cat.CategoryID = p.CategoryID
    WHERE      o.OrderStatus NOT IN ('CANCELLED')
      AND      o.PlacedAt >= DATEADD(MONTH, -6, SYSUTCDATETIME())
    GROUP BY   cat.CategoryName, FORMAT(o.PlacedAt, 'yyyy-MM')
)
SELECT *
FROM MonthlyCategoryRevenue
PIVOT (
    SUM(Revenue)
    FOR YearMonth IN (
        -- These would be generated dynamically in production via dynamic SQL
        [2024-01],[2024-02],[2024-03],[2024-04],[2024-05],[2024-06]
    )
) AS pvt
ORDER BY CategoryName;
GO

-- =============================================================================
-- QUERY 4: Pareto / ABC Analysis — which products drive 80% of revenue?
-- =============================================================================
WITH ProductRevenue AS (
    SELECT
        p.ProductID,
        p.ProductName,
        cat.CategoryName,
        ROUND(SUM(ol.LineTotal), 2) AS Revenue
    FROM       dbo.OrderLine    ol
    JOIN       dbo.[Order]      o   ON o.OrderID     = ol.OrderID
    JOIN       dbo.ProductVariant pv ON pv.VariantID = ol.VariantID
    JOIN       dbo.Product      p   ON p.ProductID   = pv.ProductID
    JOIN       dbo.Category     cat ON cat.CategoryID = p.CategoryID
    WHERE      o.OrderStatus NOT IN ('CANCELLED')
    GROUP BY   p.ProductID, p.ProductName, cat.CategoryName
),
Ranked AS (
    SELECT
        *,
        SUM(Revenue) OVER ()                                AS TotalRevenue,
        SUM(Revenue) OVER (ORDER BY Revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeRevenue,
        ROUND(100.0 * Revenue / SUM(Revenue) OVER (), 2)    AS RevenueSharePct,
        ROUND(100.0 * SUM(Revenue) OVER (ORDER BY Revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            / SUM(Revenue) OVER (), 2)                      AS CumulativeSharePct,
        ROW_NUMBER() OVER (ORDER BY Revenue DESC)           AS RevenueRank
    FROM ProductRevenue
)
SELECT
    RevenueRank,
    ProductName,
    CategoryName,
    Revenue,
    RevenueSharePct,
    CumulativeSharePct,
    -- ABC classification: A = top 80%, B = next 15%, C = bottom 5%
    CASE
        WHEN CumulativeSharePct <= 80  THEN 'A — Core'
        WHEN CumulativeSharePct <= 95  THEN 'B — Supporting'
        ELSE                                'C — Long Tail'
    END AS ABCClass,
    TotalRevenue
FROM Ranked
ORDER BY RevenueRank;
GO

-- =============================================================================
-- QUERY 5: Running totals + customer LTV with RANGE frame
-- =============================================================================
WITH CustomerSpend AS (
    SELECT
        o.CustomerID,
        CAST(o.PlacedAt AS DATE)    AS OrderDate,
        o.TotalAmount
    FROM dbo.[Order] o
    WHERE o.OrderStatus NOT IN ('CANCELLED')
)
SELECT
    cs.CustomerID,
    c.FirstName + ' ' + c.LastName AS CustomerName,
    c.CreatedAt                     AS MemberSince,
    cs.OrderDate,
    cs.TotalAmount,

    -- Running total of spend (lifetime to this order)
    SUM(cs.TotalAmount) OVER (
        PARTITION BY cs.CustomerID
        ORDER BY cs.OrderDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS LifetimeValueToDate,

    -- Order sequence number for this customer
    ROW_NUMBER() OVER (
        PARTITION BY cs.CustomerID
        ORDER BY cs.OrderDate
    ) AS OrderNumber,

    -- Days since last order
    DATEDIFF(DAY,
        LAG(cs.OrderDate) OVER (PARTITION BY cs.CustomerID ORDER BY cs.OrderDate),
        cs.OrderDate
    ) AS DaysSinceLastOrder,

    -- Average order gap (running, uses RANGE which respects tied dates)
    AVG(CAST(DATEDIFF(DAY,
        LAG(cs.OrderDate) OVER (PARTITION BY cs.CustomerID ORDER BY cs.OrderDate),
        cs.OrderDate
    ) AS FLOAT)) OVER (
        PARTITION BY cs.CustomerID
        ORDER BY cs.OrderDate
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS AvgOrderGapDays

FROM       CustomerSpend cs
JOIN       dbo.Customer  c ON c.CustomerID = cs.CustomerID
ORDER BY   cs.CustomerID, cs.OrderDate;
GO

PRINT 'Analytics queries executed.';
GO
