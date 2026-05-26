using System.Data;
using System.Text.Json;
using KhulisaQuery.Api.Models;
using Microsoft.Data.SqlClient;

namespace KhulisaQuery.Api.Services;

public interface IInventoryService
{
    Task<IEnumerable<LowStockItem>> GetLowStockReportAsync(int? warehouseId = null, CancellationToken ct = default);
    Task<int> RestockWarehouseAsync(RestockRequest request, CancellationToken ct = default);
    Task TransferStockAsync(TransferRequest request, CancellationToken ct = default);
}

public class InventoryService : IInventoryService
{
    private readonly IDbConnectionFactory      _db;
    private readonly ILogger<InventoryService> _log;

    public InventoryService(IDbConnectionFactory db, ILogger<InventoryService> log)
        => (_db, _log) = (db, log);

    public async Task<IEnumerable<LowStockItem>> GetLowStockReportAsync(
        int? warehouseId = null, CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_GetLowStockReport", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 15
        };

        cmd.Parameters.AddWithValue("@WarehouseID", (object?)warehouseId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@IncludeZero", 1);

        var items = new List<LowStockItem>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            items.Add(new LowStockItem(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetInt32(5),
                reader.GetInt32(6),
                reader.GetInt32(7),
                reader.GetString(8),
                reader.GetString(9),
                reader.GetString(10)
            ));
        }

        return items;
    }

    public async Task<int> RestockWarehouseAsync(RestockRequest request, CancellationToken ct = default)
    {
        var json = JsonSerializer.Serialize(
            request.Lines.Select(l => new { VariantID = l.VariantID, Quantity = l.Quantity })
        );

        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_RestockWarehouse", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 30
        };

        cmd.Parameters.AddWithValue("@WarehouseID",  request.WarehouseID);
        cmd.Parameters.AddWithValue("@RestockJson",  json);

        var rowsParam = cmd.Parameters.Add("@RowsUpdated", SqlDbType.Int);
        rowsParam.Direction = ParameterDirection.Output;

        await cmd.ExecuteNonQueryAsync(ct);
        return rowsParam.Value is int rows ? rows : 0;
    }

    public async Task TransferStockAsync(TransferRequest request, CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_TransferStock", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 15
        };

        cmd.Parameters.AddWithValue("@FromWarehouseID", request.FromWarehouseID);
        cmd.Parameters.AddWithValue("@ToWarehouseID",   request.ToWarehouseID);
        cmd.Parameters.AddWithValue("@VariantID",       request.VariantID);
        cmd.Parameters.AddWithValue("@Quantity",        request.Quantity);
        cmd.Parameters.AddWithValue("@Notes",           (object?)request.Notes ?? DBNull.Value);

        await cmd.ExecuteNonQueryAsync(ct);
        _log.LogInformation(
            "Stock transferred: VariantID {VariantID}, Qty {Qty}, Warehouse {From}→{To}",
            request.VariantID, request.Quantity, request.FromWarehouseID, request.ToWarehouseID);
    }
}
