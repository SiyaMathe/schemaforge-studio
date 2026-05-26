using System.Data;
using KhulisaQuery.Api.Models;
using Microsoft.Data.SqlClient;

namespace KhulisaQuery.Api.Services;

public interface IAnalyticsService
{
    Task<IEnumerable<MonthlyTrend>>   GetMonthlyTrendAsync(int months = 12, CancellationToken ct = default);
    Task<IEnumerable<ProductRanking>> GetProductRankingsAsync(string? categoryName = null, CancellationToken ct = default);
    Task RefreshSalesSummaryAsync(DateOnly? date = null, CancellationToken ct = default);
}

public class AnalyticsService : IAnalyticsService
{
    private readonly IDbConnectionFactory   _db;
    private readonly ILogger<AnalyticsService> _log;

    public AnalyticsService(IDbConnectionFactory db, ILogger<AnalyticsService> log)
        => (_db, _log) = (db, log);

    public async Task<IEnumerable<MonthlyTrend>> GetMonthlyTrendAsync(int months = 12, CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);

        // Query the analytics view directly — pre-computed with window functions
        const string sql = @"
            SELECT TOP (@Months)
                RevenueYear, RevenueMonth, OrderCount,
                GrossRevenue, NetRevenue, UniqueCustomers,
                AvgOrderValue, MoM_GrowthPct, YoY_GrowthPct,
                YTD_Revenue, Rolling3MonthAvg, AllTimeRevenueRank
            FROM dbo.vw_RevenueMonthlyTrend
            ORDER BY RevenueYear DESC, RevenueMonth DESC";

        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 15 };
        cmd.Parameters.AddWithValue("@Months", months);

        var results = new List<MonthlyTrend>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            results.Add(new MonthlyTrend(
                reader.GetInt32(0),
                reader.GetInt32(1),
                reader.GetInt32(2),
                reader.GetDecimal(3),
                reader.GetDecimal(4),
                reader.GetInt32(5),
                reader.GetDecimal(6),
                reader.IsDBNull(7)  ? null : reader.GetDecimal(7),
                reader.IsDBNull(8)  ? null : reader.GetDecimal(8),
                reader.GetDecimal(9),
                reader.GetDecimal(10),
                reader.GetInt32(11)
            ));
        }

        return results;
    }

    public async Task<IEnumerable<ProductRanking>> GetProductRankingsAsync(
        string? categoryName = null, CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);

        const string sql = @"
            SELECT
                ProductID, ProductName, CategoryName, VendorName,
                OrderCount, UnitsSold, TotalRevenue, AvgSellingPrice,
                AvgRating, RowNum_ByRevenue, Rank_ByRevenue,
                DenseRank_ByRevenue, RevenueQuartile, ProductTier,
                RankWithinCategory, RevenueSharePct, CumulativeRevenueSharePct
            FROM dbo.vw_ProductSalesRanking
            WHERE @CategoryName IS NULL OR CategoryName = @CategoryName
            ORDER BY RowNum_ByRevenue";

        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 15 };
        cmd.Parameters.AddWithValue("@CategoryName", (object?)categoryName ?? DBNull.Value);

        var results = new List<ProductRanking>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            results.Add(new ProductRanking(
                reader.GetInt32(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetInt32(4),
                reader.GetInt32(5),
                reader.GetDecimal(6),
                reader.GetDecimal(7),
                reader.IsDBNull(8) ? null : (double?)reader.GetDouble(8),
                reader.GetInt32(9),
                reader.GetInt32(10),
                reader.GetInt32(11),
                reader.GetInt32(12),
                reader.GetString(13),
                reader.GetInt32(14),
                reader.GetDecimal(15),
                reader.GetDecimal(16)
            ));
        }

        return results;
    }

    public async Task RefreshSalesSummaryAsync(DateOnly? date = null, CancellationToken ct = default)
    {
        await using var conn = await _db.OpenAsync(ct);
        await using var cmd  = new SqlCommand("dbo.usp_RefreshSalesSummary", conn)
        {
            CommandType    = CommandType.StoredProcedure,
            CommandTimeout = 120
        };

        cmd.Parameters.AddWithValue("@SummaryDate",
            date.HasValue ? (object)date.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value);

        await cmd.ExecuteNonQueryAsync(ct);
        _log.LogInformation("SalesSummary refreshed for {Date}", date?.ToString() ?? "yesterday");
    }
}
