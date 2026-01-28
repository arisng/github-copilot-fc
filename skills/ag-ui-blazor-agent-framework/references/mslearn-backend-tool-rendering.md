# Microsoft Learn: Backend tool rendering (C#)

## Summary
- Backend tools are server-defined functions that the agent can call; tool calls and results stream to clients in real time.
- Tools are registered with `AIFunctionFactory.Create()` and attached to the agent when building the server.
- Clients can surface tool calls/results by handling `FunctionCallContent` and `FunctionResultContent` during streaming.

## Key takeaways for .NET/Blazor
- For complex tool parameter types, pass serializer options from ASP.NET Core `JsonOptions` into `AIFunctionFactory.Create()`.
- Backend tools centralize sensitive operations while keeping UI informed via streaming events.

## Source
- https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/backend-tool-rendering
