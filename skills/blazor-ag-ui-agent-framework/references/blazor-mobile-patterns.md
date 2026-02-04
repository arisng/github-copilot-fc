# Blazor Mobile Patterns for Agentic Interfaces

## Overview

Translating Dual-Pane/Canvas architecture to mobile requires fundamental adaptations for small screens. The core challenge: maintain the separation of "negotiation" (chat) and "artifact" (work product) without side-by-side space.

## Core Mobile Constraints

1. **Screen real estate**: No room for permanent side-by-side panes
2. **Thumb-first interaction**: Bottom-heavy UI, large touch targets
3. **Context switching cost**: Switching between chat/canvas is disruptive
4. **Keyboard avoidance**: Typing is cumbersome; prefer taps and gestures
5. **Network variability**: Optimize for slower connections

## Pattern 1: Modal Layers (Drawer/Sheet)

Replace permanent split screen with modal overlays.

### Base Architecture

```razor
@* MobileAGUILayout.razor *@
<div class="mobile-layout">
    <!-- Base Layer: Chat (always present) -->
    <div class="chat-layer">
        <ChatPanel Messages="@_messages" 
                   OnSendMessage="HandleSendMessage" />
    </div>
    
    <!-- Overlay Layer: Artifact (appears on demand) -->
    @if (_showArtifact) {
        <div class="artifact-sheet @_sheetState"
             @ontouchstart="HandleTouchStart"
             @ontouchmove="HandleTouchMove"
             @ontouchend="HandleTouchEnd">
            
            <div class="sheet-handle"></div>
            
            <div class="sheet-header">
                <h3>@_artifactTitle</h3>
                <button @onclick="CloseArtifact" class="close-btn">✕</button>
            </div>
            
            <div class="sheet-content">
                <ArtifactViewer Content="@_artifactContent" />
            </div>
        </div>
    }
    
    <!-- Floating Action Button -->
    <button class="fab" @onclick="ToggleArtifact">
        @if (_showArtifact) {
            <span>💬</span> <!-- Back to chat -->
        } else if (_hasArtifact) {
            <span>📄</span> <!-- View artifact -->
        }
    </button>
</div>

@code {
    private bool _showArtifact = false;
    private string _sheetState = "full"; // "peek", "half", "full"
    private double _touchStartY;
    
    private void HandleTouchStart(TouchEventArgs e) {
        _touchStartY = e.Touches[0].ClientY;
    }
    
    private void HandleTouchMove(TouchEventArgs e) {
        var deltaY = e.Touches[0].ClientY - _touchStartY;
        
        if (deltaY > 50) {
            // Swiping down - shrink sheet
            if (_sheetState == "full") _sheetState = "half";
            else if (_sheetState == "half") _sheetState = "peek";
            else CloseArtifact();
        } else if (deltaY < -50) {
            // Swiping up - expand sheet
            if (_sheetState == "peek") _sheetState = "half";
            else if (_sheetState == "half") _sheetState = "full";
        }
        
        StateHasChanged();
    }
    
    private void CloseArtifact() {
        _showArtifact = false;
        StateHasChanged();
    }
}
```

### CSS for Bottom Sheet

```css
.mobile-layout {
    height: 100vh;
    position: relative;
    overflow: hidden;
}

.chat-layer {
    height: 100%;
    overflow-y: auto;
}

.artifact-sheet {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: white;
    border-radius: 16px 16px 0 0;
    box-shadow: 0 -4px 16px rgba(0,0,0,0.2);
    transition: transform 0.3s ease;
    z-index: 1000;
}

.artifact-sheet.peek {
    transform: translateY(calc(100% - 120px));
}

.artifact-sheet.half {
    transform: translateY(50%);
}

.artifact-sheet.full {
    transform: translateY(0);
    height: 90vh;
}

.sheet-handle {
    width: 40px;
    height: 4px;
    background: var(--gray-300);
    border-radius: 2px;
    margin: 8px auto;
}

.fab {
    position: fixed;
    bottom: 24px;
    right: 24px;
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: var(--primary);
    color: white;
    border: none;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    font-size: 24px;
    z-index: 999;
}
```

## Pattern 2: Artifact Cards in Chat Stream

Instead of full overlays, embed artifact previews directly in the chat.

```razor
<div class="chat-message agent">
    <p>I've created a report for you:</p>
    
    <div class="artifact-card" @onclick="() => OpenArtifact(_artifactId)">
        <div class="artifact-preview">
            <div class="preview-content">
                @* First 3 lines of content *@
                <pre>@_artifactPreview</pre>
            </div>
            <div class="preview-overlay">
                <span>Tap to view full report</span>
            </div>
        </div>
        
        <div class="artifact-meta">
            <span class="artifact-type">📊 Report</span>
            <span class="artifact-size">2.4 KB</span>
        </div>
    </div>
</div>
```

## Pattern 3: Selection-Heavy Inputs

Replace typing with taps. Use chips, carousels, and steppers.

### Suggestion Chips

```razor
<div class="input-area">
    @if (_showSuggestions) {
        <div class="suggestion-chips">
            @foreach (var suggestion in _suggestions) {
                <button class="chip" @onclick="() => SelectSuggestion(suggestion)">
                    @suggestion.Icon @suggestion.Text
                </button>
            }
        </div>
    }
    
    <div class="input-row">
        <textarea @bind="_userInput" 
                  placeholder="Type or tap a suggestion..."
                  rows="1">
        </textarea>
        <button @onclick="Send" class="send-btn">➤</button>
    </div>
</div>

@code {
    private List<Suggestion> _suggestions = new() {
        new() { Icon = "📊", Text = "Create chart" },
        new() { Icon = "✏️", Text = "Edit document" },
        new() { Icon = "🔍", Text = "Analyze data" },
        new() { Icon = "📝", Text = "Summarize" }
    };
}
```

### Carousel for Options

```razor
<div class="option-carousel">
    <div class="carousel-track" style="transform: translateX(@_carouselOffset)">
        @foreach (var option in _options) {
            <div class="option-card" @onclick="() => SelectOption(option)">
                <div class="option-icon">@option.Icon</div>
                <div class="option-label">@option.Label</div>
            </div>
        }
    </div>
</div>
```

## Pattern 4: Stacked View for Dashboards

For complex dashboards, use vertical stacking with sticky headers.

```razor
<div class="mobile-dashboard">
    <!-- Sticky Header -->
    <div class="dashboard-header sticky">
        <h2>Sales Dashboard</h2>
        <div class="header-controls">
            <button @onclick="Refresh">🔄</button>
            <button @onclick="ShowFilters">🔍</button>
        </div>
    </div>
    
    <!-- Scrollable Sections -->
    <div class="dashboard-sections">
        <section class="dashboard-section">
            <h3>Revenue</h3>
            <div class="metric-card">
                <!-- Chart rendered as inline SVG or img -->
            </div>
        </section>
        
        <section class="dashboard-section">
            <h3>Customers</h3>
            <div class="metric-card">
                <!-- Chart -->
            </div>
        </section>
    </div>
    
    <!-- Sticky Footer Controls -->
    <div class="dashboard-footer sticky">
        <button class="footer-btn">📅 Date Range</button>
        <button class="footer-btn">📥 Export</button>
    </div>
</div>

<style>
.sticky {
    position: sticky;
    top: 0;
    z-index: 10;
    background: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.dashboard-footer.sticky {
    top: auto;
    bottom: 0;
}
</style>
```

## Pattern 5: Mobile GenUI via Declarative Components

Use A2UI/Adaptive Cards to render native-feeling mobile UI.

### Why It Matters

A JSON schema can render as:
- Web: `<div>` and CSS Grid
- Mobile: Native Blazor MAUI controls (SwiftUI-like on iOS, Material on Android)

### Example: Form Rendering

Server sends:
```json
{
  "type": "AdaptiveCard",
  "body": [
    { "type": "TextBlock", "text": "Book Flight", "size": "large" },
    { "type": "Input.Text", "id": "destination", "placeholder": "Where to?" },
    { "type": "Input.Date", "id": "date" },
    { "type": "ActionSet", "actions": [
        { "type": "Action.Submit", "title": "Search" }
      ]
    }
  ]
}
```

Mobile client renders native controls:
```razor
@* AdaptiveCardRenderer.razor *@
@foreach (var element in Card.Body) {
    @if (element.Type == "Input.Text") {
        <input type="text" 
               id="@element.Id" 
               placeholder="@element.Placeholder"
               class="native-input" />
    } else if (element.Type == "Input.Date") {
        <input type="date" 
               id="@element.Id"
               class="native-input" />
    } else if (element.Type == "ActionSet") {
        <div class="action-row">
            @foreach (var action in element.Actions) {
                <button @onclick="() => HandleAction(action)" 
                        class="native-button">
                    @action.Title
                </button>
            }
        </div>
    }
}
```

## Pattern 6: Gesture-Based Navigation

Support common mobile gestures for efficiency.

```razor
@code {
    private double _swipeStartX;
    private double _swipeStartY;
    
    private void HandleTouchStart(TouchEventArgs e) {
        _swipeStartX = e.Touches[0].ClientX;
        _swipeStartY = e.Touches[0].ClientY;
    }
    
    private void HandleTouchEnd(TouchEventArgs e) {
        var deltaX = e.ChangedTouches[0].ClientX - _swipeStartX;
        var deltaY = e.ChangedTouches[0].ClientY - _swipeStartY;
        
        // Swipe right: Go back to chat
        if (deltaX > 100 && Math.Abs(deltaY) < 50) {
            NavigateToChat();
        }
        
        // Swipe left: Next artifact version
        if (deltaX < -100 && Math.Abs(deltaY) < 50) {
            NextArtifactVersion();
        }
        
        // Swipe down: Close artifact
        if (deltaY > 100 && Math.Abs(deltaX) < 50) {
            CloseArtifact();
        }
    }
}
```

## Pattern 7: Optimistic UI for Perceived Speed

On slow connections, show optimistic updates immediately.

```csharp
private async Task SendMessage(string text) {
    // 1. Add user message immediately (optimistic)
    var userMsg = new ChatMessage {
        Role = "user",
        Content = text,
        Id = Guid.NewGuid().ToString(),
        IsPending = true
    };
    _messages.Add(userMsg);
    StateHasChanged();
    
    // 2. Add loading indicator for agent response
    var agentMsg = new ChatMessage {
        Role = "assistant",
        Content = "...",
        IsLoading = true
    };
    _messages.Add(agentMsg);
    StateHasChanged();
    
    try {
        // 3. Send to server
        var response = await _httpClient.PostAsJsonAsync("/api/chat", new { text });
        
        // 4. Update with real response when it arrives
        userMsg.IsPending = false;
        _messages.Remove(agentMsg);
        
        // Stream response
        await foreach (var chunk in response.Content.ReadAsSSEStream()) {
            // Update agent message incrementally
        }
    } catch {
        // 5. Show error and allow retry
        agentMsg.Content = "Failed to send. Tap to retry.";
        agentMsg.IsError = true;
    }
    
    StateHasChanged();
}
```

## Pattern 8: Approval Queue on Mobile

Adapt approval workflows for small screens.

```razor
<div class="mobile-approval-queue">
    @if (_pendingApprovals.Any()) {
        <!-- Floating Badge -->
        <button class="approval-badge" @onclick="ShowApprovals">
            ⚠️ @_pendingApprovals.Count
        </button>
        
        <!-- Bottom Sheet with Approvals -->
        @if (_showApprovalSheet) {
            <div class="approval-sheet">
                @foreach (var approval in _pendingApprovals) {
                    <div class="approval-card-mobile">
                        <div class="approval-summary">
                            <strong>@approval.ActionName</strong>
                            <p>@approval.Description</p>
                        </div>
                        
                        <!-- Swipeable Action Buttons -->
                        <div class="swipe-actions">
                            <button @onclick="() => Approve(approval.Id)" 
                                    class="approve">
                                ✓
                            </button>
                            <button @onclick="() => Reject(approval.Id)" 
                                    class="reject">
                                ✗
                            </button>
                        </div>
                    </div>
                }
            </div>
        }
    }
</div>
```

## Performance Optimization for Mobile

1. **Lazy-load artifacts**: Don't load content until sheet is expanded
2. **Throttle SSE updates**: Batch events every 200ms to reduce reflows
3. **Use virtual scrolling**: For long chat histories (Blazor Virtualize)
4. **Optimize images**: Compress artifact previews, use WebP
5. **Minimize animations**: Keep them short (<300ms) for 60fps
6. **Cache aggressively**: Store artifacts in local storage

```csharp
// Example: Throttled SSE updates
private Queue<AGUIEvent> _eventQueue = new();
private Timer _updateTimer;

protected override void OnInitialized() {
    _updateTimer = new Timer(200); // 200ms batch window
    _updateTimer.Elapsed += async (s, e) => {
        if (_eventQueue.Count > 0) {
            await InvokeAsync(() => {
                while (_eventQueue.TryDequeue(out var evt)) {
                    ProcessEvent(evt);
                }
                StateHasChanged();
            });
        }
    };
    _updateTimer.Start();
}

private void OnSSEEvent(AGUIEvent evt) {
    _eventQueue.Enqueue(evt);
}
```

## Accessibility on Mobile

1. **Large touch targets**: Minimum 44x44 points (iOS HIG)
2. **High contrast**: Support dark mode and respect system preferences
3. **Screen reader support**: Use `aria-label` and `aria-live`
4. **Reduce motion**: Respect `prefers-reduced-motion`

```css
/* Respect reduced motion preference */
@media (prefers-reduced-motion: reduce) {
    * {
        animation-duration: 0.01ms !important;
        transition-duration: 0.01ms !important;
    }
}

/* Support dark mode */
@media (prefers-color-scheme: dark) {
    .mobile-layout {
        background: #1a1a1a;
        color: #ffffff;
    }
}
```

## Testing Mobile Patterns

Use browser dev tools to simulate mobile:

```csharp
// In Program.cs, add mobile viewport detection
builder.Services.AddScoped<IDeviceDetector, DeviceDetector>();

// In component
@inject IDeviceDetector Device

@if (Device.IsMobile) {
    <MobileAGUILayout />
} else {
    <DesktopAGUILayout />
}
```

## Best Practices

1. **Bottom-heavy UI**: Put controls at the bottom (thumb zone)
2. **Minimize typing**: Use chips, carousels, voice input
3. **Gesture support**: Swipe for navigation, long-press for context menu
4. **Progressive disclosure**: Show summary first, details on tap
5. **Offline support**: Cache artifacts and allow offline browsing
6. **Battery efficiency**: Throttle updates, use efficient animations
7. **Network awareness**: Adjust quality based on connection speed

## When to Use Mobile Patterns

- Building Blazor MAUI apps (native mobile)
- Creating PWA with mobile-first experience
- Responsive web apps that degrade gracefully
- Mobile-only agentic applications

## Next Steps

- For dual-pane patterns: See [blazor-dual-pane-implementation.md](blazor-dual-pane-implementation.md)
- For observability: See [blazor-observability-patterns.md](blazor-observability-patterns.md)
- For approval workflows: See [blazor-hitl-patterns.md](blazor-hitl-patterns.md)
