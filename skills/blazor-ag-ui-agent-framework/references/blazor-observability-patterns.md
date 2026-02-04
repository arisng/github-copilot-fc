# Blazor Observability Patterns for Agentic Interfaces

## Why Observability Matters

Users will not trust a "spinning loader" → result black box. Research from Stanford HAI shows that exposing Chain of Thought (CoT) reduces "black-box anxiety" by 34%. For agentic interfaces to succeed in enterprise, observability is not optional—it's the foundation of trust.

## The Glass Box Principle

Transform the AI from a "Black Box" (hidden process, mysterious results) to a "Glass Box" (visible reasoning, inspectable state, controllable execution).

**Core observability requirements:**
1. **What is the agent doing?** (Current action)
2. **Why is it doing this?** (Reasoning trace)
3. **What does it know?** (Context/memory state)
4. **What can it do?** (Available tools/capabilities)
5. **How can I control it?** (Intervention points)

## Pattern 1: Accordion of Thought

### Visual Pattern

```
┌─────────────────────────────────────────┐
│ ▼ Planning research strategy...   [2s] │ ← Expanded (current step)
│   ├─ Identified 3 search queries        │
│   ├─ Selected scholarly sources          │
│   └─ Planning synthesis approach         │
├─────────────────────────────────────────┤
│ ► Searched Google Scholar...      [3s] │ ← Collapsed (completed)
├─────────────────────────────────────────┤
│ ⟳ Synthesizing findings...         ... │ ← Active (in progress)
└─────────────────────────────────────────┘
```

### Blazor Implementation

```razor
@* AccordionOfThought.razor *@
<div class="chain-of-thought">
    @foreach (var step in _reasoningSteps) {
        <div class="thought-step @step.State">
            <div class="thought-header" @onclick="() => ToggleStep(step.Id)">
                <span class="expand-icon">
                    @if (step.IsExpanded) { 
                        <span>▼</span> 
                    } else { 
                        <span>►</span> 
                    }
                </span>
                
                <span class="step-label">@step.Label</span>
                
                <span class="step-status">
                    @if (step.State == "active") {
                        <span class="spinner"></span>
                    } else if (step.State == "completed") {
                        <span class="check">✓</span>
                    } else if (step.State == "failed") {
                        <span class="error">✗</span>
                    }
                </span>
                
                <span class="step-duration">@step.Duration</span>
            </div>
            
            @if (step.IsExpanded) {
                <div class="thought-content">
                    @if (!string.IsNullOrEmpty(step.Reasoning)) {
                        <div class="reasoning-text">
                            <strong>Reasoning:</strong>
                            <p>@step.Reasoning</p>
                        </div>
                    }
                    
                    @if (step.ToolCalls.Any()) {
                        <div class="tool-calls">
                            <strong>Tool Calls:</strong>
                            @foreach (var tool in step.ToolCalls) {
                                <details class="tool-call">
                                    <summary>@tool.Name(@tool.Arguments.Keys.Count parameters)</summary>
                                    <pre><code>@JsonSerializer.Serialize(tool.Arguments, _jsonOptions)</code></pre>
                                    @if (tool.Result != null) {
                                        <div class="tool-result">
                                            <strong>Result:</strong>
                                            <pre><code>@tool.Result</code></pre>
                                        </div>
                                    }
                                </details>
                            }
                        </div>
                    }
                </div>
            }
        </div>
    }
</div>

@code {
    private List<ReasoningStep> _reasoningSteps = new();
    
    private void ToggleStep(string stepId) {
        var step = _reasoningSteps.FirstOrDefault(s => s.Id == stepId);
        if (step != null) {
            step.IsExpanded = !step.IsExpanded;
        }
    }
    
    // Called when receiving SSE events from agent
    public void AddReasoningStep(string label, string reasoning = null) {
        _reasoningSteps.Add(new ReasoningStep {
            Id = Guid.NewGuid().ToString(),
            Label = label,
            Reasoning = reasoning,
            State = "active",
            Timestamp = DateTime.UtcNow
        });
        StateHasChanged();
    }
    
    public void UpdateStepStatus(string stepId, string state, string result = null) {
        var step = _reasoningSteps.FirstOrDefault(s => s.Id == stepId);
        if (step != null) {
            step.State = state;
            step.Duration = (DateTime.UtcNow - step.Timestamp).ToString(@"mm\:ss");
            if (result != null) step.Result = result;
            StateHasChanged();
        }
    }
}
```

### CSS Styling

```css
.chain-of-thought {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    margin: 1rem 0;
}

.thought-step {
    border-bottom: 1px solid var(--border);
}

.thought-step:last-child {
    border-bottom: none;
}

.thought-header {
    display: flex;
    align-items: center;
    padding: 0.75rem 1rem;
    cursor: pointer;
    transition: background 0.2s;
}

.thought-header:hover {
    background: var(--hover);
}

.expand-icon {
    margin-right: 0.5rem;
    color: var(--text-muted);
}

.step-label {
    flex: 1;
    font-weight: 500;
}

.step-status {
    margin: 0 0.5rem;
}

.spinner {
    display: inline-block;
    width: 12px;
    height: 12px;
    border: 2px solid var(--primary);
    border-top-color: transparent;
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

.thought-content {
    padding: 1rem;
    background: var(--surface-dark);
    border-top: 1px solid var(--border);
}

.tool-calls {
    margin-top: 0.5rem;
}

.tool-call {
    margin: 0.5rem 0;
    padding: 0.5rem;
    background: var(--surface);
    border-radius: 4px;
}

.tool-call summary {
    cursor: pointer;
    font-family: var(--mono-font);
    color: var(--primary);
}

.tool-result {
    margin-top: 0.5rem;
    padding: 0.5rem;
    background: var(--success-bg);
    border-left: 3px solid var(--success);
}
```

### Integration with AG-UI SSE

```csharp
private async Task HandleAGUIEvent(string eventData) {
    var evt = JsonSerializer.Deserialize<AGUIEvent>(eventData);
    
    switch (evt.Type) {
        case "reasoning_start":
            _accordionRef.AddReasoningStep(
                evt.Data["label"].ToString(),
                evt.Data["reasoning"]?.ToString()
            );
            break;
            
        case "tool_call_start":
            var currentStep = _reasoningSteps.Last();
            currentStep.ToolCalls.Add(new ToolCall {
                Name = evt.Data["tool"].ToString(),
                Arguments = evt.Data["arguments"].ToObject<Dictionary<string, object>>()
            });
            StateHasChanged();
            break;
            
        case "tool_call_complete":
            var stepId = evt.Data["stepId"].ToString();
            var result = evt.Data["result"].ToString();
            _accordionRef.UpdateStepStatus(stepId, "completed", result);
            break;
            
        case "reasoning_complete":
            var completedStepId = evt.Data["stepId"].ToString();
            _accordionRef.UpdateStepStatus(completedStepId, "completed");
            break;
    }
}
```

## Pattern 2: Interactive Reasoning Graph

For complex multi-step reasoning, visualize as an interactive graph where users can inspect and intervene.

### Blazor Component with SVG

```razor
@* ReasoningGraph.razor *@
<svg class="reasoning-graph" viewBox="0 0 800 600">
    @foreach (var edge in _edges) {
        <line x1="@edge.X1" y1="@edge.Y1" 
              x2="@edge.X2" y2="@edge.Y2" 
              class="reasoning-edge" />
    }
    
    @foreach (var node in _nodes) {
        <g class="reasoning-node @node.State" 
           transform="translate(@node.X, @node.Y)"
           @onclick="() => InspectNode(node.Id)">
            <circle r="30" class="node-circle" />
            <text text-anchor="middle" dy="0.3em">@node.Label</text>
        </g>
    }
</svg>

@if (_selectedNode != null) {
    <div class="node-inspector">
        <h3>@_selectedNode.Label</h3>
        <div class="node-details">
            <p><strong>Reasoning:</strong> @_selectedNode.Reasoning</p>
            <p><strong>State:</strong> @_selectedNode.State</p>
            
            @if (_selectedNode.CanPrune) {
                <button @onclick="() => PruneNode(_selectedNode.Id)">
                    ✂️ Prune this path
                </button>
            }
            
            @if (_selectedNode.CanRedirect) {
                <input type="text" 
                       placeholder="Try a different approach..."
                       @bind="_redirectPrompt" />
                <button @onclick="() => RedirectNode(_selectedNode.Id)">
                    ↪️ Redirect
                </button>
            }
        </div>
    </div>
}
```

### Advanced: User Intervention

Allow users to "prune" bad reasoning paths or redirect the agent:

```csharp
private async Task PruneNode(string nodeId) {
    // Send signal to agent to abandon this reasoning branch
    await SendToAgent(new {
        action = "prune_reasoning",
        nodeId = nodeId
    });
    
    // Remove node and descendants from UI
    RemoveNodeAndDescendants(nodeId);
    StateHasChanged();
}

private async Task RedirectNode(string nodeId) {
    // Inject new reasoning direction
    await SendToAgent(new {
        action = "redirect_reasoning",
        nodeId = nodeId,
        newDirection = _redirectPrompt
    });
}
```

## Pattern 3: Memory Inspector (The Brain Panel)

Show users what the agent knows and allow them to manage it.

### Blazor Component

```razor
@* MemoryInspector.razor *@
<div class="memory-inspector">
    <h3>🧠 Agent Memory</h3>
    
    <section class="memory-section">
        <h4>Active Facts</h4>
        <div class="memory-items">
            @foreach (var fact in _activeFacts) {
                <div class="memory-item">
                    <span class="fact-text">@fact.Text</span>
                    <span class="fact-source">
                        Added @fact.Timestamp.ToString("g")
                    </span>
                    <button @onclick="() => RemoveFact(fact.Id)" 
                            class="remove-btn" 
                            title="Forget this">
                        ✕
                    </button>
                </div>
            }
        </div>
        
        <div class="add-fact">
            <input type="text" 
                   placeholder="Add a fact the agent should remember..."
                   @bind="_newFact" />
            <button @onclick="AddFact">+ Add</button>
        </div>
    </section>
    
    <section class="memory-section">
        <h4>Conversation Context</h4>
        <div class="context-stats">
            <div class="stat">
                <span class="stat-label">Messages:</span>
                <span class="stat-value">@_messageCount</span>
            </div>
            <div class="stat">
                <span class="stat-label">Tokens:</span>
                <span class="stat-value">@_tokenCount / @_maxTokens</span>
            </div>
            <div class="stat">
                <span class="stat-label">Context utilization:</span>
                <div class="progress-bar">
                    <div class="progress-fill" 
                         style="width: @(_tokenCount * 100.0 / _maxTokens)%">
                    </div>
                </div>
            </div>
        </div>
    </section>
    
    <section class="memory-section">
        <h4>Tool Availability</h4>
        <div class="tool-list">
            @foreach (var tool in _availableTools) {
                <div class="tool-item @(tool.IsEnabled ? "enabled" : "disabled")">
                    <span class="tool-icon">@tool.Icon</span>
                    <span class="tool-name">@tool.Name</span>
                    <span class="tool-status">
                        @if (tool.RequiresAuth && !tool.IsAuthenticated) {
                            <span class="auth-warning">⚠️ Not authenticated</span>
                        } else if (tool.IsEnabled) {
                            <span class="enabled-badge">✓ Available</span>
                        } else {
                            <span class="disabled-badge">Disabled</span>
                        }
                    </span>
                </div>
            }
        </div>
    </section>
</div>

@code {
    private List<MemoryFact> _activeFacts = new();
    private List<ToolInfo> _availableTools = new();
    private string _newFact;
    private int _messageCount;
    private int _tokenCount;
    private int _maxTokens = 128000;
    
    private async Task AddFact() {
        if (string.IsNullOrWhiteSpace(_newFact)) return;
        
        await SendToAgent(new {
            action = "add_memory",
            fact = _newFact
        });
        
        _activeFacts.Add(new MemoryFact {
            Id = Guid.NewGuid().ToString(),
            Text = _newFact,
            Timestamp = DateTime.UtcNow
        });
        
        _newFact = string.Empty;
        StateHasChanged();
    }
    
    private async Task RemoveFact(string factId) {
        await SendToAgent(new {
            action = "remove_memory",
            factId = factId
        });
        
        _activeFacts.RemoveAll(f => f.Id == factId);
        StateHasChanged();
    }
}
```

## Pattern 4: Swarm Status Visualization

For multi-agent orchestration, show which agents are working and how they collaborate.

### Horizontal Timeline

```razor
@* SwarmStatus.razor *@
<div class="swarm-timeline">
    <div class="timeline-header">
        <h4>Agent Swarm Activity</h4>
        <span class="elapsed-time">Elapsed: @_elapsedTime</span>
    </div>
    
    <div class="timeline-track">
        @foreach (var agent in _agents) {
            <div class="agent-lane">
                <div class="agent-label">@agent.Name</div>
                <div class="agent-track">
                    @foreach (var activity in agent.Activities) {
                        <div class="activity-block @activity.State"
                             style="left: @activity.StartPercent%; width: @activity.DurationPercent%"
                             title="@activity.Description">
                            @activity.Label
                        </div>
                    }
                </div>
            </div>
        }
    </div>
    
    <div class="timeline-baton-passes">
        @foreach (var handoff in _batonPasses) {
            <div class="baton-pass" style="left: @handoff.TimePercent%">
                <div class="pass-indicator">→</div>
                <div class="pass-tooltip">
                    @handoff.FromAgent → @handoff.ToAgent
                    <br/>
                    <small>@handoff.DataDescription</small>
                </div>
            </div>
        }
    </div>
</div>
```

### CSS for Timeline

```css
.swarm-timeline {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1rem;
    margin: 1rem 0;
}

.timeline-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 1rem;
}

.agent-lane {
    display: flex;
    margin-bottom: 0.5rem;
}

.agent-label {
    width: 120px;
    font-weight: 500;
    padding: 0.5rem;
}

.agent-track {
    flex: 1;
    position: relative;
    height: 40px;
    background: var(--surface-dark);
    border-radius: 4px;
}

.activity-block {
    position: absolute;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.8rem;
    color: white;
    border-radius: 4px;
    overflow: hidden;
}

.activity-block.active {
    background: var(--primary);
    animation: pulse 2s ease-in-out infinite;
}

.activity-block.completed {
    background: var(--success);
}

.activity-block.pending {
    background: var(--muted);
}

@keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.7; }
}

.baton-pass {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 2px;
    background: var(--accent);
}

.pass-indicator {
    position: absolute;
    top: 50%;
    left: -10px;
    font-size: 1.5rem;
    color: var(--accent);
}

.pass-tooltip {
    position: absolute;
    top: -40px;
    left: 10px;
    background: var(--tooltip-bg);
    color: var(--tooltip-text);
    padding: 0.5rem;
    border-radius: 4px;
    font-size: 0.75rem;
    white-space: nowrap;
    opacity: 0;
    transition: opacity 0.3s;
}

.baton-pass:hover .pass-tooltip {
    opacity: 1;
}
```

## Pattern 5: Progressive Disclosure Controls

Don't overwhelm users with all observability data at once. Use progressive disclosure.

### Collapsible Observability Panel

```razor
<div class="observability-controls">
    <button @onclick="() => _showObservability = !_showObservability">
        @(_showObservability ? "Hide" : "Show") Agent Internals
    </button>
    
    @if (_showObservability) {
        <div class="observability-level">
            <label>Detail Level:</label>
            <select @bind="_detailLevel">
                <option value="minimal">Minimal (status only)</option>
                <option value="standard">Standard (reasoning steps)</option>
                <option value="verbose">Verbose (full traces)</option>
            </select>
        </div>
    }
</div>

@if (_showObservability) {
    <div class="observability-panel @_detailLevel">
        @if (_detailLevel == "minimal") {
            <AgentStatusIndicator State="@_agentState" />
        } else if (_detailLevel == "standard") {
            <AccordionOfThought Steps="@_reasoningSteps" />
        } else {
            <AccordionOfThought Steps="@_reasoningSteps" />
            <MemoryInspector />
            <SwarmStatus />
        </div>
    </div>
}
```

## Performance Considerations

1. **Throttle updates**: Don't re-render on every SSE event; batch updates every 100-200ms
2. **Virtualize long lists**: Use `Virtualize` component for long reasoning traces
3. **Lazy-load details**: Don't load tool results until user expands accordion
4. **Debounce graph layouts**: Recalculate graph positions only when nodes stabilize

```csharp
private Timer _updateTimer;
private Queue<AGUIEvent> _pendingEvents = new();

protected override void OnInitialized() {
    _updateTimer = new Timer(100);
    _updateTimer.Elapsed += async (s, e) => {
        if (_pendingEvents.Count > 0) {
            await InvokeAsync(() => {
                while (_pendingEvents.TryDequeue(out var evt)) {
                    ProcessEvent(evt);
                }
                StateHasChanged();
            });
        }
    };
    _updateTimer.Start();
}
```

## Accessibility

Ensure observability UI is accessible:

```razor
<div class="chain-of-thought" 
     role="region" 
     aria-label="Agent reasoning steps"
     aria-live="polite">
    
    <button class="thought-header"
            aria-expanded="@step.IsExpanded"
            aria-controls="thought-content-@step.Id">
        @step.Label
    </button>
    
    <div id="thought-content-@step.Id"
         class="thought-content"
         role="region"
         aria-labelledby="thought-header-@step.Id"
         hidden="@(!step.IsExpanded)">
        @step.Content
    </div>
</div>
```

## Best Practices

1. **Default to collapsed**: Show high-level status by default; expand on demand
2. **Real-time updates**: Use SSE to stream reasoning steps as they happen
3. **Enable intervention**: Let power users prune/redirect reasoning
4. **Show what matters**: Token usage, tool availability, critical errors
5. **Use visual hierarchy**: Active steps prominent, completed steps muted
6. **Provide export**: Let users export reasoning traces for debugging

## Next Steps

- For dual-pane integration: See [blazor-dual-pane-implementation.md](blazor-dual-pane-implementation.md)
- For approval workflows: See [blazor-hitl-patterns.md](blazor-hitl-patterns.md)
