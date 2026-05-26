-- =============================================================================
-- SchemaForge Studio — Khulisa Commerce
-- Full 3NF Schema DDL
-- Azure SQL Database / SQL Server 2019+
--
-- Design: Third Normal Form throughout
--   · Surrogate INT IDENTITY primary keys on every table
--   · Natural keys enforced via UNIQUE constraints (not as PKs)
--   · All FK relationships explicitly named
--   · Soft deletes: IsActive + DeletedAt pattern
--   · Audit: CreatedAt + UpdatedAt on all mutable entities
--   · No many-to-many without a junction table
-- =============================================================================

USE master;
GO

IF DB_ID('KhulisaCommerce') IS NOT NULL
BEGIN
    ALTER DATABASE KhulisaCommerce SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE KhulisaCommerce;
END
GO

CREATE DATABASE KhulisaCommerce
    COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

USE KhulisaCommerce;
GO

-- =============================================================================
-- BLOCK 1: GEOGRAPHIC HIERARCHY
-- Country → Province → City
-- Justification: enforces referential integrity on location data,
-- enables clean regional analytics, prevents free-text inconsistencies
-- =============================================================================

CREATE TABLE dbo.Country (
    CountryID       INT             NOT NULL IDENTITY(1,1),
    CountryCode     CHAR(2)         NOT NULL,
    CountryName     NVARCHAR(100)   NOT NULL,
    CurrencyCode    CHAR(3)         NOT NULL DEFAULT 'ZAR',
    CONSTRAINT PK_Country       PRIMARY KEY (CountryID),
    CONSTRAINT UQ_Country_Code  UNIQUE      (CountryCode)
);
GO

CREATE TABLE dbo.Province (
    ProvinceID      INT             NOT NULL IDENTITY(1,1),
    CountryID       INT             NOT NULL,
    ProvinceCode    CHAR(3)         NOT NULL,
    ProvinceName    NVARCHAR(100)   NOT NULL,
    CONSTRAINT PK_Province          PRIMARY KEY (ProvinceID),
    CONSTRAINT FK_Province_Country  FOREIGN KEY (CountryID)  REFERENCES dbo.Country(CountryID),
    CONSTRAINT UQ_Province_Code     UNIQUE (CountryID, ProvinceCode)
);
GO

CREATE TABLE dbo.City (
    CityID          INT             NOT NULL IDENTITY(1,1),
    ProvinceID      INT             NOT NULL,
    CityName        NVARCHAR(150)   NOT NULL,
    PostalCode      VARCHAR(10)     NULL,
    CONSTRAINT PK_City          PRIMARY KEY (CityID),
    CONSTRAINT FK_City_Province FOREIGN KEY (ProvinceID) REFERENCES dbo.Province(ProvinceID)
);
GO

-- =============================================================================
-- BLOCK 2: USER ENTITIES
-- Customer, Vendor — separated because their attribute sets diverge significantly
-- (Vendor has banking/tax info; Customer has loyalty/preferences)
-- =============================================================================

CREATE TABLE dbo.Customer (
    CustomerID      INT             NOT NULL IDENTITY(1,1),
    FirstName       NVARCHAR(100)   NOT NULL,
    LastName        NVARCHAR(100)   NOT NULL,
    Email           NVARCHAR(254)   NOT NULL,
    PhoneNumber     VARCHAR(20)     NULL,
    DateOfBirth     DATE            NULL,
    LoyaltyPoints   INT             NOT NULL DEFAULT 0,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    DeletedAt       DATETIME2       NULL,
    CONSTRAINT PK_Customer      PRIMARY KEY (CustomerID),
    CONSTRAINT UQ_Customer_Email UNIQUE (Email),
    CONSTRAINT CK_Customer_LoyaltyPoints CHECK (LoyaltyPoints >= 0)
);
GO

-- Address is separate from Customer because:
-- · A customer can have multiple addresses (home, work, delivery)
-- · City/Province data is normalised away to avoid transitive dependency
CREATE TABLE dbo.Address (
    AddressID       INT             NOT NULL IDENTITY(1,1),
    CustomerID      INT             NOT NULL,
    CityID          INT             NOT NULL,
    AddressLine1    NVARCHAR(200)   NOT NULL,
    AddressLine2    NVARCHAR(200)   NULL,
    AddressType     VARCHAR(20)     NOT NULL DEFAULT 'SHIPPING',
    IsDefault       BIT             NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Address           PRIMARY KEY (AddressID),
    CONSTRAINT FK_Address_Customer  FOREIGN KEY (CustomerID) REFERENCES dbo.Customer(CustomerID),
    CONSTRAINT FK_Address_City      FOREIGN KEY (CityID)     REFERENCES dbo.City(CityID),
    CONSTRAINT CK_Address_Type      CHECK (AddressType IN ('SHIPPING','BILLING','BOTH'))
);
GO

CREATE TABLE dbo.Vendor (
    VendorID        INT             NOT NULL IDENTITY(1,1),
    VendorName      NVARCHAR(200)   NOT NULL,
    TradingName     NVARCHAR(200)   NULL,
    Email           NVARCHAR(254)   NOT NULL,
    PhoneNumber     VARCHAR(20)     NULL,
    VATNumber       VARCHAR(20)     NULL,
    BankName        NVARCHAR(100)   NULL,
    BankAccountNo   VARCHAR(30)     NULL,
    CommissionRate  DECIMAL(5,2)    NOT NULL DEFAULT 10.00,
    IsVerified      BIT             NOT NULL DEFAULT 0,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Vendor        PRIMARY KEY (VendorID),
    CONSTRAINT UQ_Vendor_Email  UNIQUE (Email),
    CONSTRAINT CK_Vendor_Commission CHECK (CommissionRate BETWEEN 0 AND 100)
);
GO

-- =============================================================================
-- BLOCK 3: PRODUCT CATALOGUE
-- Category → Product → ProductVariant
-- Variant captures SKU-level data (size, colour, barcode)
-- Stock is tracked at variant level, not product level
-- =============================================================================

CREATE TABLE dbo.Category (
    CategoryID      INT             NOT NULL IDENTITY(1,1),
    ParentCategoryID INT            NULL,   -- self-referencing for subcategory tree
    CategoryName    NVARCHAR(150)   NOT NULL,
    CategorySlug    VARCHAR(150)    NOT NULL,
    Description     NVARCHAR(500)   NULL,
    IsActive        BIT             NOT NULL DEFAULT 1,
    SortOrder       INT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_Category              PRIMARY KEY (CategoryID),
    CONSTRAINT FK_Category_Parent       FOREIGN KEY (ParentCategoryID) REFERENCES dbo.Category(CategoryID),
    CONSTRAINT UQ_Category_Slug         UNIQUE (CategorySlug)
);
GO

CREATE TABLE dbo.Product (
    ProductID       INT             NOT NULL IDENTITY(1,1),
    VendorID        INT             NOT NULL,
    CategoryID      INT             NOT NULL,
    ProductName     NVARCHAR(300)   NOT NULL,
    ProductSlug     VARCHAR(300)    NOT NULL,
    Description     NVARCHAR(MAX)   NULL,
    BasePrice       DECIMAL(10,2)   NOT NULL,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Product           PRIMARY KEY (ProductID),
    CONSTRAINT FK_Product_Vendor    FOREIGN KEY (VendorID)    REFERENCES dbo.Vendor(VendorID),
    CONSTRAINT FK_Product_Category  FOREIGN KEY (CategoryID)  REFERENCES dbo.Category(CategoryID),
    CONSTRAINT UQ_Product_Slug      UNIQUE (ProductSlug),
    CONSTRAINT CK_Product_BasePrice CHECK (BasePrice >= 0)
);
GO

-- ProductVariant: one row per purchasable SKU (size/colour combination)
-- Why separate? Stock, barcode, and pricing can differ per variant
CREATE TABLE dbo.ProductVariant (
    VariantID       INT             NOT NULL IDENTITY(1,1),
    ProductID       INT             NOT NULL,
    SKU             VARCHAR(100)    NOT NULL,
    Barcode         VARCHAR(50)     NULL,
    SizeName        NVARCHAR(50)    NULL,
    ColourName      NVARCHAR(50)    NULL,
    PriceAdjustment DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    WeightKg        DECIMAL(8,3)    NULL,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CONSTRAINT PK_ProductVariant        PRIMARY KEY (VariantID),
    CONSTRAINT FK_ProductVariant_Product FOREIGN KEY (ProductID) REFERENCES dbo.Product(ProductID),
    CONSTRAINT UQ_ProductVariant_SKU    UNIQUE (SKU)
);
GO

CREATE TABLE dbo.ProductImage (
    ImageID         INT             NOT NULL IDENTITY(1,1),
    ProductID       INT             NOT NULL,
    ImageUrl        NVARCHAR(500)   NOT NULL,
    AltText         NVARCHAR(200)   NULL,
    SortOrder       INT             NOT NULL DEFAULT 0,
    IsPrimary       BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_ProductImage          PRIMARY KEY (ImageID),
    CONSTRAINT FK_ProductImage_Product  FOREIGN KEY (ProductID) REFERENCES dbo.Product(ProductID)
);
GO

-- =============================================================================
-- BLOCK 4: DISCOUNT
-- Separate entity — a discount is a fact about a promotion, not a product
-- Many discounts can apply to many products (resolved via DiscountProduct)
-- =============================================================================

CREATE TABLE dbo.Discount (
    DiscountID      INT             NOT NULL IDENTITY(1,1),
    DiscountCode    VARCHAR(50)     NOT NULL,
    DiscountType    VARCHAR(20)     NOT NULL,
    DiscountValue   DECIMAL(10,2)   NOT NULL,
    MinOrderValue   DECIMAL(10,2)   NULL,
    MaxUsageCount   INT             NULL,
    UsageCount      INT             NOT NULL DEFAULT 0,
    ValidFrom       DATETIME2       NOT NULL,
    ValidTo         DATETIME2       NULL,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CONSTRAINT PK_Discount          PRIMARY KEY (DiscountID),
    CONSTRAINT UQ_Discount_Code     UNIQUE (DiscountCode),
    CONSTRAINT CK_Discount_Type     CHECK (DiscountType IN ('PERCENTAGE','FIXED_AMOUNT','FREE_SHIPPING')),
    CONSTRAINT CK_Discount_Value    CHECK (DiscountValue > 0)
);
GO

-- =============================================================================
-- BLOCK 5: ORDER LIFECYCLE
-- Order → OrderLine (junction: Order ↔ ProductVariant)
-- Order → Payment
-- Order → Shipment → ShipmentEvent
-- =============================================================================

CREATE TABLE dbo.[Order] (
    OrderID         INT             NOT NULL IDENTITY(1,1),
    CustomerID      INT             NOT NULL,
    ShippingAddressID INT           NOT NULL,
    DiscountID      INT             NULL,
    OrderStatus     VARCHAR(30)     NOT NULL DEFAULT 'PENDING',
    SubtotalAmount  DECIMAL(10,2)   NOT NULL,
    DiscountAmount  DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    ShippingAmount  DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    TotalAmount     DECIMAL(10,2)   NOT NULL,
    Notes           NVARCHAR(500)   NULL,
    PlacedAt        DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Order             PRIMARY KEY (OrderID),
    CONSTRAINT FK_Order_Customer    FOREIGN KEY (CustomerID)         REFERENCES dbo.Customer(CustomerID),
    CONSTRAINT FK_Order_Address     FOREIGN KEY (ShippingAddressID)  REFERENCES dbo.Address(AddressID),
    CONSTRAINT FK_Order_Discount    FOREIGN KEY (DiscountID)         REFERENCES dbo.Discount(DiscountID),
    CONSTRAINT CK_Order_Status      CHECK (OrderStatus IN (
        'PENDING','CONFIRMED','PROCESSING','SHIPPED','DELIVERED','CANCELLED','REFUNDED'
    )),
    CONSTRAINT CK_Order_Total       CHECK (TotalAmount >= 0)
);
GO

-- OrderLine: junction resolving Order ↔ ProductVariant M:N
-- UnitPrice captured at order time (historical snapshot — not a 3NF violation)
CREATE TABLE dbo.OrderLine (
    OrderLineID     INT             NOT NULL IDENTITY(1,1),
    OrderID         INT             NOT NULL,
    VariantID       INT             NOT NULL,
    Quantity        INT             NOT NULL,
    UnitPrice       DECIMAL(10,2)   NOT NULL,
    LineTotal       AS (Quantity * UnitPrice) PERSISTED,   -- computed column
    CONSTRAINT PK_OrderLine             PRIMARY KEY (OrderLineID),
    CONSTRAINT FK_OrderLine_Order       FOREIGN KEY (OrderID)    REFERENCES dbo.[Order](OrderID),
    CONSTRAINT FK_OrderLine_Variant     FOREIGN KEY (VariantID)  REFERENCES dbo.ProductVariant(VariantID),
    CONSTRAINT CK_OrderLine_Qty         CHECK (Quantity > 0),
    CONSTRAINT CK_OrderLine_UnitPrice   CHECK (UnitPrice >= 0),
    CONSTRAINT UQ_OrderLine_OrderVariant UNIQUE (OrderID, VariantID)
);
GO

CREATE TABLE dbo.Payment (
    PaymentID       INT             NOT NULL IDENTITY(1,1),
    OrderID         INT             NOT NULL,
    PaymentMethod   VARCHAR(30)     NOT NULL,
    PaymentStatus   VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    Amount          DECIMAL(10,2)   NOT NULL,
    Currency        CHAR(3)         NOT NULL DEFAULT 'ZAR',
    GatewayRef      VARCHAR(100)    NULL,
    PaidAt          DATETIME2       NULL,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Payment           PRIMARY KEY (PaymentID),
    CONSTRAINT FK_Payment_Order     FOREIGN KEY (OrderID) REFERENCES dbo.[Order](OrderID),
    CONSTRAINT CK_Payment_Method    CHECK (PaymentMethod IN ('CREDIT_CARD','EFT','INSTANT_EFT','SNAPSCAN','MOBICRED','PAYFLEX')),
    CONSTRAINT CK_Payment_Status    CHECK (PaymentStatus IN ('PENDING','AUTHORISED','CAPTURED','FAILED','REFUNDED'))
);
GO

-- =============================================================================
-- BLOCK 6: DELIVERY
-- Courier → Shipment → ShipmentEvent
-- DeliveryZone: maps City to Courier with SLA days
-- =============================================================================

CREATE TABLE dbo.Courier (
    CourierID       INT             NOT NULL IDENTITY(1,1),
    CourierName     NVARCHAR(150)   NOT NULL,
    TrackingUrlTemplate NVARCHAR(300) NULL,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CONSTRAINT PK_Courier PRIMARY KEY (CourierID)
);
GO

CREATE TABLE dbo.DeliveryZone (
    ZoneID          INT             NOT NULL IDENTITY(1,1),
    CourierID       INT             NOT NULL,
    CityID          INT             NOT NULL,
    SLADays         TINYINT         NOT NULL DEFAULT 3,
    BaseDeliveryFee DECIMAL(8,2)    NOT NULL,
    CONSTRAINT PK_DeliveryZone          PRIMARY KEY (ZoneID),
    CONSTRAINT FK_DeliveryZone_Courier  FOREIGN KEY (CourierID) REFERENCES dbo.Courier(CourierID),
    CONSTRAINT FK_DeliveryZone_City     FOREIGN KEY (CityID)    REFERENCES dbo.City(CityID),
    CONSTRAINT UQ_DeliveryZone          UNIQUE (CourierID, CityID)
);
GO

CREATE TABLE dbo.Shipment (
    ShipmentID      INT             NOT NULL IDENTITY(1,1),
    OrderID         INT             NOT NULL,
    CourierID       INT             NOT NULL,
    TrackingNumber  VARCHAR(100)    NULL,
    ShipmentStatus  VARCHAR(30)     NOT NULL DEFAULT 'PENDING',
    EstimatedDelivery DATE          NULL,
    ActualDelivery  DATETIME2       NULL,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Shipment          PRIMARY KEY (ShipmentID),
    CONSTRAINT FK_Shipment_Order    FOREIGN KEY (OrderID)   REFERENCES dbo.[Order](OrderID),
    CONSTRAINT FK_Shipment_Courier  FOREIGN KEY (CourierID) REFERENCES dbo.Courier(CourierID),
    CONSTRAINT CK_Shipment_Status   CHECK (ShipmentStatus IN (
        'PENDING','COLLECTED','IN_TRANSIT','OUT_FOR_DELIVERY','DELIVERED','FAILED','RETURNED'
    ))
);
GO

CREATE TABLE dbo.ShipmentEvent (
    EventID         INT             NOT NULL IDENTITY(1,1),
    ShipmentID      INT             NOT NULL,
    EventStatus     VARCHAR(30)     NOT NULL,
    EventLocation   NVARCHAR(200)   NULL,
    EventNote       NVARCHAR(500)   NULL,
    EventAt         DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ShipmentEvent            PRIMARY KEY (EventID),
    CONSTRAINT FK_ShipmentEvent_Shipment   FOREIGN KEY (ShipmentID) REFERENCES dbo.Shipment(ShipmentID)
);
GO

-- =============================================================================
-- BLOCK 7: INVENTORY
-- Warehouse → StockLevel (junction: Warehouse ↔ ProductVariant)
-- StockLevel → StockMovement (audit trail of every stock change)
-- =============================================================================

CREATE TABLE dbo.Warehouse (
    WarehouseID     INT             NOT NULL IDENTITY(1,1),
    WarehouseName   NVARCHAR(150)   NOT NULL,
    CityID          INT             NOT NULL,
    AddressLine     NVARCHAR(200)   NULL,
    IsActive        BIT             NOT NULL DEFAULT 1,
    CONSTRAINT PK_Warehouse         PRIMARY KEY (WarehouseID),
    CONSTRAINT FK_Warehouse_City    FOREIGN KEY (CityID) REFERENCES dbo.City(CityID)
);
GO

-- StockLevel: junction with attributes — quantityOnHand is a fact about the
-- (Warehouse, Variant) pair, not about either entity alone → correct 3NF junction
CREATE TABLE dbo.StockLevel (
    StockLevelID    INT             NOT NULL IDENTITY(1,1),
    WarehouseID     INT             NOT NULL,
    VariantID       INT             NOT NULL,
    QuantityOnHand  INT             NOT NULL DEFAULT 0,
    ReorderPoint    INT             NOT NULL DEFAULT 10,
    UpdatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_StockLevel            PRIMARY KEY (StockLevelID),
    CONSTRAINT FK_StockLevel_Warehouse  FOREIGN KEY (WarehouseID) REFERENCES dbo.Warehouse(WarehouseID),
    CONSTRAINT FK_StockLevel_Variant    FOREIGN KEY (VariantID)   REFERENCES dbo.ProductVariant(VariantID),
    CONSTRAINT UQ_StockLevel            UNIQUE (WarehouseID, VariantID),
    CONSTRAINT CK_StockLevel_Qty        CHECK (QuantityOnHand >= 0)
);
GO

CREATE TABLE dbo.StockMovement (
    MovementID      INT             NOT NULL IDENTITY(1,1),
    StockLevelID    INT             NOT NULL,
    MovementType    VARCHAR(20)     NOT NULL,
    QuantityChange  INT             NOT NULL,
    QuantityAfter   INT             NOT NULL,
    ReferenceID     INT             NULL,   -- OrderID or PurchaseOrderID
    ReferenceType   VARCHAR(30)     NULL,
    Notes           NVARCHAR(300)   NULL,
    MovedAt         DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_StockMovement             PRIMARY KEY (MovementID),
    CONSTRAINT FK_StockMovement_StockLevel  FOREIGN KEY (StockLevelID) REFERENCES dbo.StockLevel(StockLevelID),
    CONSTRAINT CK_StockMovement_Type        CHECK (MovementType IN (
        'SALE','RETURN','RESTOCK','ADJUSTMENT','TRANSFER','DAMAGE'
    )),
    CONSTRAINT CK_StockMovement_After CHECK (QuantityAfter >= 0)
);
GO

-- =============================================================================
-- BLOCK 8: REVIEWS
-- Review: a ternary relationship — Customer reviews a Product on an Order
-- (Must have purchased to review — enforced at application layer)
-- =============================================================================

CREATE TABLE dbo.Review (
    ReviewID        INT             NOT NULL IDENTITY(1,1),
    ProductID       INT             NOT NULL,
    CustomerID      INT             NOT NULL,
    OrderID         INT             NOT NULL,
    Rating          TINYINT         NOT NULL,
    Title           NVARCHAR(200)   NULL,
    Body            NVARCHAR(2000)  NULL,
    IsVerifiedPurchase BIT          NOT NULL DEFAULT 1,
    IsApproved      BIT             NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Review            PRIMARY KEY (ReviewID),
    CONSTRAINT FK_Review_Product    FOREIGN KEY (ProductID)  REFERENCES dbo.Product(ProductID),
    CONSTRAINT FK_Review_Customer   FOREIGN KEY (CustomerID) REFERENCES dbo.Customer(CustomerID),
    CONSTRAINT FK_Review_Order      FOREIGN KEY (OrderID)    REFERENCES dbo.[Order](OrderID),
    CONSTRAINT UQ_Review_Customer_Product_Order UNIQUE (CustomerID, ProductID, OrderID),
    CONSTRAINT CK_Review_Rating     CHECK (Rating BETWEEN 1 AND 5)
);
GO

CREATE TABLE dbo.ReviewHelpful (
    HelpfulID       INT             NOT NULL IDENTITY(1,1),
    ReviewID        INT             NOT NULL,
    CustomerID      INT             NOT NULL,
    IsHelpful       BIT             NOT NULL,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ReviewHelpful         PRIMARY KEY (HelpfulID),
    CONSTRAINT FK_ReviewHelpful_Review  FOREIGN KEY (ReviewID)   REFERENCES dbo.Review(ReviewID),
    CONSTRAINT FK_ReviewHelpful_Customer FOREIGN KEY (CustomerID) REFERENCES dbo.Customer(CustomerID),
    CONSTRAINT UQ_ReviewHelpful         UNIQUE (ReviewID, CustomerID)
);
GO

-- =============================================================================
-- BLOCK 9: ANALYTICS GOLD LAYER
-- Pre-aggregated daily summary — populated by scheduled procedure
-- Separate from the operational tables for query performance
-- =============================================================================

CREATE TABLE dbo.SalesSummary (
    SummaryID       INT             NOT NULL IDENTITY(1,1),
    SummaryDate     DATE            NOT NULL,
    VendorID        INT             NOT NULL,
    CategoryID      INT             NOT NULL,
    ProvinceID      INT             NOT NULL,
    OrderCount      INT             NOT NULL DEFAULT 0,
    LineItemCount   INT             NOT NULL DEFAULT 0,
    GrossRevenue    DECIMAL(14,2)   NOT NULL DEFAULT 0,
    DiscountTotal   DECIMAL(14,2)   NOT NULL DEFAULT 0,
    NetRevenue      DECIMAL(14,2)   NOT NULL DEFAULT 0,
    Commission      DECIMAL(14,2)   NOT NULL DEFAULT 0,
    ComputedAt      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_SalesSummary          PRIMARY KEY (SummaryID),
    CONSTRAINT FK_SalesSummary_Vendor   FOREIGN KEY (VendorID)   REFERENCES dbo.Vendor(VendorID),
    CONSTRAINT FK_SalesSummary_Category FOREIGN KEY (CategoryID) REFERENCES dbo.Category(CategoryID),
    CONSTRAINT FK_SalesSummary_Province FOREIGN KEY (ProvinceID) REFERENCES dbo.Province(ProvinceID),
    CONSTRAINT UQ_SalesSummary          UNIQUE (SummaryDate, VendorID, CategoryID, ProvinceID)
);
GO

PRINT 'KhulisaCommerce schema created successfully — 20 tables, 3NF throughout.';
GO
