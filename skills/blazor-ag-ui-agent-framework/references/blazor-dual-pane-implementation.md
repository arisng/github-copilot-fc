# Blazor Dual-Pane Architecture Implementation

## Overview

The Dual-Pane Architecture is the foundational UX pattern for agentic interfaces in 2026. It separates the "negotiation" (chat/commands) from the "artifact" (the work product), enabling co-creation workflows where human and AI work side-by-side on persistent, stateful objects.

## Core Architecture

### Two Panes, Two Purposes

```
┌─────────────────┬────────────────────────────┐
│  Context Pane   │      Canvas Pane          │
│  (Meta-Channel) │   (Object-Channel)        │
│                 │                            │
│  [Chat UI]      │   [Artifact/Editor]       │
│  - Messages     │   - Code/Document/UI      │
│  - Tool calls   │   - Interactive elements  │
│  - Approvals    │   - Direct editing        │
│  - Memory       │   - Version history       │
└─────────────────┴────────────────────────────┘
```

**Context Pane (Left/Sidebar):**
- Purpose: Intent expression, plan negotiation, feedback
- State: Ephemeral (scrolls away)
- Interaction: Linear, chronological text stream
- Blazor component: `<ChatPanel>`

**Canvas Pane (Right/Main):**
- Purpose: Artifact creation and manipulation
- State: Persistent (updates in place)
- Interaction: Spatial, non-linear, highly interactive
- Blazor component: `<ArtifactCanvas>`

## Blazor Component Structure

### Basic Layout

```razor
@* DualPaneLayout.razor *@
<div class="dual-pane-container">
    <aside class="context-pane @(_contextPaneCollapsed ? "collapsed" : "")">
        <ChatPanel 
            Messages="@_messages"
            OnSendMessage="HandleSendMessage"
            OnToolApproval="HandleToolApproval" />
    </aside>
    
    <main class="canvas-pane">
        <ArtifactCanvas 
            ArtifactId="@_currentArtifactId"
            Content="@_artifactContent"
            OnSelectionChanged="HandleSelectionChanged"
            OnContentEdited="HandleContentEdited" />
    </main>
    
    <button class="pane-toggle" @onclick="ToggleContextPane">
        @(_contextPaneCollapsed ? "◀" : "▶")
    </button>
</div>

@code {
    private bool _contextPaneCollapsed = false;
    private List<ChatMessage> _messages = new();
    private string _currentArtifactId;
    private string _artifactContent;
    private string _selectedText;
    
    private void ToggleContextPane() => _contextPaneCollapsed = !_contextPaneCollapsed;
}
```

### CSS Grid Implementation

```css
.dual-pane-container {
    display: grid;
    grid-template-columns: 320px 1fr;
    height: 100vh;
    gap: 0;
}

.context-pane {
    grid-column: 1;
    overflow-y: auto;
    border-right: 1px solid var(--border-color);
    transition: transform 0.3s ease;
}

.context-pane.collapsed {
    transform: translateX(-100%);
}

.canvas-pane {
    grid-column: 2;
    overflow: auto;
    position: relative;
}

.pane-toggle {
    position: fixed;
    left: 320px;
    top: 50%;
    z-index: 100;
}

/* Responsive: Stack on mobile */
@media (max-width: 768px) {
    .dual-pane-container {
        grid-template-columns: 1fr;
        grid-template-rows: auto 1fr;
    }
    
    .context-pane {
        grid-column: 1;
        grid-row: 1;
        max-height: 40vh;
    }
    
    .canvas-pane {
        grid-column: 1;
        grid-row: 2;
    }
}
```

## Contextual Scoping: Highlight-to-Prompt

The killer feature of Dual-Pane is **spatial deictic referencing** - users point at things in the Canvas instead of verbally describing them.

### Implementation Pattern

```razor
@* ArtifactCanvas.razor *@
<div class="artifact-canvas" 
     @onmouseup="HandleMouseUp"
     @ontouchend="HandleTouchEnd">
    <pre><code id="artifact-content">@Content</code></pre>
    
    @if (_showScopedPrompt) {
        <div class="scoped-prompt-overlay" 
             style="top: @_promptPosition.Y; left: @_promptPosition.X">
            <input type="text" 
                   placeholder="Edit this selection..." 
                   @bind="_scopedPrompt"
                   @onkeydown="HandleScopedPromptKeydown" />
            <button @onclick="SendScopedPrompt">✓</button>
            <button @onclick="CancelScopedPrompt">✕</button>
        </div>
    }
</div>

@code {
    [Parameter] public string Content { get; set; }
    [Parameter] public EventCallback<SelectionContext> OnSelectionChanged { get; set; }
    
    private bool _showScopedPrompt = false;
    private (double X, double Y) _promptPosition;
    private string _scopedPrompt;
    private string _selectedText;
    private (int Start, int End) _selectedRange;
    
    private async Task HandleMouseUp(MouseEventArgs e) {
        var selection = await JS.InvokeAsync<SelectionResult>("getSelection");
        
        if (!string.IsNullOrWhiteSpace(selection.Text)) {
            _selectedText = selection.Text;
            _selectedRange = (selection.Start, selection.End);
            _promptPosition = (e.ClientX, e.ClientY);
            _showScopedPrompt = true;
            StateHasChanged();
        }
    }
    
    private async Task SendScopedPrompt() {
        var context = new SelectionContext {
            SelectedText = _selectedText,
            Range = _selectedRange,
            Prompt = _scopedPrompt,
            FullContent = Content
        };
        
        await OnSelectionChanged.InvokeAsync(context);
        _showScopedPrompt = false;
        _scopedPrompt = string.Empty;
    }
}
```

### JavaScript Interop for Selection

```javascript
// wwwroot/selection.js
window.getSelection = function() {
    const selection = window.getSelection();
    const range = selection.getRangeAt(0);
    const preNode = document.getElementById('artifact-content');
    
    return {
        text: selection.toString(),
        start: getTextOffset(preNode, range.startContainer, range.startOffset),
        end: getTextOffset(preNode, range.endContainer, range.endOffset)
    };
};

function getTextOffset(parent, node, offset) {
    let textOffset = 0;
    const walker = document.createTreeWalker(parent, NodeFilter.SHOW_TEXT);
    
    while (walker.nextNode()) {
        if (walker.currentNode === node) {
            return textOffset + offset;
        }
        textOffset += walker.currentNode.textContent.length;
    }
    
    return textOffset;
}
```

## Integrating with AG-UI

### Sending Scoped Requests

When a user highlights text and provides a scoped prompt, send the selection context to the agent:

```csharp
private async Task HandleSelectionChanged(SelectionContext context) {
    var request = new ChatRequest {
        ConversationId = _conversationId,
        Messages = new List<ChatMessage> {
            new() {
                Role = "user",
                Content = $"[SELECTED TEXT: lines {context.Range.Start}-{context.Range.End}]\n" +
                          $"{context.SelectedText}\n\n" +
                          $"[USER REQUEST]: {context.Prompt}"
            }
        },
        Metadata = new Dictionary<string, object> {
            ["artifactId"] = _currentArtifactId,
            ["selectionRange"] = context.Range
        }
    };
    
    await SendToAgent(request);
}
```

### Agent-Side Handling

The agent receives the selection context and can perform "surgical" edits:

```csharp
// In your AIAgent tool definition
[AIFunction("apply_scoped_edit")]
public static async Task<string> ApplyScopedEdit(
    [Description("The new content to replace the selection")] string newContent,
    [Description("Start position of selection")] int start,
    [Description("End position of selection")] int end,
    [Description("Full artifact content")] string fullContent) 
{
    var before = fullContent.Substring(0, start);
    var after = fullContent.Substring(end);
    
    return before + newContent + after;
}
```

## State Synchronization

### The Golden Record Problem

The Canvas artifact state must stay in sync with:
1. The agent's memory of the artifact
2. The chat history referencing the artifact
3. The user's local edits

**Solution: Server-authoritative state with JSON Patch**

```csharp
// Server-side artifact manager
public class ArtifactStateManager {
    private readonly ConcurrentDictionary<string, ArtifactVersion> _artifacts = new();
    
    public async Task<JsonPatch> UpdateArtifact(
        string artifactId, 
        Func<string, string> transformation) 
    {
        var current = _artifacts[artifactId];
        var updated = transformation(current.Content);
        
        // Generate JSON Patch (RFC 6902)
        var patch = JsonPatchGenerator.Generate(current.Content, updated);
        
        current.Content = updated;
        current.Version++;
        
        // Broadcast patch to all connected clients via SSE
        await BroadcastPatch(artifactId, patch);
        
        return patch;
    }
}
```

### Client-Side Patch Application

```csharp
// Blazor component receiving SSE events
private async Task HandleSSEEvent(string eventData) {
    var evt = JsonSerializer.Deserialize<AGUIEvent>(eventData);
    
    if (evt.Type == "artifact_patch") {
        var patch = evt.Data.ToObject<JsonPatch>();
        
        // Apply patch to current state
        _artifactContent = JsonPatchApplier.Apply(_artifactContent, patch);
        StateHasChanged();
    }
}
```

## Attention Management

### Collapsible Context Pane

Allow users to enter "Deep Work" mode by collapsing the chat:

```csharp
// DualPaneLayout.razor
private async Task EnterDeepWorkMode() {
    _contextPaneCollapsed = true;
    await JS.InvokeVoidAsync("enterFullscreen", "canvas-pane");
    
    // Show minimal agent status indicator
    _showFloatingStatus = true;
}
```

### Floating Status Indicator

```razor
@if (_showFloatingStatus && _contextPaneCollapsed) {
    <div class="floating-status">
        <div class="status-indicator @_agentStatus">
            @if (_agentStatus == "thinking") {
                <span class="spinner"></span> Agent thinking...
            } else if (_agentStatus == "idle") {
                <span class="check">✓</span> Ready
            }
        </div>
    </div>
}
```

## Versioning & Time Travel

### Checkpoint System

```csharp
public class ArtifactVersion {
    public string Id { get; set; }
    public string Content { get; set; }
    public int Version { get; set; }
    public DateTime Timestamp { get; set; }
    public string ChangeSummary { get; set; }
    public List<ArtifactVersion> History { get; set; } = new();
    
    public void CreateCheckpoint(string summary) {
        History.Add(new ArtifactVersion {
            Id = Id,
            Content = Content,
            Version = Version,
            Timestamp = DateTime.UtcNow,
            ChangeSummary = summary
        });
    }
    
    public void RestoreVersion(int versionNumber) {
        var target = History.FirstOrDefault(h => h.Version == versionNumber);
        if (target != null) {
            Content = target.Content;
            Version = versionNumber;
        }
    }
}
```

### Version Timeline UI

```razor
<div class="version-timeline">
    <input type="range" 
           min="1" 
           max="@_artifact.History.Count" 
           @bind="_selectedVersion"
           @bind:event="oninput"
           @onchange="RestoreVersion" />
    
    <div class="version-info">
        Version @_selectedVersion / @_artifact.History.Count
        <br/>
        @_artifact.History[_selectedVersion - 1].ChangeSummary
        <br/>
        <small>@_artifact.History[_selectedVersion - 1].Timestamp.ToString("g")</small>
    </div>
</div>
```

## Best Practices

1. **Keep panes synchronized**: Use ConversationId to link chat messages with artifact versions
2. **Token efficiency**: Only send deltas (selection context) to the agent, not full artifact
3. **Preserve user flow**: Don't interrupt with modals; use inline cards for approvals
4. **Enable keyboard navigation**: Ctrl+B to toggle context pane, Ctrl+Z for undo
5. **Show what's happening**: Always visualize agent activity in the collapsed state
6. **Support branching**: Let users explore alternative approaches without losing work

## Next Steps

- For observability patterns: See [blazor-observability-patterns.md](blazor-observability-patterns.md)
- For approval workflows: See [blazor-hitl-patterns.md](blazor-hitl-patterns.md)
- For mobile adaptation: See [blazor-mobile-patterns.md](blazor-mobile-patterns.md)
