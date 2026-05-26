using System.Data;
using System.Text.Json;
using KhulisaQuery.Api.Models;
using Microsoft.Data.SqlClient;

namespace KhulisaQuery.Api.Services;

public interface IOrderService
{
    Task<PagedResult<OrderSummary>> SearchOrdersAsync(
        int? customerId, string? status, DateTime? fromDate, DateTime? toDate,
        decimal? minAmount, decimal? maxAmount, int pageNumber, int pageSize,
        CancellationToken ct = default);

    Task<PlaceOrderResponse> PlaceOrderAsync(PlaceOrderRequest request, CancellationToken ct = default);

    Task UpdateStatusAsync(int orderId, UpdateOrderStatusRequest request, CancellationToken ct = default);
}

public class OrderService : IOrderService
{
    private readonly IDbConnectionFactory _db;
    private readonly ILogger<OrderService> _log;

    public OrderService(IDbConnectionFactory db, ILogger<OrderService> log)
        => (_db, _log) = (db, log);

    public async Task<PagedResult<OrderSummary>> SearchOrdersAsync(
        int? customerId, string? status, DateTime? fromDate, DateTime? toDate,
        decimal? minAmount, decimal? maxAmount, int pageNumber, int pageSize,
        CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_SearchOrders", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 30
        };

        cmd.Parameters.AddWithValue("@CustomerID",  (object?)customerId  ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@OrderStatus", (object?)status      ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@FromDate",    (object?)fromDate     ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ToDate",      (object?)toDate       ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@MinAmount",   (object?)minAmount    ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@MaxAmount",   (object?)maxAmount    ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@PageNumber",  pageNumber);
        cmd.Parameters.AddWithValue("@PageSize",    pageSize);

        var totalParam = cmd.Parameters.Add("@TotalCount", SqlDbType.Int);
        totalParam.Direction = ParameterDirection.Output;

        var results = new List<OrderSummary>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            results.Add(new OrderSummary(
                reader.GetInt32(0),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetDecimal(5),
                reader.GetDecimal(6),
                reader.GetDecimal(7),
                reader.GetDateTime(8),
                reader.GetDateTime(9)
            ));
        }

        await reader.CloseAsync();
        int totalCount = totalParam.Value is int tc ? tc : 0;

        return PagedResult<OrderSummary>.Create(results, totalCount, pageNumber, pageSize);
    }

    public async Task<PlaceOrderResponse> PlaceOrderAsync(PlaceOrderRequest request, CancellationToken ct = default)
    {
        var linesJson = JsonSerializer.Serialize(
            request.Lines.Select(l => new { VariantID = l.VariantID, Quantity = l.Quantity })
        );

        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_PlaceOrder", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 30
        };

        cmd.Parameters.AddWithValue("@CustomerID",        request.CustomerID);
        cmd.Parameters.AddWithValue("@ShippingAddressID", request.ShippingAddressID);
        cmd.Parameters.AddWithValue("@DiscountCode",      (object?)request.DiscountCode ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@OrderLinesJson",    linesJson);

        var orderIdParam = cmd.Parameters.Add("@OrderID",     SqlDbType.Int);
        var totalParam   = cmd.Parameters.Add("@TotalAmount", SqlDbType.Decimal);
        orderIdParam.Direction = ParameterDirection.Output;
        totalParam.Direction   = ParameterDirection.Output;
        totalParam.Precision   = 10;
        totalParam.Scale       = 2;

        await cmd.ExecuteNonQueryAsync(ct);

        int     orderId     = (int)orderIdParam.Value;
        decimal totalAmount = (decimal)totalParam.Value;

        _log.LogInformation("Order {OrderID} placed for CustomerID {CustomerID} — total R{Total}",
            orderId, request.CustomerID, totalAmount);

        return new PlaceOrderResponse(orderId, totalAmount, $"Order {orderId} placed successfully.");
    }

    public async Task UpdateStatusAsync(int orderId, UpdateOrderStatusRequest request, CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_UpdateOrderStatus", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 15
        };

        cmd.Parameters.AddWithValue("@OrderID",        orderId);
        cmd.Parameters.AddWithValue("@NewStatus",      request.NewStatus);
        cmd.Parameters.AddWithValue("@CourierID",      (object?)request.CourierID      ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@TrackingNumber", (object?)request.TrackingNumber ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Notes",          (object?)request.Notes          ?? DBNull.Value);

        await cmd.ExecuteNonQueryAsync(ct);
        _log.LogInformation("Order {OrderID} status updated to {Status}", orderId, request.NewStatus);
    }
}
