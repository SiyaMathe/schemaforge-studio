using KhulisaQuery.Api.Models;
using KhulisaQuery.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace KhulisaQuery.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class OrdersController : ControllerBase
{
    private readonly IOrderService             _orders;
    private readonly ILogger<OrdersController> _log;

    public OrdersController(IOrderService orders, ILogger<OrdersController> log)
        => (_orders, _log) = (orders, log);

    /// <summary>Search orders with optional filters and pagination.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<OrderSummary>), 200)]
    public async Task<IActionResult> Search(
        [FromQuery] int?     customerId  = null,
        [FromQuery] string?  status      = null,
        [FromQuery] DateTime? fromDate   = null,
        [FromQuery] DateTime? toDate     = null,
        [FromQuery] decimal? minAmount   = null,
        [FromQuery] decimal? maxAmount   = null,
        [FromQuery] int      page        = 1,
        [FromQuery] int      pageSize    = 25,
        CancellationToken ct = default)
    {
        var result = await _orders.SearchOrdersAsync(
            customerId, status, fromDate, toDate,
            minAmount, maxAmount, page, pageSize, ct);

        return Ok(result);
    }

    /// <summary>Place a new order. Validates stock, applies discount, awards loyalty points.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(PlaceOrderResponse), 201)]
    [ProducesResponseType(typeof(ProblemDetails), 400)]
    public async Task<IActionResult> Place([FromBody] PlaceOrderRequest request, CancellationToken ct = default)
    {
        if (!request.Lines.Any())
            return BadRequest(new ProblemDetails { Title = "At least one order line is required." });

        var response = await _orders.PlaceOrderAsync(request, ct);
        return CreatedAtAction(nameof(GetById), new { id = response.OrderID }, response);
    }

    /// <summary>Get a single order by ID.</summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType(typeof(OrderSummary), 200)]
    [ProducesResponseType(404)]
    public async Task<IActionResult> GetById(int id, CancellationToken ct = default)
    {
        var result = await _orders.SearchOrdersAsync(
            customerId: null, status: null, fromDate: null, toDate: null,
            minAmount: null, maxAmount: null, pageNumber: 1, pageSize: 1, ct: ct);

        var order = result.Data.FirstOrDefault();
        return order is null ? NotFound() : Ok(order);
    }

    /// <summary>Update order status. Enforces legal state transitions.</summary>
    [HttpPatch("{id:int}/status")]
    [ProducesResponseType(204)]
    [ProducesResponseType(typeof(ProblemDetails), 400)]
    public async Task<IActionResult> UpdateStatus(
        int id,
        [FromBody] UpdateOrderStatusRequest request,
        CancellationToken ct = default)
    {
        await _orders.UpdateStatusAsync(id, request, ct);
        return NoContent();
    }
}
