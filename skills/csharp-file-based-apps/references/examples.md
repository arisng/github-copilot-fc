# C# File-Based Apps — Examples

## Data Processing (NuGet Packages)

Process JSON and export to CSV without a project file:

```csharp
#:package CsvHelper@33.1.0

using System.Text.Json;
using CsvHelper;
using System.Globalization;

var json = await File.ReadAllTextAsync("sales_data.json");
var sales = JsonSerializer.Deserialize<List<SaleRecord>>(json)!;

var topProducts = sales
    .GroupBy(s => s.Product)
    .Select(g => new {
        Product = g.Key,
        TotalRevenue = g.Sum(s => s.Amount),
        UnitsSold = g.Count()
    })
    .OrderByDescending(p => p.TotalRevenue)
    .Take(10);

using var writer = new StreamWriter("top_products.csv");
using var csv = new CsvWriter(writer, CultureInfo.InvariantCulture);
csv.WriteRecords(topProducts);

Console.WriteLine("Report generated: top_products.csv");

record SaleRecord(string Product, decimal Amount, DateTime Date);
```

> Note: `JsonSerializer.Deserialize` uses reflection. Add `#:property PublishAot=false` if publishing,
> or migrate to a `JsonSerializerContext` to keep AOT enabled.

---

## ASP.NET Core Minimal API

```csharp
#:sdk Microsoft.NET.Sdk.Web
#:property PublishAot=false

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Hello from a file-based web app!");
app.MapGet("/time", () => DateTime.UtcNow.ToString("o"));

app.Run();
```

Run with: `dotnet run api.cs --launch-profile http`

Use a companion `api.run.json` for profiles:
```json
{
  "profiles": {
    "http": {
      "commandName": "Project",
      "applicationUrl": "http://localhost:5000",
      "environmentVariables": { "ASPNETCORE_ENVIRONMENT": "Development" }
    }
  }
}
```

---

## Aspire AppHost (Distributed Application Orchestration)

```csharp
#:sdk Aspire.AppHost.Sdk@13.0.0
#:package Aspire.Hosting.AppHost@13.0.0

var builder = DistributedApplication.CreateBuilder(args);

var cache = builder.AddRedis("cache").WithDataVolume();

var postgres = builder.AddPostgres("postgres")
    .WithDataVolume()
    .AddDatabase("tododb");

var api = builder.AddProject<Projects.TodoApi>("api")
    .WithReference(cache)
    .WithReference(postgres);

builder.AddNpmApp("frontend", "../TodoApp")
    .WithReference(api)
    .WithHttpEndpoint(env: "PORT")
    .WithExternalHttpEndpoints();

builder.Build().Run();
```

---

## Spectre.Console CLI Tool

```csharp
#:package Spectre.Console@*

using Spectre.Console;

AnsiConsole.MarkupLine("[bold green]File-Based CLI Tool[/]");

var name = AnsiConsole.Ask<string>("What's your [blue]name[/]?");
AnsiConsole.MarkupLine($"Hello, [yellow]{name}[/]!");

var table = new Table();
table.AddColumn("Feature");
table.AddColumn("Status");
table.AddRow("No .csproj needed", "[green]✓[/]");
table.AddRow("NuGet packages", "[green]✓[/]");
table.AddRow("Native AOT", "[green]✓ (default)[/]");
table.AddRow("Multi-file", "[green]✓ (.NET 11+)[/]");

AnsiConsole.Write(table);
```

---

## Piping Code from stdin

**PowerShell:**
```powershell
'Console.WriteLine("Hello from stdin!");' | dotnet run -
```

**Bash:**
```bash
echo 'Console.WriteLine("Hello from stdin!");' | dotnet run -
```

Useful for shell scripts that generate C# code dynamically.

---

## Source-Generated JSON (AOT-Safe)

When native AOT is enabled (the default), use `JsonSerializerContext`:

```csharp
using System.Text.Json;
using System.Text.Json.Serialization;

var items = new[] {
    new Product("Widget", 9.99m),
    new Product("Gadget", 24.99m)
};

foreach (var item in items)
{
    var json = JsonSerializer.Serialize(item, ShopCtx.Default.Product);
    var back = JsonSerializer.Deserialize(json, ShopCtx.Default.Product)!;
    Console.WriteLine($"{back.Name}: ${back.Price}");
}

record Product(string Name, decimal Price);

[JsonSerializable(typeof(Product))]
[JsonSerializable(typeof(Product[]))]
partial class ShopCtx : JsonSerializerContext;
```

---

## Folder Layout for Multiple Scripts

```
📁 scripts/
├── Directory.Build.props    ← Isolate from parent repo settings
├── data-export.cs
├── data-export.run.json
├── db-seed.cs
└── health-check.cs
```

---

## Multi-File: HTTP Health-Check Tool (.NET 11+)

Split logic and entry point across two files.

```csharp
// healthchecker.cs — types only, no top-level statements
using System.Diagnostics;

public sealed class HealthChecker(HttpClient httpClient)
{
    public async Task<HealthCheckResult> CheckAsync(string url)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var response = await httpClient.GetAsync(url);
            sw.Stop();
            return new HealthCheckResult(url, (int)response.StatusCode,
                response.IsSuccessStatusCode, sw.ElapsedMilliseconds);
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new HealthCheckResult(url, 0, false, sw.ElapsedMilliseconds, ex.Message);
        }
    }
}

public record HealthCheckResult(
    string Url, int StatusCode, bool IsHealthy,
    long ResponseTimeMs, string? Error = null);
```

```csharp
// main.cs — entry point
#:include healthchecker.cs

var urls = new[] { "https://github.com", "https://example.com" };

using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
var checker = new HealthChecker(http);

Console.WriteLine($"Monitoring {urls.Length} URLs every 5 seconds. Press Ctrl+C to stop.\n");

while (true)
{
    foreach (var url in urls)
    {
        var r = await checker.CheckAsync(url);
        var status = r.IsHealthy ? "OK  " : "FAIL";
        var err = r.Error is null ? "" : $" - {r.Error}";
        Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {status} {r.StatusCode} {r.Url} ({r.ResponseTimeMs}ms){err}");
    }
    Console.WriteLine();
    await Task.Delay(TimeSpan.FromSeconds(5));
}
```

Run: `dotnet run main.cs`

---

## Multi-File: Minimal API with EF Core + SQLite (.NET 11+)

A working web API in three files — no project setup.

```csharp
// Order.cs
public class Order
{
    public int Id { get; set; }
    public string OrderNumber { get; set; } = string.Empty;
    public string CustomerName { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
```

```csharp
// OrdersDbContext.cs
using Microsoft.EntityFrameworkCore;

public class OrdersDbContext(DbContextOptions<OrdersDbContext> options) : DbContext(options)
{
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Order>(e =>
        {
            e.ToTable("Orders");
            e.HasKey(o => o.Id);
            e.Property(o => o.OrderNumber).HasMaxLength(50).IsRequired();
            e.Property(o => o.CustomerName).HasMaxLength(200).IsRequired();
            e.Property(o => o.Amount).HasColumnType("decimal(18,2)");
            e.HasIndex(o => o.OrderNumber).IsUnique();
        });
    }
}
```

```csharp
// main.cs — entry point
#:sdk Microsoft.NET.Sdk.Web
#:package Microsoft.EntityFrameworkCore.Sqlite@10.0.0
#:include Order.cs
#:include OrdersDbContext.cs

using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder();
builder.Services.AddDbContext<OrdersDbContext>(o => o.UseSqlite("Data Source=orders.db"));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
    await scope.ServiceProvider.GetRequiredService<OrdersDbContext>().Database.MigrateAsync();

app.MapGet("/orders", async (OrdersDbContext db) =>
    await db.Orders.AsNoTracking().ToListAsync());

app.MapGet("/orders/{id:int}", async (int id, OrdersDbContext db) =>
    await db.Orders.FindAsync(id) is { } o ? Results.Ok(o) : Results.NotFound());

app.MapPost("/orders", async (Order order, OrdersDbContext db) =>
{
    db.Orders.Add(order);
    await db.SaveChangesAsync();
    return Results.Created($"/orders/{order.Id}", order);
});

app.MapDelete("/orders/{id:int}", async (int id, OrdersDbContext db) =>
{
    var order = await db.Orders.FindAsync(id);
    if (order is null) return Results.NotFound();
    db.Orders.Remove(order);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

app.Run();
```

Run: `dotnet run main.cs`

First run restores EF Core and the SQLite provider; subsequent runs are fast.

The local `Directory.Build.props` can be empty (`<Project />`) to prevent parent directory settings from leaking in.
