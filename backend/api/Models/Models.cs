namespace KhulisaQuery.Api.Models;

// ── Order models ──────────────────────────────────────────────────────────────

public record OrderSummary(
    int      OrderID,
    string   CustomerName,
    string   CustomerEmail,
    string   OrderStatus,
    decimal  SubtotalAmount,
    decimal  DiscountAmount,
    decimal  TotalAmount,
    DateTime PlacedAt,
    DateTime UpdatedAt
);

public record PlaceOrderRequest(
    int     CustomerID,
    int     ShippingAddressID,
    string? DiscountCode,
    IEnumerable<OrderLineRequest> Lines
);

public record OrderLineRequest(int VariantID, int Quantity);

public record PlaceOrderResponse(
    int     OrderID,
    decimal TotalAmount,
    string  Message
);

public record UpdateOrderStatusRequest(
    string  NewStatus,
    int?    CourierID      = null,
    string? TrackingNumber = null,
    string? Notes          = null
);

// ── Inventory models ──────────────────────────────────────────────────────────

public record LowStockItem(
    string  WarehouseName,
    string  SKU,
    string  ProductName,
    string? SizeName,
    string? ColourName,
    int     QuantityOnHand,
    int     ReorderPoint,
    int     Shortfall,
    string  StockStatus,
    string  VendorName,
    string  VendorEmail
);

public record RestockRequest(
    int WarehouseID,
    IEnumerable<RestockLine> Lines
);

public record RestockLine(int VariantID, int Quantity);

public record TransferRequest(
    int FromWarehouseID,
    int ToWarehouseID,
    int VariantID,
    int Quantity,
    string? Notes = null
);

// ── Analytics models ──────────────────────────────────────────────────────────

public record MonthlyTrend(
    int      RevenueYear,
    int      RevenueMonth,
    int      OrderCount,
    decimal  GrossRevenue,
    decimal  NetRevenue,
    int      UniqueCustomers,
    decimal  AvgOrderValue,
    decimal? MoM_GrowthPct,
    decimal? YoY_GrowthPct,
    decimal  YTD_Revenue,
    decimal  Rolling3MonthAvg,
    int      AllTimeRevenueRank
);

public record ProductRanking(
    int     ProductID,
    string  ProductName,
    string  CategoryName,
    string  VendorName,
    int     OrderCount,
    int     UnitsSold,
    decimal TotalRevenue,
    decimal AvgSellingPrice,
    double? AvgRating,
    int     RowNum_ByRevenue,
    int     Rank_ByRevenue,
    int     DenseRank_ByRevenue,
    int     RevenueQuartile,
    string  ProductTier,
    int     RankWithinCategory,
    decimal RevenueSharePct,
    decimal CumulativeRevenueSharePct
);

// ── Shared pagination wrapper ─────────────────────────────────────────────────

public record PagedResult<T>(
    IEnumerable<T> Data,
    int TotalCount,
    int PageNumber,
    int PageSize,
    int TotalPages
)
{
    public static PagedResult<T> Create(IEnumerable<T> data, int totalCount, int pageNumber, int pageSize)
        => new(data, totalCount, pageNumber, pageSize,
               (int)Math.Ceiling((double)totalCount / pageSize));
}
