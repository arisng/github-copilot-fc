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
table.AddRow("Multi-file", "[red]✗ (.NET 11+)[/]");

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

The local `Directory.Build.props` can be empty (`<Project />`) to prevent parent directory settings from leaking in.
