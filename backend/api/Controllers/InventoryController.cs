using KhulisaQuery.Api.Models;
using KhulisaQuery.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace KhulisaQuery.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class InventoryController : ControllerBase
{
    private readonly IInventoryService             _inventory;
    private readonly ILogger<InventoryController>  _log;

    public InventoryController(IInventoryService inventory, ILogger<InventoryController> log)
        => (_inventory, _log) = (inventory, log);

    /// <summary>Low stock report — items at or below reorder point, classified by severity.</summary>
    [HttpGet("low-stock")]
    [ProducesResponseType(typeof(IEnumerable<LowStockItem>), 200)]
    public async Task<IActionResult> LowStock(
        [FromQuery] int? warehouseId = null,
        CancellationToken ct = default)
    {
        var items = await _inventory.GetLowStockReportAsync(warehouseId, ct);
        return Ok(items);
    }

    /// <summary>Restock a warehouse. Accepts a JSON array of variant/quantity pairs.</summary>
    [HttpPost("restock")]
    [ProducesResponseType(typeof(object), 200)]
    [ProducesResponseType(typeof(ProblemDetails), 400)]
    public async Task<IActionResult> Restock(
        [FromBody] RestockRequest request,
        CancellationToken ct = default)
    {
        if (!request.Lines.Any())
            return BadRequest(new ProblemDetails { Title = "At least one restock line is required." });

        var rowsUpdated = await _inventory.RestockWarehouseAsync(request, ct);
        return Ok(new { rowsUpdated, message = $"{rowsUpdated} variant(s) restocked in warehouse {request.WarehouseID}." });
    }

    /// <summary>Transfer stock between warehouses. Validates availability before deducting.</summary>
    [HttpPost("transfer")]
    [ProducesResponseType(204)]
    [ProducesResponseType(typeof(ProblemDetails), 400)]
    public async Task<IActionResult> Transfer(
        [FromBody] TransferRequest request,
        CancellationToken ct = default)
    {
        if (request.Quantity <= 0)
            return BadRequest(new ProblemDetails { Title = "Quantity must be greater than zero." });

        if (request.FromWarehouseID == request.ToWarehouseID)
            return BadRequest(new ProblemDetails { Title = "Source and destination warehouse must differ." });

        await _inventory.TransferStockAsync(request, ct);
        return NoContent();
    }
}
