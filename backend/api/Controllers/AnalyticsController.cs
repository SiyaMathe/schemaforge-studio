using KhulisaQuery.Api.Models;
using KhulisaQuery.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace KhulisaQuery.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class AnalyticsController : ControllerBase
{
    private readonly IAnalyticsService             _analytics;
    private readonly ILogger<AnalyticsController>  _log;

    public AnalyticsController(IAnalyticsService analytics, ILogger<AnalyticsController> log)
        => (_analytics, _log) = (analytics, log);

    /// <summary>Monthly revenue trend with MoM/YoY growth, rolling averages, and rank.</summary>
    [HttpGet("revenue/monthly")]
    [ProducesResponseType(typeof(IEnumerable<MonthlyTrend>), 200)]
    public async Task<IActionResult> MonthlyRevenue(
        [FromQuery] int months = 12,
        CancellationToken ct = default)
    {
        if (months is < 1 or > 60)
            return BadRequest("months must be between 1 and 60.");

        var data = await _analytics.GetMonthlyTrendAsync(months, ct);
        return Ok(data);
    }

    /// <summary>Product sales ranking — ROW_NUMBER, RANK, DENSE_RANK, NTILE, Pareto share.</summary>
    [HttpGet("products/ranking")]
    [ProducesResponseType(typeof(IEnumerable<ProductRanking>), 200)]
    public async Task<IActionResult> ProductRankings(
        [FromQuery] string? category = null,
        CancellationToken ct = default)
    {
        var data = await _analytics.GetProductRankingsAsync(category, ct);
        return Ok(data);
    }

    /// <summary>Trigger Gold-layer SalesSummary refresh for a given date (defaults to yesterday).</summary>
    [HttpPost("sales-summary/refresh")]
    [ProducesResponseType(204)]
    public async Task<IActionResult> RefreshSalesSummary(
        [FromQuery] DateOnly? date = null,
        CancellationToken ct = default)
    {
        await _analytics.RefreshSalesSummaryAsync(date, ct);
        return NoContent();
    }
}
