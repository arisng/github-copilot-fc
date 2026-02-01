# CAP Configuration Reference

## Core Configuration

### Storage Providers

#### SQL Server
```csharp
services.AddCap(x =>
{
    x.UseSqlServer(connectionString);
});
```

#### PostgreSQL
```csharp
services.AddCap(x =>
{
    x.UsePostgreSql(connectionString);
});
```

#### MySQL
```csharp
services.AddCap(x =>
{
    x.UseMySql(connectionString);
});
```

#### MongoDB
```csharp
services.AddCap(x =>
{
    x.UseMongoDB(connectionString);
});
```

### Message Queue Transports

#### RabbitMQ
```csharp
services.AddCap(x =>
{
    x.UseRabbitMQ(options =>
    {
        options.HostName = "localhost";
        options.Port = 5672;
        options.UserName = "guest";
        options.Password = "guest";
        options.VirtualHost = "/";
    });
});
```

#### Kafka
```csharp
services.AddCap(x =>
{
    x.UseKafka(options =>
    {
        options.Servers = "localhost:9092";
        options.MainConfig.Add("group.id", "cap-group");
    });
});
```

#### Azure Service Bus
```csharp
services.AddCap(x =>
{
    x.UseAzureServiceBus(options =>
    {
        options.ConnectionString = "your-connection-string";
    });
});
```

## Advanced Configuration Options

### Consumer Configuration

```csharp
services.AddCap(x =>
{
    // Consumer thread count (default: 1)
    x.ConsumerThreadCount = 10;

    // Failed retry count (default: 50)
    x.FailedRetryCount = 5;

    // Failed message waiting interval (default: 60 seconds)
    x.FailedRetryInterval = 60;

    // Success message expiration time (default: 24*3600 seconds)
    x.SucceedMessageExpiredAfter = 24 * 3600;
});
```

### Publisher Configuration

```csharp
services.AddCap(x =>
{
    // Default group name
    x.DefaultGroup = "my-service-group";

    // Group name prefix
    x.GroupNamePrefix = "cap";

    // Message version
    x.Version = "1.0";
});
```

### Dashboard Configuration

```csharp
services.AddCap(x =>
{
    x.UseDashboard(options =>
    {
        options.PathMatch = "/cap-dashboard";
        options.UseAuth = true;
        options.AuthorizationPolicy = "CapPolicy";
    });
});
```

### Serialization

```csharp
services.AddCap(x =>
{
    // Custom serializer
    x.UseCustomSerializer(new JsonSerializer());
});
```

### Filters

```csharp
services.AddCap(x =>
{
    // Add custom filters
    x.UseFilter<MyPublishFilter>();
    x.UseFilter<MySubscribeFilter>();
});
```

## Environment-Specific Configuration

### Development
```csharp
services.AddCap(x =>
{
    x.UseInMemoryStorage();
    x.UseInMemoryMessageQueue();
    x.UseDashboard();
});
```

### Production
```csharp
services.AddCap(x =>
{
    x.UseSqlServer(Configuration.GetConnectionString("CapDb"));
    x.UseRabbitMQ(Configuration.GetSection("RabbitMQ"));
    x.ConsumerThreadCount = Environment.ProcessorCount;
    x.UseDashboard(options =>
    {
        options.UseAuth = true;
    });
});
```