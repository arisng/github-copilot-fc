# CAP Troubleshooting Guide

## Common Issues and Solutions

### Messages Not Being Processed

**Symptoms:**
- Messages are published but subscribers don't receive them
- Dashboard shows messages in "Published" state but not "Consumed"

**Possible Causes & Solutions:**

1. **Subscriber not registered**
   ```csharp
   // Ensure subscriber is registered in DI
   services.AddTransient<IMySubscriber, MySubscriber>();
   ```

2. **Incorrect topic names**
   - Check for typos in topic names
   - Ensure publisher and subscriber use exact same topic

3. **Group configuration issues**
   - Same group: competing consumers (only one processes)
   - Different groups: fan-out (all receive)
   - Check `DefaultGroup` configuration

4. **Consumer thread count**
   ```csharp
   services.AddCap(x =>
   {
       x.ConsumerThreadCount = 5; // Increase if needed
   });
   ```

### Duplicate Message Processing

**Symptoms:**
- Same message processed multiple times
- Database shows duplicate records

**Solutions:**

1. **Implement idempotency**
   ```csharp
   [CapSubscribe("order.created")]
   public async Task HandleOrderCreated(OrderCreatedEvent data)
   {
       if (await repository.ExistsAsync(data.OrderId))
           return; // Skip duplicate

       await ProcessOrderAsync(data);
   }
   ```

2. **Use message deduplication**
   ```csharp
   private readonly ConcurrentDictionary<string, bool> _processedMessages = new();

   [CapSubscribe("order.created")]
   public async Task HandleOrderCreated(OrderCreatedEvent data)
   {
       var messageId = GetCapMessageId();
       if (!_processedMessages.TryAdd(messageId, true))
           return; // Already processed

       await ProcessOrderAsync(data);
   }
   ```

### Connection Issues

**Message Queue Connection Problems:**

1. **RabbitMQ connection failed**
   ```csharp
   services.AddCap(x =>
   {
       x.UseRabbitMQ(options =>
       {
           options.HostName = "rabbitmq-host";
           options.Port = 5672;
           options.UserName = "user";
           options.Password = "password";
           options.VirtualHost = "/";
           options.ConnectionFactoryOptions = factory =>
           {
               factory.AutomaticRecoveryEnabled = true;
               factory.NetworkRecoveryInterval = TimeSpan.FromSeconds(10);
           };
       });
   });
   ```

2. **Kafka connection issues**
   ```csharp
   services.AddCap(x =>
   {
       x.UseKafka(options =>
       {
           options.Servers = "kafka-broker1:9092,kafka-broker2:9092";
           options.MainConfig.Add("group.id", "cap-group");
           options.MainConfig.Add("auto.offset.reset", "earliest");
       });
   });
   ```

**Database Connection Problems:**

1. **Connection string issues**
   - Verify connection string format
   - Check network connectivity
   - Validate credentials

2. **Database permissions**
   - Ensure CAP can create tables
   - Check schema permissions

### Performance Issues

**High Memory Usage:**

```csharp
services.AddCap(x =>
{
    // Reduce consumer threads
    x.ConsumerThreadCount = 2;

    // Reduce batch size
    x.ConsumerMaxBatchSize = 10;

    // Enable backpressure
    x.UseBackpressure = true;
});
```

**Slow Message Processing:**

1. **Database bottlenecks**
   - Check indexes on CAP tables
   - Monitor database performance

2. **Message queue throughput**
   - Increase consumer threads
   - Use consumer groups for load balancing

3. **Serialization overhead**
   ```csharp
   // Use faster serializer
   x.UseCustomSerializer(new MessagePackSerializer());
   ```

### Transaction Issues

**Messages not published in transactions:**

```csharp
// Correct - use CAP transaction
using (var transaction = dbContext.Database.BeginTransaction(_capPublisher, autoCommit: true))
{
    // Business logic
    await dbContext.SaveChangesAsync();

    // Publish within transaction
    await _capPublisher.PublishAsync("event", data);
}

// Incorrect - publish outside transaction
await dbContext.SaveChangesAsync();
await _capPublisher.PublishAsync("event", data); // May be lost if app crashes
```

### Dashboard Issues

**Dashboard not accessible:**

1. **Package not installed**
   ```bash
   dotnet add package DotNetCore.CAP.Dashboard
   ```

2. **Path configuration**
   ```csharp
   services.AddCap(x =>
   {
       x.UseDashboard(options =>
       {
           options.PathMatch = "/cap"; // Default path
       });
   });
   ```

3. **Authentication issues**
   ```csharp
   services.AddCap(x =>
   {
       x.UseDashboard(options =>
       {
           options.UseAuth = true;
           options.AuthorizationPolicy = "CapDashboardPolicy";
       });
   });
   ```

### Monitoring and Debugging

**Enable detailed logging:**

```csharp
services.AddCap(x =>
{
    x.EnableDetailedLogging = true;
});

// In appsettings.json
{
  "Logging": {
    "LogLevel": {
      "DotNetCore.CAP": "Debug"
    }
  }
}
```

**Check CAP tables:**

```sql
-- Check published messages
SELECT * FROM cap.published ORDER BY Added DESC;

-- Check received messages
SELECT * FROM cap.received ORDER BY Added DESC;

-- Check failed messages
SELECT * FROM cap.published WHERE StatusName = 'Failed';
```

**Health checks:**

```csharp
services.AddHealthChecks()
    .AddCapCheck(); // Requires DotNetCore.CAP.HealthCheck package
```

### Migration Issues

**Upgrading CAP versions:**

1. **v5.x to v6.x/v7.x**
   - Update package references
   - Check breaking changes in release notes
   - Update configuration syntax

2. **Database schema changes**
   ```bash
   # CAP will auto-create tables, but verify permissions
   ```

### Testing Issues

**Unit testing subscribers:**

```csharp
[Fact]
public async Task Should_Process_Order_Created_Event()
{
    // Arrange
    var handler = new OrderEventHandler(mockService.Object);
    var @event = new OrderCreatedEvent { OrderId = 1 };

    // Act
    await handler.HandleOrderCreated(@event);

    // Assert
    mockService.Verify(x => x.ProcessOrderAsync(1), Times.Once);
}
```

**Integration testing:**

```csharp
public class CapIntegrationTests : IClassFixture<CustomWebApplicationFactory>
{
    [Fact]
    public async Task Should_Publish_And_Consume_Message()
    {
        // Use test containers for message queue and database
        // Publish message and verify consumption
    }
}
```