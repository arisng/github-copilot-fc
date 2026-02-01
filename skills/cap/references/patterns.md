# CAP Message Patterns and Best Practices

## Publishing Patterns

### Transactional Publishing

Always publish messages within database transactions to ensure consistency:

```csharp
// Entity Framework
using (var transaction = dbContext.Database.BeginTransaction(_capPublisher, autoCommit: true))
{
    // Business logic
    var order = new Order { ... };
    dbContext.Orders.Add(order);
    await dbContext.SaveChangesAsync();

    // Publish event
    await _capPublisher.PublishAsync("order.created", order);
}

// ADO.NET
using (var connection = new SqlConnection(connectionString))
using (var transaction = connection.BeginTransaction(_capPublisher, autoCommit: true))
{
    // Business logic
    // ...

    // Publish event
    await _capPublisher.PublishAsync("order.created", orderData);
}
```

### Delayed Publishing

```csharp
// Publish with delay
await _capPublisher.PublishDelayAsync(
    TimeSpan.FromMinutes(30),
    "order.payment.reminder",
    new { OrderId = orderId }
);

// Publish at specific time
await _capPublisher.PublishDelayAsync(
    DateTimeOffset.Now.AddHours(1),
    "scheduled.notification",
    notificationData
);
```

### Message Headers

```csharp
await _capPublisher.PublishAsync(
    "order.processed",
    order,
    headers: new Dictionary<string, string>
    {
        ["correlation-id"] = correlationId,
        ["user-id"] = userId,
        ["source"] = "order-service"
    }
);
```

## Subscription Patterns

### Consumer Groups

#### Competing Consumers (Load Balancing)
```csharp
[CapSubscribe("order.payment.processed", Group = "payment-processors")]
public async Task ProcessPayment(OrderPayment payment)
{
    // Only one instance will process this message
    await ProcessPaymentAsync(payment);
}
```

#### Fan-out (Broadcasting)
```csharp
[CapSubscribe("system.announcement", Group = "email-service")]
public async Task SendEmailAnnouncement(Announcement announcement)
{
    await emailService.SendAsync(announcement);
}

[CapSubscribe("system.announcement", Group = "sms-service")]
public async Task SendSmsAnnouncement(Announcement announcement)
{
    await smsService.SendAsync(announcement);
}
```

### Partial Topic Subscriptions

```csharp
[CapSubscribe("orders")]
public class OrderEventHandler : ICapSubscribe
{
    [CapSubscribe("created", IsPartial = true)]
    public async Task HandleOrderCreated(OrderCreatedEvent data)
    {
        // Handles "orders.created"
    }

    [CapSubscribe("updated", IsPartial = true)]
    public async Task HandleOrderUpdated(OrderUpdatedEvent data)
    {
        // Handles "orders.updated"
    }

    [CapSubscribe("cancelled", IsPartial = true)]
    public async Task HandleOrderCancelled(OrderCancelledEvent data)
    {
        // Handles "orders.cancelled"
    }
}
```

### Asynchronous Processing

```csharp
[CapSubscribe("heavy.processing.task")]
public async Task ProcessHeavyTask(
    HeavyTaskData data,
    CancellationToken cancellationToken)
{
    await heavyProcessor.ProcessAsync(data, cancellationToken);
}
```

### Error Handling and Retry

```csharp
[CapSubscribe("order.payment.failed")]
public async Task HandlePaymentFailure(PaymentFailureEvent failure)
{
    try
    {
        await retryPaymentService.RetryAsync(failure.PaymentId);
    }
    catch (Exception ex)
    {
        // Log error - CAP will retry based on configuration
        logger.LogError(ex, "Payment retry failed for {PaymentId}", failure.PaymentId);

        // For permanent failures, you might want to publish to dead letter queue
        await _capPublisher.PublishAsync("payment.permanent.failure", failure);
    }
}
```

## Saga Pattern Implementation

```csharp
public class OrderSaga : ICapSubscribe
{
    [CapSubscribe("order.created")]
    public async Task HandleOrderCreated(OrderCreatedEvent data)
    {
        // Step 1: Reserve inventory
        await _capPublisher.PublishAsync("inventory.reserve", new
        {
            OrderId = data.OrderId,
            Items = data.Items
        });
    }

    [CapSubscribe("inventory.reserved")]
    public async Task HandleInventoryReserved(InventoryReservedEvent data)
    {
        // Step 2: Process payment
        await _capPublisher.PublishAsync("payment.process", new
        {
            OrderId = data.OrderId,
            Amount = data.TotalAmount
        });
    }

    [CapSubscribe("payment.succeeded")]
    public async Task HandlePaymentSucceeded(PaymentSucceededEvent data)
    {
        // Step 3: Complete order
        await _capPublisher.PublishAsync("order.complete", new
        {
            OrderId = data.OrderId
        });
    }

    [CapSubscribe("payment.failed")]
    public async Task HandlePaymentFailed(PaymentFailedEvent data)
    {
        // Compensating action: Release inventory
        await _capPublisher.PublishAsync("inventory.release", new
        {
            OrderId = data.OrderId,
            Items = data.Items
        });
    }
}
```

## Idempotency Patterns

### Database-Based Idempotency

```csharp
[CapSubscribe("order.payment.processed")]
public async Task ProcessPayment(PaymentProcessedEvent data)
{
    // Check if already processed
    if (await paymentRepository.IsProcessedAsync(data.PaymentId))
    {
        return; // Idempotent - skip processing
    }

    // Process payment
    await paymentService.ProcessAsync(data);

    // Mark as processed
    await paymentRepository.MarkProcessedAsync(data.PaymentId);
}
```

### Message-Based Idempotency

```csharp
[CapSubscribe("user.registration.completed")]
public async Task HandleUserRegistration(UserRegistrationEvent data)
{
    var messageId = GetCapMessageId(); // Get from CAP headers

    if (await idempotencyStore.IsProcessedAsync(messageId))
    {
        return;
    }

    await userService.CompleteRegistrationAsync(data);
    await idempotencyStore.MarkProcessedAsync(messageId);
}
```

## Monitoring and Observability

### Structured Logging

```csharp
[CapSubscribe("order.shipped")]
public async Task HandleOrderShipped(OrderShippedEvent data)
{
    using (logger.BeginScope(new Dictionary<string, object>
    {
        ["OrderId"] = data.OrderId,
        ["CorrelationId"] = GetCorrelationId(),
        ["EventType"] = "OrderShipped"
    }))
    {
        logger.LogInformation("Processing order shipment");
        await shippingService.ProcessAsync(data);
    }
}
```

### Metrics Collection

```csharp
[CapSubscribe("payment.completed")]
public async Task HandlePaymentCompleted(PaymentCompletedEvent data)
{
    metricsService.IncrementCounter("payments.completed");

    using (metricsService.BeginTimer("payment.processing.duration"))
    {
        await paymentProcessor.CompleteAsync(data);
    }
}
```