# CAP API Reference

## Core Interfaces

### ICapPublisher

Main interface for publishing messages.

```csharp
public interface ICapPublisher
{
    // Synchronous publishing
    void Publish(string name, object contentObj, string callbackName = null);
    void Publish(string name, object contentObj, IDictionary<string, string> headers);

    // Asynchronous publishing
    Task PublishAsync(string name, object contentObj, string callbackName = null);
    Task PublishAsync(string name, object contentObj, IDictionary<string, string> headers);

    // Delayed publishing
    Task PublishDelayAsync(TimeSpan delay, string name, object contentObj);
    Task PublishDelayAsync(TimeSpan delay, string name, object contentObj, IDictionary<string, string> headers);
    Task PublishDelayAsync(DateTimeOffset publishTime, string name, object contentObj);
    Task PublishDelayAsync(DateTimeOffset publishTime, string name, object contentObj, IDictionary<string, string> headers);
}
```

### ICapSubscribe

Interface for subscribers that are not controllers.

```csharp
public interface ICapSubscribe
{
    // Marker interface - no methods required
    // Subscribers implement this to enable method scanning
}
```

## Attributes

### CapSubscribeAttribute

Marks methods as message subscribers.

```csharp
[AttributeUsage(AttributeTargets.Method, AllowMultiple = true)]
public class CapSubscribeAttribute : Attribute
{
    public CapSubscribeAttribute(string name);
    public CapSubscribeAttribute(string name, bool isPartial);

    public string Name { get; }
    public string Group { get; set; }
    public bool IsPartial { get; set; }
}
```

## Configuration Classes

### CapOptions

Main configuration class.

```csharp
public class CapOptions
{
    // Storage
    public string DefaultGroup { get; set; }
    public string GroupNamePrefix { get; set; }
    public string Version { get; set; }

    // Consumer
    public int ConsumerThreadCount { get; set; }
    public int ConsumerMaxBatchSize { get; set; }
    public TimeSpan ConsumerPollDelay { get; set; }

    // Retry
    public int FailedRetryCount { get; set; }
    public int FailedRetryInterval { get; set; }

    // Cleanup
    public int SucceedMessageExpiredAfter { get; set; }
    public int FailedMessageExpiredAfter { get; set; }

    // Extensions
    public bool UseBackpressure { get; set; }
    public bool EnableDetailedLogging { get; set; }
}
```

## Transport-Specific Options

### RabbitMQOptions

```csharp
public class RabbitMQOptions
{
    public string HostName { get; set; }
    public int Port { get; set; }
    public string UserName { get; set; }
    public string Password { get; set; }
    public string VirtualHost { get; set; }
    public string ExchangeName { get; set; }
    public Action<ConnectionFactory> ConnectionFactoryOptions { get; set; }
}
```

### KafkaOptions

```csharp
public class KafkaOptions
{
    public string Servers { get; set; }
    public Dictionary<string, string> MainConfig { get; }
    public Dictionary<string, string> ProducerConfig { get; }
    public Dictionary<string, string> ConsumerConfig { get; }
}
```

### AzureServiceBusOptions

```csharp
public class AzureServiceBusOptions
{
    public string ConnectionString { get; set; }
    public string TopicPath { get; set; }
    public string SubscriptionName { get; set; }
    public string Namespace { get; set; }
}
```

## Database-Specific Options

### SqlServerOptions

```csharp
public class SqlServerOptions
{
    public string ConnectionString { get; set; }
    public string Schema { get; set; }
    public string TableNamePrefix { get; set; }
}
```

### PostgreSqlOptions

```csharp
public class PostgreSqlOptions
{
    public string ConnectionString { get; set; }
    public string Schema { get; set; }
    public string TableNamePrefix { get; set; }
}
```

### MySqlOptions

```csharp
public class MySqlOptions
{
    public string ConnectionString { get; set; }
    public string TableNamePrefix { get; set; }
}
```

### MongoDBOptions

```csharp
public class MongoDBOptions
{
    public string DatabaseConnection { get; set; }
    public string DatabaseName { get; set; }
    public string TableNamePrefix { get; set; }
}
```

## Dashboard Options

### DashboardOptions

```csharp
public class DashboardOptions
{
    public string PathMatch { get; set; }
    public bool UseAuth { get; set; }
    public string AuthorizationPolicy { get; set; }
    public string DefaultPath { get; set; }
    public int StatsPollingInterval { get; set; }
}
```

## Extension Methods

### IServiceCollection Extensions

```csharp
public static class CapServiceCollectionExtensions
{
    public static CapBuilder AddCap(this IServiceCollection services, Action<CapOptions> setupAction);
}
```

### CapBuilder Extensions

```csharp
public static class CapBuilderExtensions
{
    // Storage
    public static CapBuilder UseSqlServer(this CapBuilder builder, string connectionString);
    public static CapBuilder UseSqlServer(this CapBuilder builder, Action<SqlServerOptions> configure);
    public static CapBuilder UsePostgreSql(this CapBuilder builder, string connectionString);
    public static CapBuilder UsePostgreSql(this CapBuilder builder, Action<PostgreSqlOptions> configure);
    public static CapBuilder UseMySql(this CapBuilder builder, string connectionString);
    public static CapBuilder UseMySql(this CapBuilder builder, Action<MySqlOptions> configure);
    public static CapBuilder UseMongoDB(this CapBuilder builder, string connectionString);
    public static CapBuilder UseMongoDB(this CapBuilder builder, Action<MongoDBOptions> configure);
    public static CapBuilder UseEntityFramework<TDbContext>(this CapBuilder builder) where TDbContext : DbContext;

    // Transports
    public static CapBuilder UseRabbitMQ(this CapBuilder builder, string hostName);
    public static CapBuilder UseRabbitMQ(this CapBuilder builder, Action<RabbitMQOptions> configure);
    public static CapBuilder UseKafka(this CapBuilder builder, string servers);
    public static CapBuilder UseKafka(this CapBuilder builder, Action<KafkaOptions> configure);
    public static CapBuilder UseAzureServiceBus(this CapBuilder builder, string connectionString);
    public static CapBuilder UseAzureServiceBus(this CapBuilder builder, Action<AzureServiceBusOptions> configure);
    public static CapBuilder UseAmazonSQS(this CapBuilder builder, Action<AmazonSQSOptions> configure);
    public static CapBuilder UseNATS(this CapBuilder builder, string url);
    public static CapBuilder UsePulsar(this CapBuilder builder, string serviceUrl);
    public static CapBuilder UseRedisStreams(this CapBuilder builder, string connectionString);

    // Features
    public static CapBuilder UseDashboard(this CapBuilder builder);
    public static CapBuilder UseDashboard(this CapBuilder builder, Action<DashboardOptions> configure);
    public static CapBuilder UseFilter<T>(this CapBuilder builder) where T : class, IFilter;
    public static CapBuilder UseCustomSerializer(this CapBuilder builder, IContentSerializer serializer);
    public static CapBuilder UseDispatchingPerGroup(this CapBuilder builder);
}
```

## Filter Interfaces

### IFilter

Base interface for filters.

```csharp
public interface IFilter
{
    // Marker interface
}
```

### IPublishFilter

Filter for publish operations.

```csharp
public interface IPublishFilter : IFilter
{
    Task Invoke(PublishContext context, PublishFilterDelegate next);
}
```

### ISubscribeFilter

Filter for subscribe operations.

```csharp
public interface ISubscribeFilter : IFilter
{
    Task Invoke(SubscribeContext context, SubscribeFilterDelegate next);
}
```

## Context Classes

### PublishContext

```csharp
public class PublishContext
{
    public string Topic { get; set; }
    public object Content { get; set; }
    public IDictionary<string, string> Headers { get; set; }
    public IServiceProvider ServiceProvider { get; set; }
}
```

### SubscribeContext

```csharp
public class SubscribeContext
{
    public string Topic { get; set; }
    public object Content { get; set; }
    public IDictionary<string, string> Headers { get; set; }
    public IServiceProvider ServiceProvider { get; set; }
}
```

## Exception Classes

### PublisherSentFailedException

```csharp
public class PublisherSentFailedException : Exception
{
    public PublisherSentFailedException(string message);
    public PublisherSentFailedException(string message, Exception innerException);
}
```

### SubscriberExecutionFailedException

```csharp
public class SubscriberExecutionFailedException : Exception
{
    public SubscriberExecutionFailedException(string message);
    public SubscriberExecutionFailedException(string message, Exception innerException);
}
```

## Database Tables

CAP creates the following tables in your database:

### Published Messages Table

```sql
CREATE TABLE [Cap].[Published] (
    [Id] bigint IDENTITY(1,1) PRIMARY KEY,
    [Version] nvarchar(20) NULL,
    [Name] nvarchar(400) NOT NULL,
    [Content] nvarchar(max) NULL,
    [Retries] int NULL,
    [Added] datetime2 NOT NULL,
    [ExpiresAt] datetime2 NULL,
    [StatusName] nvarchar(50) NOT NULL,
    [Group] nvarchar(200) NULL,
    [Type] nvarchar(200) NULL,
    [MessageId] nvarchar(50) NULL,
    [CorrelationId] nvarchar(50) NULL
);
```

### Received Messages Table

```sql
CREATE TABLE [Cap].[Received] (
    [Id] bigint IDENTITY(1,1) PRIMARY KEY,
    [Version] nvarchar(20) NULL,
    [Name] nvarchar(400) NOT NULL,
    [Group] nvarchar(200) NULL,
    [Content] nvarchar(max) NULL,
    [Retries] int NULL,
    [Added] datetime2 NOT NULL,
    [ExpiresAt] datetime2 NULL,
    [StatusName] nvarchar(50) NOT NULL,
    [Type] nvarchar(200) NULL,
    [MessageId] nvarchar(50) NULL,
    [CorrelationId] nvarchar(50) NULL
);
```