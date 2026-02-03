---
description: 'Guidelines for developing web applications with ASP.NET Core on .NET 10.0, including Minimal APIs, Blazor, and Native AOT'
applyTo: '**/Program.cs, **/Startup.cs, **/*.razor, **/*.cshtml, **/appsettings.json, **/*.csproj, **/*.slnx, **/*.sln'
---

# ASP.NET Core (.NET 10.0) Development Guidelines

## Overview

This guide provides best practices for developing web applications and APIs using ASP.NET Core on the .NET 10.0 SDK. It focuses on modern patterns like Minimal APIs, Blazor Web Apps, and Native AOT deployment, ensuring applications are high-performance, secure, and maintainable.

## Workflow

1. **Project Setup**: Use `dotnet new webapiaot` for AOT-ready APIs or `dotnet new blazor` for modern web apps targeting .NET 10.0.
2. **Endpoint Definition**: Prefer Minimal APIs for microservices and cloud-native applications unless complex MVC features are required.
3. **Frontend Development**: Utilize Blazor for interactive web UIs, leveraging .NET 10.0's state persistence updates.
4. **Performance & AOT**: Opt for Native AOT for high-density deployments where startup time and memory footprint are critical.
5. **Security**: Implement modern authentication patterns like Passkeys (WebAuthn) supported in .NET 10.0.

## Rules & Constraints

- Target the **.NET 10.0** SDK (specifically `net10.0` TFM) for all web projects.
- Use `WebApplication.CreateSlimBuilder(args)` for Native AOT or minimal footprint applications.
- Always include `builder.Services.AddProblemDetails()` for consistent RFC 7807 error responses.
- Avoid using reflection-based APIs (like traditional JSON serialization) in Native AOT projects; use source generators instead.
- Use `RedirectHttpResult.IsLocalUrl` to prevent open redirection attacks in controllers or Minimal APIs.

## Best Practices

- **Minimal APIs**: Use `builder.Services.AddValidation()` for built-in, AOT-compatible request validation using DataAnnotations.
- **Blazor**: Use the `[PersistentState]` attribute for seamless state persistence during prerendering.
- **Error Handling**: Implement `IProblemDetailsService` to customize error responses globally.
- **Networking**: Use `WebSocketStream` for simplified real-time communication.
- **Diagnostics**: Enable metrics for authorization and identity to monitor security events.

## Code Standards

### Project Configuration
- Enable Native AOT with `<PublishAot>true</PublishAot>` in `.csproj`.
- Use `<WasmEnableHotReload>true</WasmEnableHotReload>` for Blazor WebAssembly development.

### JSON Serialization
- Define a `JsonSerializerContext` for Native AOT compatibility:
```csharp
[JsonSerializable(typeof(Todo))]
internal partial class AppJsonContext : JsonSerializerContext { }
```

### Solution Files
Starting in .NET 10, `dotnet new sln` defaults to creating SLNX format solution files instead of SLN format. The SLNX format is XML-based, more readable, and easier to maintain. Use SLNX for new ASP.NET Core solutions to benefit from better mergeability and tooling support. If you need SLN format, use `dotnet new sln --format sln`.

Example SLNX structure:
```xml
<Solution xmlns="http://schemas.microsoft.com/vs/2022/solution">
  <Project Path="MyAspNetCoreApp.csproj" />
</Solution>
```

## Common Patterns

### Minimal API with Validation and AOT
```csharp
var builder = WebApplication.CreateSlimBuilder(args);
builder.Services.AddValidation(); // Native AOT compatible validation
builder.Services.ConfigureHttpJsonOptions(options => {
    options.SerializerOptions.TypeInfoResolver = AppJsonContext.Default;
});

var app = builder.Build();

app.MapPost("/todos", (Todo todo) => Results.Created($"/todos/{todo.Id}", todo))
   .WithParameterValidation(); // Triggers automatic 400 results

app.Run();
```

### Server-Sent Events (SSE) in .NET 10.0
```csharp
app.MapGet("/updates", () =>
{
    return TypedResults.ServerSentEvents(GetUpdatesAsync());
});

async IAsyncEnumerable<SseItem<string>> GetUpdatesAsync()
{
    while (true)
    {
        yield return new SseItem<string>(DateTime.Now.ToString());
        await Task.Delay(1000);
    }
}
```

### Blazor State Persistence
```razor
@code {
    [PersistentState]
    public string SessionData { get; set; } = string.Empty;
}
```

## Validation

- **Build**: Run `dotnet build` to verify compliance with .NET 10.0 SDK.
- **Publish**: Use `dotnet publish -r win-x64 -c Release` to test Native AOT compilation warnings.
- **Safety**: Ensure all redirection logic uses `Url.IsLocalUrl` or `RedirectHttpResult.IsLocalUrl`.

## Notes on globs

This guidance applies to ASP.NET Core specific files (`Program.cs`, `.razor`, `appsettings.json`), project configurations (`.csproj`), and solution files (`.slnx`, `.sln`) for apps targeting .NET 10.0.

## References

- [ASP.NET Core .NET 10.0 Roadmap](https://learn.microsoft.com/aspnet/core/introduction/whats-new/dotnet-10)
- [Native AOT in ASP.NET Core](https://learn.microsoft.com/aspnet/core/fundamentals/native-aot)
- [Minimal APIs Overview](https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis)
- [Blazor Documentation](https://learn.microsoft.com/aspnet/core/blazor/)
- [`dotnet new sln` defaults to SLNX](https://learn.microsoft.com/en-us/dotnet/core/compatibility/sdk/10.0/dotnet-new-sln-slnx-default) - .NET 10 change for default solution format
