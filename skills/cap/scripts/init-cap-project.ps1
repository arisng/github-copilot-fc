# CAP Project Initialization Script
# This script sets up a basic CAP configuration for a .NET project

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath,

    [Parameter(Mandatory=$true)]
    [ValidateSet("RabbitMQ", "Kafka", "AzureServiceBus", "AmazonSQS", "NATS", "RedisStreams", "Pulsar")]
    [string]$Transport,

    [Parameter(Mandatory=$true)]
    [ValidateSet("SqlServer", "PostgreSql", "MySql", "MongoDB")]
    [string]$Database,

    [string]$ConnectionString = "",
    [switch]$IncludeDashboard,
    [switch]$IncludeHealthChecks
)

function Add-CapPackages {
    param([string]$Transport, [string]$Database, [bool]$IncludeDashboard, [bool]$IncludeHealthChecks)

    $packages = @("DotNetCore.CAP")

    # Add transport package
    switch ($Transport) {
        "RabbitMQ" { $packages += "DotNetCore.CAP.RabbitMQ" }
        "Kafka" { $packages += "DotNetCore.CAP.Kafka" }
        "AzureServiceBus" { $packages += "DotNetCore.CAP.AzureServiceBus" }
        "AmazonSQS" { $packages += "DotNetCore.CAP.AmazonSQS" }
        "NATS" { $packages += "DotNetCore.CAP.NATS" }
        "RedisStreams" { $packages += "DotNetCore.CAP.RedisStreams" }
        "Pulsar" { $packages += "DotNetCore.CAP.Pulsar" }
    }

    # Add database package
    switch ($Database) {
        "SqlServer" { $packages += "DotNetCore.CAP.SqlServer" }
        "PostgreSql" { $packages += "DotNetCore.CAP.PostgreSql" }
        "MySql" { $packages += "DotNetCore.CAP.MySql" }
        "MongoDB" { $packages += "DotNetCore.CAP.MongoDB" }
    }

    if ($IncludeDashboard) {
        $packages += "DotNetCore.CAP.Dashboard"
    }

    if ($IncludeHealthChecks) {
        $packages += "DotNetCore.CAP.HealthCheck"
    }

    foreach ($package in $packages) {
        Write-Host "Adding package: $package"
        dotnet add package $package
    }
}

function Generate-CapConfiguration {
    param([string]$Transport, [string]$Database, [string]$ConnectionString, [bool]$IncludeDashboard)

    $config = @"
// Add CAP services
builder.Services.AddCap(x =>
{
    // Configure storage
"@

    # Add database configuration
    switch ($Database) {
        "SqlServer" {
            if ($ConnectionString) {
                $config += "`n    x.UseSqlServer(""$ConnectionString"");"
            } else {
                $config += "`n    x.UseSqlServer(builder.Configuration.GetConnectionString(""DefaultConnection""));"
            }
        }
        "PostgreSql" {
            if ($ConnectionString) {
                $config += "`n    x.UsePostgreSql(""$ConnectionString"");"
            } else {
                $config += "`n    x.UsePostgreSql(builder.Configuration.GetConnectionString(""DefaultConnection""));"
            }
        }
        "MySql" {
            if ($ConnectionString) {
                $config += "`n    x.UseMySql(""$ConnectionString"");"
            } else {
                $config += "`n    x.UseMySql(builder.Configuration.GetConnectionString(""DefaultConnection""));"
            }
        }
        "MongoDB" {
            if ($ConnectionString) {
                $config += "`n    x.UseMongoDB(""$ConnectionString"");"
            } else {
                $config += "`n    x.UseMongoDB(builder.Configuration.GetConnectionString(""MongoDB""));"
            }
        }
    }

    $config += "`n"
    $config += "`n    // Configure transport`n"

    # Add transport configuration
    switch ($Transport) {
        "RabbitMQ" {
            $config += "    x.UseRabbitMQ(""localhost"");`n"
        }
        "Kafka" {
            $config += "    x.UseKafka(""localhost:9092"");`n"
        }
        "AzureServiceBus" {
            $config += "    x.UseAzureServiceBus(builder.Configuration.GetConnectionString(""AzureServiceBus""));`n"
        }
        "AmazonSQS" {
            $config += "    x.UseAmazonSQS(options => {`n"
            $config += "        // Configure AWS credentials and region`n"
            $config += "    });`n"
        }
        "NATS" {
            $config += "    x.UseNATS(""localhost"");`n"
        }
        "RedisStreams" {
            $config += "    x.UseRedisStreams(builder.Configuration.GetConnectionString(""Redis""));`n"
        }
        "Pulsar" {
            $config += "    x.UsePulsar(""pulsar://localhost:6650"");`n"
        }
    }

    if ($IncludeDashboard) {
        $config += "`n    // Configure dashboard`n"
        $config += "    x.UseDashboard();`n"
    }

    $config += "});`n"

    if ($IncludeHealthChecks) {
        $config += "`n// Add CAP health checks`n"
        $config += "builder.Services.AddHealthChecks().AddCapCheck();`n"
    }

    return $config
}

function Generate-SamplePublisher {
    $publisher = @'
using DotNetCore.CAP;

public class OrderService
{
    private readonly ICapPublisher _capPublisher;

    public OrderService(ICapPublisher capPublisher)
    {
        _capPublisher = capPublisher;
    }

    public async Task CreateOrder(Order order)
    {
        // Publish order created event
        await _capPublisher.PublishAsync("order.created", order);
    }

    public async Task ProcessPayment(Payment payment)
    {
        // Publish payment processed event with headers
        await _capPublisher.PublishAsync(
            "payment.processed",
            payment,
            headers: new Dictionary<string, string>
            {
                ["correlation-id"] = Guid.NewGuid().ToString(),
                ["source"] = "payment-service"
            }
        );
    }
}
'@

    return $publisher
}

function Generate-SampleSubscriber {
    $subscriber = @'
using DotNetCore.CAP;

public class OrderEventHandler : ICapSubscribe
{
    private readonly ILogger<OrderEventHandler> _logger;

    public OrderEventHandler(ILogger<OrderEventHandler> logger)
    {
        _logger = logger;
    }

    [CapSubscribe("order.created")]
    public async Task HandleOrderCreated(OrderCreatedEvent orderEvent)
    {
        _logger.LogInformation("Processing order created event for OrderId: {OrderId}",
            orderEvent.OrderId);

        // Process the order created event
        await ProcessOrderAsync(orderEvent);
    }

    [CapSubscribe("payment.processed", Group = "order-processing")]
    public async Task HandlePaymentProcessed(PaymentProcessedEvent paymentEvent)
    {
        _logger.LogInformation("Processing payment for OrderId: {OrderId}",
            paymentEvent.OrderId);

        // Update order status
        await UpdateOrderStatusAsync(paymentEvent.OrderId, "Paid");
    }

    private async Task ProcessOrderAsync(OrderCreatedEvent orderEvent)
    {
        // Implementation here
        await Task.CompletedTask;
    }

    private async Task UpdateOrderStatusAsync(int orderId, string status)
    {
        // Implementation here
        await Task.CompletedTask;
    }
}

// Event classes
public class OrderCreatedEvent
{
    public int OrderId { get; set; }
    public string CustomerId { get; set; }
    public decimal TotalAmount { get; set; }
    public List<OrderItem> Items { get; set; }
}

public class PaymentProcessedEvent
{
    public int OrderId { get; set; }
    public string PaymentId { get; set; }
    public decimal Amount { get; set; }
    public DateTime ProcessedAt { get; set; }
}
'@

    return $subscriber
}

# Main execution
try {
    Write-Host "Initializing CAP project at: $ProjectPath"
    Write-Host "Transport: $Transport"
    Write-Host "Database: $Database"
    Write-Host "Include Dashboard: $IncludeDashboard"
    Write-Host "Include Health Checks: $IncludeHealthChecks"

    # Navigate to project directory
    Push-Location $ProjectPath

    # Add NuGet packages
    Write-Host "`nAdding CAP packages..."
    Add-CapPackages -Transport $Transport -Database $Database -IncludeDashboard $IncludeDashboard -IncludeHealthChecks $IncludeHealthChecks

    # Generate configuration
    Write-Host "`nGenerating CAP configuration..."
    $capConfig = Generate-CapConfiguration -Transport $Transport -Database $Database -ConnectionString $ConnectionString -IncludeDashboard $IncludeDashboard

    # Output configuration to console
    Write-Host "`nAdd the following to your Program.cs or Startup.cs:"
    Write-Host "----------------------------------------"
    Write-Host $capConfig
    Write-Host "----------------------------------------"

    # Generate sample classes
    Write-Host "`nGenerating sample publisher and subscriber classes..."
    $publisherCode = Generate-SamplePublisher
    $subscriberCode = Generate-SampleSubscriber

    # Output sample code
    Write-Host "`nSample Publisher (OrderService.cs):"
    Write-Host "----------------------------------------"
    Write-Host $publisherCode
    Write-Host "----------------------------------------"

    Write-Host "`nSample Subscriber (OrderEventHandler.cs):"
    Write-Host "----------------------------------------"
    Write-Host $subscriberCode
    Write-Host "----------------------------------------"

    Write-Host "`nCAP initialization completed successfully!"
    Write-Host "`nNext steps:"
    Write-Host "1. Add the generated configuration to your Program.cs"
    Write-Host "2. Create the sample classes or adapt them to your needs"
    Write-Host "3. Register subscribers in DI container if using ICapSubscribe"
    Write-Host "4. Test the setup by publishing and subscribing to messages"

} catch {
    Write-Error "Error initializing CAP project: $_"
} finally {
    Pop-Location
}