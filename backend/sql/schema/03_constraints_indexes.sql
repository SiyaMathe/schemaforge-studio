-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Indexes & Performance Constraints
-- =============================================================================

USE KhulisaCommerce;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CUSTOMER INDEXES
-- =============================================================================

-- Email lookup for active customer records
CREATE UNIQUE NONCLUSTERED INDEX IX_Customer_Email
    ON dbo.Customer (Email)
    WHERE IsActive = 1;
GO

-- Customer order history lookup
CREATE NONCLUSTERED INDEX IX_Customer_CreatedAt
    ON dbo.Customer (CreatedAt DESC)
    INCLUDE (FirstName, LastName, Email, LoyaltyPoints);
GO

-- =============================================================================
-- PRODUCT CATALOG INDEXES
-- =============================================================================

-- Product browse by category
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
-- ORDER INDEXES
-- =============================================================================

-- Customer order history
CREATE NONCLUSTERED INDEX IX_Order_Customer_PlacedAt
    ON dbo.[Order] (CustomerID, PlacedAt DESC)
    INCLUDE (OrderStatus, TotalAmount);
GO

-- Order status dashboard
CREATE NONCLUSTERED INDEX IX_Order_Status_PlacedAt
    ON dbo.[Order] (OrderStatus, PlacedAt DESC)
    INCLUDE (CustomerID, TotalAmount);
GO

-- Open orders only filter using clean character literals
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

-- Stock level lookup by warehouse + variant
CREATE NONCLUSTERED INDEX IX_StockLevel_Warehouse_Variant
    ON dbo.StockLevel (WarehouseID, VariantID)
    INCLUDE (QuantityOnHand, ReorderPoint);
GO

-- Low-stock alert
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

-- Clustered Columnstore Index for unified aggregate scanning
CREATE CLUSTERED COLUMNSTORE INDEX CCI_SalesSummary
    ON dbo.SalesSummary;
GO

PRINT 'Indexes and performance constraints applied successfully.';
GO