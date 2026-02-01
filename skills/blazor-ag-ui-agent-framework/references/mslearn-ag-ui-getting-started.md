# Microsoft Learn: AG-UI getting started (C#)

## Summary
- Walks through building an AG-UI server (ASP.NET Core) and a client that streams responses using SSE.
- Server setup uses `AddAGUI` and `MapAGUI`, plus a chat client adapted to `IChatClient` and `AIAgent`.
- Client setup uses `AGUIChatClient` and `RunStreamingAsync` to process response updates and maintain thread context.

## Key takeaways for .NET/Blazor
- The server requires `Microsoft.NET.Sdk.Web` and prerelease packages for AG-UI hosting.
- `AGUIChatClient` supports threaded conversations and stream handling; clients can be hosted separately from the server.
- The protocol is evolving; prerelease dependencies and version checks are expected.

## Source
- https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/getting-started
