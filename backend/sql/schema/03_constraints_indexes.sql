-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Indexes & Performance Constraints
-- Demonstrates: covering indexes, filtered indexes, composite indexes,
--               partial indexes, columnstore for analytics
-- =============================================================================

USE KhulisaCommerce;
GO

-- Environmental settings strictly required for creating indexes over tables
-- containing persisted computed columns or filtered constraints.
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- CUSTOMER INDEXES
-- =============================================================================

-- Email lookup (login, uniqueness check)
CREATE UNIQUE NONCLUSTERED INDEX IX_Customer_Email
    ON dbo.Customer (Email)
    WHERE IsActive = 1;   -- filtered: only active customers
GO

-- Customer order history lookup
CREATE NONCLUSTERED INDEX IX_Customer_CreatedAt
    ON dbo.Customer (CreatedAt DESC)
    INCLUDE (FirstName, LastName, Email, LoyaltyPoints);
GO

-- =============================================================================
-- PRODUCT CATALOG INDEXES
-- =============================================================================

-- Product browse by category (most common catalogue query)
CREATE NONCLUSTERED INDEX IX_Product_Category_Active
    ON dbo.Product (CategoryID, IsActive)
    INCLUDE (ProductName, ProductSlug, BasePrice, VendorID)
    WHERE IsActive = 1;
GO

-- Vendor product management
CREATE NONCLUSTERED INDEX IX_Product_Vendor
    ON dbo.Product (VendorID, IsActive)
    INCLUDE (ProductName, BasePrice, CreatedAt);
GO

-- SKU lookup for inventory / order line creation
CREATE UNIQUE NONCLUSTERED INDEX IX_ProductVariant_SKU
    ON dbo.ProductVariant (SKU)
    WHERE IsActive = 1;
GO

-- =============================================================================
-- ORDER INDEXES — high-traffic, optimise for common read patterns
-- =============================================================================

-- Customer order history (descending — most recent first)
CREATE NONCLUSTERED INDEX IX_Order_Customer_PlacedAt
    ON dbo.[Order] (CustomerID, PlacedAt DESC)
    INCLUDE (OrderStatus, TotalAmount);
GO

-- Order status dashboard (operations team view)
CREATE NONCLUSTERED INDEX IX_Order_Status_PlacedAt
    ON dbo.[Order] (OrderStatus, PlacedAt DESC)
    INCLUDE (CustomerID, TotalAmount);
GO

-- Open orders only (filtered index — dramatically smaller, faster for ops)
-- Fixed string literals to single quotes to align with QUOTED_IDENTIFIER ON
CREATE NONCLUSTERED INDEX IX_Order_Open
    ON dbo.[Order] (PlacedAt DESC)
    INCLUDE (CustomerID, OrderStatus, TotalAmount)
    WHERE OrderStatus NOT IN ('DELIVERED', 'CANCELLED', 'REFUNDED');
GO

-- OrderLine: lookups from both sides of the junction
CREATE NONCLUSTERED INDEX IX_OrderLine_Order
    ON dbo.OrderLine (OrderID)
    INCLUDE (VariantID, Quantity, UnitPrice, LineTotal);
GO

CREATE NONCLUSTERED INDEX IX_OrderLine_Variant
    ON dbo.OrderLine (VariantID)
    INCLUDE (OrderID, Quantity, UnitPrice);
GO

-- =============================================================================
-- PAYMENT INDEXES
-- =============================================================================

CREATE NONCLUSTERED INDEX IX_Payment_Order
    ON dbo.Payment (OrderID, PaymentStatus)
    INCLUDE (Amount, PaymentMethod, PaidAt);
GO

-- Failed payments — filtered for quick alerting
CREATE NONCLUSTERED INDEX IX_Payment_Failed
    ON dbo.Payment (CreatedAt DESC)
    WHERE PaymentStatus = 'FAILED';
GO

-- =============================================================================
-- INVENTORY INDEXES
-- =============================================================================

-- Stock level lookup by warehouse + variant (the common join path)
CREATE NONCLUSTERED INDEX IX_StockLevel_Warehouse_Variant
    ON dbo.StockLevel (WarehouseID, VariantID)
    INCLUDE (QuantityOnHand, ReorderPoint);
GO

-- Low-stock alert (filtered — only rows needing attention)
CREATE NONCLUSTERED INDEX IX_StockLevel_LowStock
    ON dbo.StockLevel (QuantityOnHand)
    INCLUDE (WarehouseID, VariantID, ReorderPoint)
    WHERE QuantityOnHand <= ReorderPoint;
GO

-- Stock movement audit trail
CREATE NONCLUSTERED INDEX IX_StockMovement_StockLevel_Date
    ON dbo.StockMovement (StockLevelID, MovedAt DESC)
    INCLUDE (MovementType, QuantityChange, QuantityAfter);
GO

-- =============================================================================
-- DELIVERY INDEXES
-- =============================================================================

CREATE NONCLUSTERED INDEX IX_Shipment_Order
    ON dbo.Shipment (OrderID, ShipmentStatus)
    INCLUDE (CourierID, TrackingNumber, EstimatedDelivery);
GO

CREATE NONCLUSTERED INDEX IX_ShipmentEvent_Shipment
    ON dbo.ShipmentEvent (ShipmentID, EventAt DESC);
GO

-- =============================================================================
-- REVIEW INDEXES
-- =============================================================================

CREATE NONCLUSTERED INDEX IX_Review_Product_Approved
    ON dbo.Review (ProductID, IsApproved, CreatedAt DESC)
    INCLUDE (Rating, Title, CustomerID)
    WHERE IsApproved = 1;
GO

-- =============================================================================
-- ANALYTICS INDEXES
-- =============================================================================

-- SalesSummary: date range scans for dashboards
CREATE NONCLUSTERED INDEX IX_SalesSummary_Date_Vendor
    ON dbo.SalesSummary (SummaryDate DESC, VendorID)
    INCLUDE (CategoryID, ProvinceID, NetRevenue, OrderCount);
GO

-- Columnstore index on SalesSummary for fast analytical aggregations
-- (columnstore compresses and batch-processes aggregations extremely efficiently)
CREATE NONCLUSTERED COLUMNSTORE INDEX CCI_SalesSummary
    ON dbo.SalesSummary (SummaryDate, VendorID, CategoryID, ProvinceID,
                         OrderCount, LineItemCount, GrossRevenue, NetRevenue, Commission);
GO

PRINT 'Indexes and performance constraints applied successfully.';
GO