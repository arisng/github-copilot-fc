# Microsoft Learn: Frontend tools (C#)

## Summary
- Frontend tools are client-registered functions that run on the client device, not the server.
- Tool declarations are captured by `AGUIChatClient` when creating the agent and sent to the server with each request.
- The server requests tool execution via SSE; the client executes and returns results to continue the agent run.

## Key takeaways for .NET/Blazor
- Register frontend tools in the client via `AIFunctionFactory.Create()` and pass them to `AsAIAgent()`.
- The server doesn’t need special configuration—standard AG-UI server handling orchestrates tool calls.

## Source
- https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/frontend-tools
