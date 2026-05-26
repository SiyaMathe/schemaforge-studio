USE KhulisaCommerce;
GO

-- =============================================================================
-- CUSTOMER INDEXES
-- =============================================================================

CREATE UNIQUE NONCLUSTERED INDEX IX_Customer_Email
    ON dbo.Customer (Email)
    WHERE IsActive = 1;
GO

CREATE NONCLUSTERED INDEX IX_Customer_CreatedAt
    ON dbo.Customer (CreatedAt DESC)
    INCLUDE (FirstName, LastName, Email, LoyaltyPoints);
GO

-- =============================================================================
-- PRODUCT CATALOG INDEXES
-- =============================================================================

CREATE NONCLUSTERED INDEX IX_Product_Category_Active
    ON dbo.Product (CategoryID, IsActive)
    INCLUDE (ProductName, ProductSlug, BasePrice, VendorID)
    WHERE IsActive = 1;
GO

CREATE NONCLUSTERED INDEX IX_Product_Vendor
    ON dbo.Product (VendorID, IsActive)
    INCLUDE (ProductName, BasePrice, CreatedAt);
GO

CREATE UNIQUE NONCLUSTERED INDEX IX_ProductVariant_SKU
    ON dbo.ProductVariant (SKU)
    WHERE IsActive = 1;
GO

-- =============================================================================
-- ORDER INDEXES
-- =============================================================================

CREATE NONCLUSTERED INDEX IX_Order_Customer_PlacedAt
    ON dbo.[Order] (CustomerID, PlacedAt DESC)
    INCLUDE (OrderStatus, TotalAmount);
GO

CREATE NONCLUSTERED INDEX IX_Order_Status_PlacedAt
    ON dbo.[Order] (OrderStatus, PlacedAt DESC)
    INCLUDE (CustomerID, TotalAmount);
GO

-- Open orders only filter 
-- Explicitly wrapping the filtered columns in bracket identifiers to force engine matching
CREATE NONCLUSTERED INDEX IX_Order_Open
    ON dbo.[Order] (PlacedAt DESC)
    INCLUDE (CustomerID, OrderStatus, TotalAmount)
    WHERE [OrderStatus] <> 'DELIVERED' AND [OrderStatus] <> 'CANCELLED' AND [OrderStatus] <> 'REFUNDED';
GO

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

-- Low-stock alert (Optimized Composite Coverage Scan — Option A)
CREATE NONCLUSTERED INDEX IX_StockLevel_LowStock
    ON dbo.StockLevel (QuantityOnHand, ReorderPoint)
    INCLUDE (WarehouseID, VariantID);
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

CREATE NONCLUSTERED INDEX IX_SalesSummary_Date_Vendor
    ON dbo.SalesSummary (SummaryDate DESC, VendorID)
    INCLUDE (CategoryID, ProvinceID, NetRevenue, OrderCount);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_SalesSummary
    ON dbo.SalesSummary;
GO

PRINT 'Indexes and performance constraints applied successfully.';
GO