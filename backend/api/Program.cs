using KhulisaQuery.Api.Services;
using Microsoft.Data.SqlClient;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// ── Logging ──────────────────────────────────────────────────────────────────
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateLogger();

builder.Host.UseSerilog();

// ── Services ─────────────────────────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new()
    {
        Title       = "KhulisaQuery API",
        Version     = "v1",
        Description = "REST query interface for the Khulisa Commerce database — " +
                      "demonstrates stored procedure calls, dynamic views, and analytics endpoints."
    });
});

// Register SQL connection factory as scoped (one connection per request)
builder.Services.AddScoped<IDbConnectionFactory>(_ =>
    new SqlConnectionFactory(
        builder.Configuration.GetConnectionString("KhulisaCommerce")
            ?? throw new InvalidOperationException("KhulisaCommerce connection string is required.")
    )
);

builder.Services.AddScoped<IOrderService,     OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();
builder.Services.AddScoped<IAnalyticsService, AnalyticsService>();

// Application Insights
builder.Services.AddApplicationInsightsTelemetry();

// CORS — allow local dashboard dev
builder.Services.AddCors(opt => opt.AddDefaultPolicy(policy =>
    policy.WithOrigins("http://localhost:5173", "https://localhost:5173")
          .AllowAnyMethod()
          .AllowAnyHeader()
));

var app = builder.Build();

// ── Middleware pipeline ───────────────────────────────────────────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "KhulisaQuery v1"));
}

app.UseSerilogRequestLogging();
app.UseHttpsRedirection();
app.UseCors();
app.UseAuthorization();
app.MapControllers();

// Health endpoint (used by CI/CD smoke test)
app.MapGet("/health", () => Results.Ok(new
{
    status    = "healthy",
    timestamp = DateTimeOffset.UtcNow,
    version   = "1.0.0"
}));

app.Run();
