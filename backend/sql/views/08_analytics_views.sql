-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Analytics Views — Window Functions Showcase
-- Demonstrates: LAG/LEAD, NTILE, RANK/DENSE_RANK/ROW_NUMBER, PERCENT_RANK,
--               ROWS/RANGE frames, cumulative totals, month-over-month,
--               cohort retention, running averages, FIRST_VALUE/LAST_VALUE
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- VIEW 1: Revenue trend with MoM growth and running total
--         LAG for period-over-period · running SUM · PERCENT_RANK
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_RevenueMonthlyTrend
AS
WITH MonthlyRevenue AS (
    SELECT
        YEAR(o.PlacedAt)                                    AS RevenueYear,
        MONTH(o.PlacedAt)                                   AS RevenueMonth,
        DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1) AS MonthStart,
        COUNT(DISTINCT o.OrderID)                           AS OrderCount,
        SUM(o.TotalAmount)                                  AS GrossRevenue,
        SUM(o.DiscountAmount)                               AS TotalDiscounts,
        SUM(o.TotalAmount - o.DiscountAmount)               AS NetRevenue,
        COUNT(DISTINCT o.CustomerID)                        AS UniqueCustomers,
        AVG(o.TotalAmount)                                  AS AvgOrderValue
    FROM dbo.[Order] o
    WHERE o.OrderStatus NOT IN ('CANCELLED')
    GROUP BY
        YEAR(o.PlacedAt),
        MONTH(o.PlacedAt),
        DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1)
)
SELECT
    RevenueYear,
    RevenueMonth,
    MonthStart,
    OrderCount,
    GrossRevenue,
    TotalDiscounts,
    NetRevenue,
    UniqueCustomers,
    AvgOrderValue,

    -- Month-over-month revenue (LAG 1 period back)
    LAG(NetRevenue, 1)  OVER (ORDER BY MonthStart)  AS PrevMonthRevenue,
    LAG(OrderCount, 1)  OVER (ORDER BY MonthStart)  AS PrevMonthOrders,

    -- MoM growth %
    CASE WHEN LAG(NetRevenue, 1) OVER (ORDER BY MonthStart) > 0
         THEN ROUND(100.0 * (NetRevenue - LAG(NetRevenue, 1) OVER (ORDER BY MonthStart))
                          / LAG(NetRevenue, 1) OVER (ORDER BY MonthStart), 2)
    END AS MoM_GrowthPct,

    -- Year-over-year (LAG 12 periods back)
    LAG(NetRevenue, 12) OVER (ORDER BY MonthStart)  AS SameMonthLastYear,
    CASE WHEN LAG(NetRevenue, 12) OVER (ORDER BY MonthStart) > 0
         THEN ROUND(100.0 * (NetRevenue - LAG(NetRevenue, 12) OVER (ORDER BY MonthStart))
                           / LAG(NetRevenue, 12) OVER (ORDER BY MonthStart), 2)
    END AS YoY_GrowthPct,

    -- Cumulative (running) revenue total for the year
    SUM(NetRevenue) OVER (
        PARTITION BY RevenueYear
        ORDER BY MonthStart
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS YTD_Revenue,

    -- 3-month rolling average
    AVG(NetRevenue) OVER (
        ORDER BY MonthStart
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS Rolling3MonthAvg,

    -- Rank this month vs all months by revenue
    RANK() OVER (ORDER BY NetRevenue DESC)          AS AllTimeRevenueRank,

    -- Percentile (what % of months had lower revenue?)
    ROUND(100.0 * PERCENT_RANK() OVER (ORDER BY NetRevenue), 1) AS RevenuePercentile

FROM MonthlyRevenue;
GO

-- =============================================================================
-- VIEW 2: Customer cohort analysis — retention by signup month
--         Demonstrates: ROW_NUMBER for deduplication, DATEDIFF bucketing,
--                        cohort cross-join pattern
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_CustomerCohortRetention
AS
WITH CustomerCohorts AS (
    -- Assign each customer to their signup month cohort
    SELECT
        CustomerID,
        DATEFROMPARTS(YEAR(CreatedAt), MONTH(CreatedAt), 1) AS CohortMonth
    FROM dbo.Customer
    WHERE IsActive = 1
),
CustomerOrders AS (
    -- First purchase per customer per month (deduplicated)
    SELECT DISTINCT
        o.CustomerID,
        DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1) AS OrderMonth
    FROM dbo.[Order] o
    WHERE o.OrderStatus NOT IN ('CANCELLED')
),
CohortActivity AS (
    SELECT
        cc.CohortMonth,
        co.OrderMonth,
        -- Months since cohort joined (0 = first month)
        DATEDIFF(MONTH, cc.CohortMonth, co.OrderMonth) AS MonthsAfterJoin,
        COUNT(DISTINCT cc.CustomerID)                  AS ActiveCustomers
    FROM CustomerCohorts    cc
    JOIN CustomerOrders     co ON co.CustomerID = cc.CustomerID
    GROUP BY cc.CohortMonth, co.OrderMonth, DATEDIFF(MONTH, cc.CohortMonth, co.OrderMonth)
),
CohortSizes AS (
    SELECT CohortMonth, COUNT(*) AS CohortSize
    FROM CustomerCohorts
    GROUP BY CohortMonth
)
SELECT
    ca.CohortMonth,
    cs.CohortSize,
    ca.MonthsAfterJoin,
    ca.ActiveCustomers,
    ROUND(100.0 * ca.ActiveCustomers / cs.CohortSize, 1) AS RetentionRate,

    -- Rank cohorts by size
    DENSE_RANK() OVER (ORDER BY cs.CohortSize DESC)  AS CohortSizeRank,

    -- Best-performing month for this cohort
    FIRST_VALUE(ca.ActiveCustomers) OVER (
        PARTITION BY ca.CohortMonth
        ORDER BY ca.ActiveCustomers DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS PeakActiveInCohort

FROM CohortActivity     ca
JOIN CohortSizes        cs ON cs.CohortMonth = ca.CohortMonth;
GO

-- =============================================================================
-- VIEW 3: Product sales ranking — NTILE, RANK, ROW_NUMBER side-by-side
--         Shows the difference between the three ranking functions
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_ProductSalesRanking
AS
WITH ProductRevenue AS (
    SELECT
        p.ProductID,
        p.ProductName,
        cat.CategoryName,
        v.VendorName,
        COUNT(DISTINCT ol.OrderID)      AS OrderCount,
        SUM(ol.Quantity)                AS UnitsSold,
        SUM(ol.LineTotal)               AS TotalRevenue,
        AVG(ol.UnitPrice)               AS AvgSellingPrice,
        AVG(CAST(r.Rating AS FLOAT))    AS AvgRating
    FROM dbo.Product        p
    JOIN dbo.Category       cat ON cat.CategoryID  = p.CategoryID
    JOIN dbo.Vendor         v   ON v.VendorID      = p.VendorID
    JOIN dbo.ProductVariant pv  ON pv.ProductID    = p.ProductID
    JOIN dbo.OrderLine      ol  ON ol.VariantID    = pv.VariantID
    JOIN dbo.[Order]        o   ON o.OrderID       = ol.OrderID
    LEFT JOIN dbo.Review    r   ON r.ProductID     = p.ProductID AND r.IsApproved = 1
    WHERE o.OrderStatus NOT IN ('CANCELLED')
    GROUP BY p.ProductID, p.ProductName, cat.CategoryName, v.VendorName
)
SELECT
    ProductID,
    ProductName,
    CategoryName,
    VendorName,
    OrderCount,
    UnitsSold,
    TotalRevenue,
    AvgSellingPrice,
    ROUND(AvgRating, 2) AS AvgRating,

    -- ROW_NUMBER: unique sequential rank (no ties)
    ROW_NUMBER()  OVER (ORDER BY TotalRevenue DESC) AS RowNum_ByRevenue,

    -- RANK: tied products get same rank, next rank skips (1,1,3)
    RANK()        OVER (ORDER BY TotalRevenue DESC) AS Rank_ByRevenue,

    -- DENSE_RANK: tied products same rank, next rank does NOT skip (1,1,2)
    DENSE_RANK()  OVER (ORDER BY TotalRevenue DESC) AS DenseRank_ByRevenue,

    -- NTILE(4): divides into quartiles — 1=top, 4=bottom
    NTILE(4)      OVER (ORDER BY TotalRevenue DESC) AS RevenueQuartile,
    CASE NTILE(4) OVER (ORDER BY TotalRevenue DESC)
        WHEN 1 THEN 'STAR'
        WHEN 2 THEN 'RISING'
        WHEN 3 THEN 'AVERAGE'
        WHEN 4 THEN 'UNDERPERFORMER'
    END AS ProductTier,

    -- Category-scoped ranking
    RANK() OVER (
        PARTITION BY CategoryName
        ORDER BY TotalRevenue DESC
    ) AS RankWithinCategory,

    -- % contribution to total revenue
    ROUND(100.0 * TotalRevenue / SUM(TotalRevenue) OVER (), 2) AS RevenueSharePct,

    -- Cumulative revenue share (for Pareto analysis — which products = 80% of revenue?)
    ROUND(100.0 *
        SUM(TotalRevenue) OVER (
            ORDER BY TotalRevenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(TotalRevenue) OVER (), 2
    ) AS CumulativeRevenueSharePct

FROM ProductRevenue;
GO

-- =============================================================================
-- VIEW 4: Delivery SLA performance with LEAD for next event prediction
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_DeliverySLAPerformance
AS
WITH ShipmentTimeline AS (
    SELECT
        se.ShipmentID,
        se.EventStatus,
        se.EventAt,
        se.EventLocation,

        -- LEAD: next event for this shipment
        LEAD(se.EventStatus) OVER (PARTITION BY se.ShipmentID ORDER BY se.EventAt) AS NextStatus,
        LEAD(se.EventAt)     OVER (PARTITION BY se.ShipmentID ORDER BY se.EventAt) AS NextEventAt,

        -- LAG: previous event
        LAG(se.EventStatus)  OVER (PARTITION BY se.ShipmentID ORDER BY se.EventAt) AS PrevStatus,
        LAG(se.EventAt)      OVER (PARTITION BY se.ShipmentID ORDER BY se.EventAt) AS PrevEventAt,

        -- Minutes between consecutive events
        DATEDIFF(MINUTE,
            LAG(se.EventAt) OVER (PARTITION BY se.ShipmentID ORDER BY se.EventAt),
            se.EventAt
        ) AS MinutesSincePrevEvent,

        ROW_NUMBER() OVER (PARTITION BY se.ShipmentID ORDER BY se.EventAt) AS EventSequence
    FROM dbo.ShipmentEvent se
)
SELECT
    s.ShipmentID,
    o.OrderID,
    c.FirstName + ' ' + c.LastName  AS CustomerName,
    cour.CourierName,
    s.TrackingNumber,
    s.ShipmentStatus,
    s.EstimatedDelivery,
    s.ActualDelivery,

    -- SLA breach?
    CASE
        WHEN s.ActualDelivery IS NOT NULL
         AND CAST(s.ActualDelivery AS DATE) > s.EstimatedDelivery THEN 1
        WHEN s.ActualDelivery IS NULL
         AND CAST(SYSUTCDATETIME() AS DATE) > s.EstimatedDelivery THEN 1
        ELSE 0
    END AS SLABreached,

    -- Days late
    CASE WHEN s.ActualDelivery IS NOT NULL
         THEN DATEDIFF(DAY, s.EstimatedDelivery, CAST(s.ActualDelivery AS DATE))
         ELSE DATEDIFF(DAY, s.EstimatedDelivery, CAST(SYSUTCDATETIME() AS DATE))
    END AS DaysVsSLA,

    -- Transit time in hours
    DATEDIFF(HOUR, MIN(st.EventAt), MAX(st.EventAt)) AS TotalTransitHours,
    COUNT(DISTINCT st.EventSequence) AS EventCount,

    -- Last known location
    FIRST_VALUE(st.EventLocation) OVER (
        PARTITION BY s.ShipmentID
        ORDER BY st.EventAt DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS LastKnownLocation

FROM dbo.Shipment       s
JOIN dbo.[Order]        o    ON o.OrderID    = s.OrderID
JOIN dbo.Customer       c    ON c.CustomerID = o.CustomerID
JOIN dbo.Courier        cour ON cour.CourierID = s.CourierID
LEFT JOIN ShipmentTimeline st ON st.ShipmentID = s.ShipmentID
GROUP BY
    s.ShipmentID, o.OrderID, c.FirstName, c.LastName,
    cour.CourierName, s.TrackingNumber, s.ShipmentStatus,
    s.EstimatedDelivery, s.ActualDelivery, st.EventLocation, st.EventAt;
GO

PRINT 'Analytics views created.';
GO
