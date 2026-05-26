-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Operational Views
-- Demonstrates: multi-table JOINs, CASE expressions, subqueries,
--               EXISTS / NOT EXISTS, scalar subqueries, COALESCE
-- =============================================================================

USE KhulisaCommerce;
GO

-- =============================================================================
-- VIEW 1: Full order detail — joins 8 tables, operational dashboard
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_OrderDetail
AS
SELECT
    o.OrderID,
    o.PlacedAt,
    o.OrderStatus,

    -- Customer
    o.CustomerID,
    c.FirstName + ' ' + c.LastName     AS CustomerName,
    c.Email                             AS CustomerEmail,
    c.LoyaltyPoints,

    -- Shipping address (denormalised for display)
    ci.CityName                         AS ShippingCity,
    pr.ProvinceName                     AS ShippingProvince,
    addr.AddressLine1                   AS ShippingAddress,

    -- Financials
    o.SubtotalAmount,
    o.DiscountAmount,
    o.ShippingAmount,
    o.TotalAmount,

    -- Discount
    d.DiscountCode,
    d.DiscountType,
    d.DiscountValue,

    -- Payment (most recent)
    pay.PaymentMethod,
    pay.PaymentStatus,
    pay.PaidAt,

    -- Delivery
    ship.TrackingNumber,
    ship.ShipmentStatus,
    ship.EstimatedDelivery,
    cour.CourierName,

    -- Line summary (scalar subquery — avoids GROUP BY on whole row)
    (SELECT COUNT(*)        FROM dbo.OrderLine ol WHERE ol.OrderID = o.OrderID) AS LineCount,
    (SELECT SUM(ol.Quantity) FROM dbo.OrderLine ol WHERE ol.OrderID = o.OrderID) AS TotalItems,

    -- Is delayed? (business rule: estimated + 1 day past, not yet delivered)
    CASE
        WHEN ship.EstimatedDelivery IS NOT NULL
         AND ship.ActualDelivery    IS NULL
         AND CAST(SYSUTCDATETIME() AS DATE) > ship.EstimatedDelivery
         AND ship.ShipmentStatus NOT IN ('DELIVERED','RETURNED')
        THEN 1 ELSE 0
    END AS IsDelayed,

    o.UpdatedAt

FROM       dbo.[Order]  o
JOIN       dbo.Customer c    ON c.CustomerID   = o.CustomerID
JOIN       dbo.Address  addr ON addr.AddressID = o.ShippingAddressID
JOIN       dbo.City     ci   ON ci.CityID      = addr.CityID
JOIN       dbo.Province pr   ON pr.ProvinceID  = ci.ProvinceID
LEFT JOIN  dbo.Discount d    ON d.DiscountID   = o.DiscountID
LEFT JOIN  dbo.Payment  pay  ON pay.OrderID    = o.OrderID
LEFT JOIN  dbo.Shipment ship ON ship.OrderID   = o.OrderID
LEFT JOIN  dbo.Courier  cour ON cour.CourierID = ship.CourierID;
GO

-- =============================================================================
-- VIEW 2: Product catalogue with computed effective price & stock status
--         Demonstrates: CROSS APPLY, nested subqueries, COALESCE
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_ProductCatalogue
AS
SELECT
    p.ProductID,
    p.ProductName,
    p.ProductSlug,
    p.Description,
    p.BasePrice,

    -- Category breadcrumb (self-join on Category)
    COALESCE(parent.CategoryName + ' > ', '') + cat.CategoryName AS CategoryPath,
    cat.CategoryName,
    cat.CategoryID,

    -- Vendor
    v.VendorID,
    v.VendorName,
    v.CommissionRate,

    -- Stock aggregates across all warehouses
    stock.TotalStock,
    stock.WarehouseCount,

    -- In-stock flag
    CASE WHEN stock.TotalStock > 0 THEN 1 ELSE 0 END AS InStock,

    -- Review aggregates
    reviews.ReviewCount,
    reviews.AvgRating,
    reviews.LatestReviewAt,

    -- Active discount (if any)
    disc.DiscountCode       AS ActiveDiscountCode,
    disc.DiscountType       AS ActiveDiscountType,
    disc.DiscountValue      AS ActiveDiscountValue,
    CASE disc.DiscountType
        WHEN 'PERCENTAGE'   THEN p.BasePrice * (1 - disc.DiscountValue / 100)
        WHEN 'FIXED_AMOUNT' THEN GREATEST(0, p.BasePrice - disc.DiscountValue)
        ELSE p.BasePrice
    END                     AS EffectivePrice,

    p.IsActive,
    p.CreatedAt,
    p.UpdatedAt

FROM dbo.Product    p
JOIN dbo.Category   cat     ON cat.CategoryID   = p.CategoryID
JOIN dbo.Vendor     v       ON v.VendorID       = p.VendorID
LEFT JOIN dbo.Category parent ON parent.CategoryID = cat.ParentCategoryID

-- Stock summary (CROSS APPLY so each product gets one aggregated row)
CROSS APPLY (
    SELECT
        ISNULL(SUM(sl.QuantityOnHand), 0) AS TotalStock,
        COUNT(DISTINCT sl.WarehouseID)    AS WarehouseCount
    FROM dbo.ProductVariant pv
    JOIN dbo.StockLevel     sl ON sl.VariantID = pv.VariantID
    WHERE pv.ProductID = p.ProductID
      AND pv.IsActive  = 1
) AS stock

-- Review summary
CROSS APPLY (
    SELECT
        COUNT(*)                    AS ReviewCount,
        AVG(CAST(Rating AS FLOAT))  AS AvgRating,
        MAX(CreatedAt)              AS LatestReviewAt
    FROM dbo.Review r
    WHERE r.ProductID  = p.ProductID
      AND r.IsApproved = 1
) AS reviews

-- Active discount (most generous one if multiple exist — MIN effective price logic)
OUTER APPLY (
    SELECT TOP 1
        DiscountCode, DiscountType, DiscountValue
    FROM dbo.Discount
    WHERE IsActive   = 1
      AND ValidFrom <= SYSUTCDATETIME()
      AND (ValidTo IS NULL OR ValidTo >= SYSUTCDATETIME())
    ORDER BY DiscountValue DESC
) AS disc;
GO

-- =============================================================================
-- VIEW 3: Customer 360 — full snapshot of a customer's activity
--         Demonstrates: multiple scalar subqueries, DATEDIFF, EXISTS
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_Customer360
AS
SELECT
    c.CustomerID,
    c.FirstName,
    c.LastName,
    c.FirstName + ' ' + c.LastName     AS FullName,
    c.Email,
    c.PhoneNumber,
    c.LoyaltyPoints,
    c.IsActive,
    c.CreatedAt                         AS MemberSince,
    DATEDIFF(DAY, c.CreatedAt, SYSUTCDATETIME()) AS DaysSinceMembership,

    -- Order stats
    orders.TotalOrders,
    orders.TotalSpend,
    orders.AvgOrderValue,
    orders.LastOrderAt,
    orders.CancelledOrders,

    -- Delivery stats
    orders.DeliveredOrders,
    CASE WHEN orders.TotalOrders > 0
         THEN CAST(orders.DeliveredOrders AS FLOAT) / orders.TotalOrders * 100
    END AS DeliverySuccessRate,

    -- Address count
    (SELECT COUNT(*) FROM dbo.Address a WHERE a.CustomerID = c.CustomerID) AS AddressCount,

    -- Has written any approved review?
    CASE WHEN EXISTS (
        SELECT 1 FROM dbo.Review r
        WHERE r.CustomerID = c.CustomerID AND r.IsApproved = 1
    ) THEN 1 ELSE 0 END AS HasReviewed,

    -- Segment
    CASE
        WHEN orders.TotalSpend >= 50000                         THEN 'VIP'
        WHEN orders.TotalSpend >= 10000                         THEN 'LOYAL'
        WHEN orders.TotalOrders >= 3                            THEN 'RETURNING'
        WHEN orders.TotalOrders = 1                             THEN 'NEW'
        WHEN orders.LastOrderAt < DATEADD(DAY,-90,SYSUTCDATETIME()) THEN 'AT_RISK'
        ELSE 'INACTIVE'
    END AS CustomerSegment

FROM dbo.Customer c
CROSS APPLY (
    SELECT
        COUNT(*)                                                    AS TotalOrders,
        ISNULL(SUM(TotalAmount), 0)                                 AS TotalSpend,
        ISNULL(AVG(TotalAmount), 0)                                 AS AvgOrderValue,
        MAX(PlacedAt)                                               AS LastOrderAt,
        SUM(CASE WHEN OrderStatus = 'DELIVERED'  THEN 1 ELSE 0 END) AS DeliveredOrders,
        SUM(CASE WHEN OrderStatus = 'CANCELLED'  THEN 1 ELSE 0 END) AS CancelledOrders
    FROM dbo.[Order] o
    WHERE o.CustomerID = c.CustomerID
) AS orders;
GO

-- =============================================================================
-- VIEW 4: Vendor performance dashboard
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_VendorPerformance
AS
WITH Last30Days AS (
    SELECT
        p.VendorID,
        COUNT(DISTINCT ol.OrderID)          AS Orders30d,
        SUM(ol.LineTotal)                   AS Revenue30d,
        SUM(ol.Quantity)                    AS UnitsSold30d,
        AVG(CAST(r.Rating AS FLOAT))        AS AvgRating30d
    FROM dbo.OrderLine      ol
    JOIN dbo.ProductVariant pv  ON pv.VariantID = ol.VariantID
    JOIN dbo.Product        p   ON p.ProductID  = pv.ProductID
    JOIN dbo.[Order]        o   ON o.OrderID    = ol.OrderID
    LEFT JOIN dbo.Review    r   ON r.ProductID  = p.ProductID
                                AND r.IsApproved = 1
    WHERE o.PlacedAt >= DATEADD(DAY, -30, SYSUTCDATETIME())
      AND o.OrderStatus NOT IN ('CANCELLED')
    GROUP BY p.VendorID
)
SELECT
    v.VendorID,
    v.VendorName,
    v.Email,
    v.CommissionRate,
    v.IsVerified,
    v.IsActive,
    v.CreatedAt,

    -- Product counts
    (SELECT COUNT(*) FROM dbo.Product p WHERE p.VendorID = v.VendorID AND p.IsActive = 1) AS ActiveProducts,

    -- All-time stats
    alltime.TotalOrders,
    alltime.TotalRevenue,
    alltime.TotalCommission,

    -- 30-day stats
    ISNULL(l30.Orders30d,    0) AS Orders30d,
    ISNULL(l30.Revenue30d,   0) AS Revenue30d,
    ISNULL(l30.UnitsSold30d, 0) AS UnitsSold30d,
    ISNULL(l30.AvgRating30d, 0) AS AvgRating30d

FROM dbo.Vendor v

CROSS APPLY (
    SELECT
        COUNT(DISTINCT ol.OrderID)  AS TotalOrders,
        SUM(ol.LineTotal)           AS TotalRevenue,
        SUM(ol.LineTotal * v.CommissionRate / 100) AS TotalCommission
    FROM dbo.OrderLine      ol
    JOIN dbo.ProductVariant pv  ON pv.VariantID = ol.VariantID
    JOIN dbo.Product        p   ON p.ProductID  = pv.ProductID
    JOIN dbo.[Order]        o   ON o.OrderID    = ol.OrderID
    WHERE p.VendorID = v.VendorID
      AND o.OrderStatus NOT IN ('CANCELLED')
) AS alltime

LEFT JOIN Last30Days l30 ON l30.VendorID = v.VendorID;
GO

PRINT 'Operational views created.';
GO
