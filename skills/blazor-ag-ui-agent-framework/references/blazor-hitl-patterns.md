# Blazor Human-in-the-Loop (HITL) Patterns

## Overview

Human-in-the-Loop (HITL) is the "Gold Standard Pattern" for 2026 agentic systems. It transforms AI from an uncontrolled autonomous system into a manageable teammate where humans serve as supervisors, not micromanagers.

The key shift: from blocking the agent with permission requests to creating a continuous approval workflow that preserves user flow while maintaining control.

## Core Principles

1. **Non-blocking approvals**: Don't freeze the UI; queue approvals and let users batch-process
2. **Risk-based escalation**: Low-risk actions proceed autonomously; high-risk require confirmation
3. **Reversibility**: Every action should be undoable via checkpoints
4. **Transparency**: Users must see exactly what they're approving
5. **Context preservation**: Approval requests include full context, not just the action

## Pattern 1: Approval Queue (The Pending Actions Widget)

### Anti-Pattern: Blocking Modal

```razor
<!-- DON'T DO THIS -->
@if (_needsApproval) {
    <div class="modal-overlay" @onclick:stopPropagation="true">
        <div class="modal">
            <h3>Approve Action</h3>
            <p>Agent wants to delete 50 files. Allow?</p>
            <button @onclick="Approve">Yes</button>
            <button @onclick="Reject">No</button>
        </div>
    </div>
}
```

**Why it's bad:**
- Blocks the entire UI
- Breaks user's train of thought
- Forces immediate decision
- Can't batch multiple approvals

### Better Pattern: Inline Approval Card

```razor
@* ApprovalQueue.razor *@
<div class="approval-queue" role="region" aria-label="Pending approvals">
    @if (_pendingApprovals.Any()) {
        <div class="queue-header">
            <h3>⚠️ @_pendingApprovals.Count Action(s) Need Approval</h3>
            <button @onclick="ApproveAll" class="btn-approve-all">
                Approve All Low-Risk
            </button>
        </div>
        
        @foreach (var approval in _pendingApprovals) {
            <div class="approval-card @approval.RiskLevel">
                <div class="approval-header">
                    <span class="action-icon">@approval.Icon</span>
                    <h4>@approval.ActionName</h4>
                    <span class="risk-badge @approval.RiskLevel">
                        @approval.RiskLevel.ToUpper()
                    </span>
                </div>
                
                <div class="approval-body">
                    <div class="action-context">
                        <strong>What will happen:</strong>
                        <p>@approval.Description</p>
                    </div>
                    
                    @if (approval.Parameters.Any()) {
                        <details class="parameters">
                            <summary>View Parameters (@approval.Parameters.Count)</summary>
                            <pre><code>@JsonSerializer.Serialize(approval.Parameters, _jsonOptions)</code></pre>
                        </details>
                    }
                    
                    @if (!string.IsNullOrEmpty(approval.Impact)) {
                        <div class="impact-warning">
                            <strong>⚠️ Impact:</strong>
                            <p>@approval.Impact</p>
                        </div>
                    }
                    
                    @if (approval.IsEditable) {
                        <div class="edit-payload">
                            <button @onclick="() => ToggleEditMode(approval.Id)">
                                ✏️ Edit Parameters
                            </button>
                            @if (approval.EditMode) {
                                <textarea @bind="approval.EditedJson" 
                                          rows="10" 
                                          class="json-editor">
                                </textarea>
                            }
                        </div>
                    }
                </div>
                
                <div class="approval-actions">
                    <button @onclick="() => Approve(approval.Id)" 
                            class="btn-approve">
                        ✓ Approve
                    </button>
                    <button @onclick="() => ApproveAndModify(approval.Id)" 
                            class="btn-approve-edit"
                            disabled="@(!approval.EditMode)">
                        ✓ Approve with Edits
                    </button>
                    <button @onclick="() => Reject(approval.Id)" 
                            class="btn-reject">
                        ✗ Reject
                    </button>
                    <button @onclick="() => Defer(approval.Id)" 
                            class="btn-defer">
                        ⏸ Defer
                    </button>
                </div>
            </div>
        }
    } else {
        <div class="queue-empty">
            <span class="check-icon">✓</span>
            <p>No pending approvals</p>
        </div>
    }
</div>

@code {
    private List<ApprovalRequest> _pendingApprovals = new();
    
    private async Task Approve(string approvalId) {
        var approval = _pendingApprovals.FirstOrDefault(a => a.Id == approvalId);
        if (approval == null) return;
        
        await SendApprovalResponse(approvalId, true, approval.Parameters);
        _pendingApprovals.Remove(approval);
        StateHasChanged();
    }
    
    private async Task ApproveAndModify(string approvalId) {
        var approval = _pendingApprovals.FirstOrDefault(a => a.Id == approvalId);
        if (approval == null) return;
        
        try {
            var modifiedParams = JsonSerializer.Deserialize<Dictionary<string, object>>(
                approval.EditedJson
            );
            
            await SendApprovalResponse(approvalId, true, modifiedParams);
            _pendingApprovals.Remove(approval);
            StateHasChanged();
        } catch (JsonException ex) {
            // Show validation error
            approval.ValidationError = $"Invalid JSON: {ex.Message}";
        }
    }
    
    private async Task Reject(string approvalId) {
        await SendApprovalResponse(approvalId, false, null);
        _pendingApprovals.RemoveAll(a => a.Id == approvalId);
        StateHasChanged();
    }
    
    private async Task Defer(string approvalId) {
        var approval = _pendingApprovals.FirstOrDefault(a => a.Id == approvalId);
        if (approval != null) {
            approval.IsDeferred = true;
            approval.DeferredUntil = DateTime.UtcNow.AddMinutes(5);
        }
    }
    
    private async Task ApproveAll() {
        var lowRisk = _pendingApprovals.Where(a => a.RiskLevel == "low").ToList();
        
        foreach (var approval in lowRisk) {
            await Approve(approval.Id);
        }
    }
}
```

### CSS Styling

```css
.approval-queue {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1rem;
    margin: 1rem 0;
}

.approval-card {
    background: white;
    border: 2px solid var(--border);
    border-radius: 8px;
    padding: 1rem;
    margin-bottom: 1rem;
    transition: all 0.3s;
}

.approval-card.high {
    border-color: var(--danger);
    background: var(--danger-bg);
}

.approval-card.medium {
    border-color: var(--warning);
    background: var(--warning-bg);
}

.approval-card.low {
    border-color: var(--success);
}

.approval-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 1rem;
}

.risk-badge {
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
}

.risk-badge.high {
    background: var(--danger);
    color: white;
}

.risk-badge.medium {
    background: var(--warning);
    color: var(--text-dark);
}

.risk-badge.low {
    background: var(--success);
    color: white;
}

.impact-warning {
    margin: 1rem 0;
    padding: 1rem;
    background: var(--warning-bg);
    border-left: 4px solid var(--warning);
    border-radius: 4px;
}

.approval-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
}

.btn-approve {
    background: var(--success);
    color: white;
    border: none;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    cursor: pointer;
    font-weight: 500;
}

.btn-reject {
    background: var(--danger);
    color: white;
}

.btn-defer {
    background: var(--muted);
    color: var(--text);
}
```

## Pattern 2: Integration with AG-UI Protocol

AG-UI has built-in support for approval workflows via `ApprovalRequiredAIFunction`.

### Server-Side Setup

```csharp
// Program.cs or agent configuration
var agent = new AIAgent(chatClient);

// Wrap sensitive functions with approval middleware
var deleteFilesFunction = AIFunctionFactory.Create(
    DeleteFiles,
    "delete_files",
    "Deletes specified files from the file system"
);

var approvalRequired = new ApprovalRequiredAIFunction(
    deleteFilesFunction,
    riskLevel: "high"
);

agent.AddFunction(approvalRequired);

// Map endpoint
app.MapAGUI("/api/chat", agent);
```

### Client-Side Event Handling

```csharp
private async Task HandleSSEEvent(string eventData) {
    var evt = JsonSerializer.Deserialize<AGUIEvent>(eventData);
    
    if (evt.Type == "function_approval_request") {
        var approvalRequest = new ApprovalRequest {
            Id = evt.Data["approvalId"].ToString(),
            ActionName = evt.Data["functionName"].ToString(),
            Description = evt.Data["description"]?.ToString(),
            Parameters = evt.Data["arguments"].ToObject<Dictionary<string, object>>(),
            RiskLevel = evt.Data["riskLevel"]?.ToString() ?? "medium",
            Icon = GetIconForAction(evt.Data["functionName"].ToString()),
            Impact = CalculateImpact(evt.Data),
            IsEditable = true
        };
        
        _pendingApprovals.Add(approvalRequest);
        StateHasChanged();
        
        // Optional: Show notification
        await ShowToast($"Approval needed: {approvalRequest.ActionName}");
    }
}

private async Task SendApprovalResponse(
    string approvalId, 
    bool approved, 
    Dictionary<string, object> parameters) 
{
    var response = new {
        approvalId = approvalId,
        approved = approved,
        modifiedArguments = approved ? parameters : null,
        timestamp = DateTime.UtcNow
    };
    
    // Send back to agent via POST
    await _httpClient.PostAsJsonAsync(
        $"{_agentEndpoint}/approval",
        response
    );
}
```

## Pattern 3: Reversibility - Time Travel UI

Every agentic action should be undoable. Implement checkpointing for critical operations.

### Checkpoint System

```razor
@* TimeTravel.razor *@
<div class="time-travel">
    <div class="timeline-control">
        <button @onclick="Undo" disabled="@(!CanUndo)">
            ⟲ Undo
        </button>
        
        <input type="range" 
               min="0" 
               max="@(_checkpoints.Count - 1)" 
               @bind="_currentCheckpoint"
               @bind:event="oninput"
               @onchange="RestoreCheckpoint"
               class="timeline-slider" />
        
        <button @onclick="Redo" disabled="@(!CanRedo)">
            ⟳ Redo
        </button>
    </div>
    
    <div class="checkpoint-info">
        <h4>Version @(_currentCheckpoint + 1) / @_checkpoints.Count</h4>
        <p>@_checkpoints[_currentCheckpoint].Summary</p>
        <small>@_checkpoints[_currentCheckpoint].Timestamp.ToString("g")</small>
    </div>
    
    @if (_showHistory) {
        <div class="checkpoint-history">
            @foreach (var (checkpoint, index) in _checkpoints.Select((c, i) => (c, i))) {
                <div class="checkpoint-item @(index == _currentCheckpoint ? "active" : "")"
                     @onclick="() => JumpToCheckpoint(index)">
                    <span class="checkpoint-number">@(index + 1)</span>
                    <div class="checkpoint-details">
                        <strong>@checkpoint.Summary</strong>
                        <br/>
                        <small>@checkpoint.Timestamp.ToString("g")</small>
                        
                        @if (checkpoint.ActionType == "agent") {
                            <span class="action-badge agent">🤖 Agent</span>
                        } else {
                            <span class="action-badge user">👤 User</span>
                        }
                    </div>
                </div>
            }
        </div>
    }
</div>

@code {
    private List<Checkpoint> _checkpoints = new();
    private int _currentCheckpoint = 0;
    private bool _showHistory = false;
    
    private bool CanUndo => _currentCheckpoint > 0;
    private bool CanRedo => _currentCheckpoint < _checkpoints.Count - 1;
    
    public void CreateCheckpoint(string summary, string actionType, object state) {
        // If we're not at the end, truncate future checkpoints (new timeline branch)
        if (_currentCheckpoint < _checkpoints.Count - 1) {
            _checkpoints.RemoveRange(_currentCheckpoint + 1, 
                _checkpoints.Count - _currentCheckpoint - 1);
        }
        
        _checkpoints.Add(new Checkpoint {
            Id = Guid.NewGuid().ToString(),
            Summary = summary,
            ActionType = actionType,
            Timestamp = DateTime.UtcNow,
            State = JsonSerializer.Serialize(state)
        });
        
        _currentCheckpoint = _checkpoints.Count - 1;
        StateHasChanged();
    }
    
    private async Task Undo() {
        if (!CanUndo) return;
        _currentCheckpoint--;
        await RestoreCheckpoint();
    }
    
    private async Task Redo() {
        if (!CanRedo) return;
        _currentCheckpoint++;
        await RestoreCheckpoint();
    }
    
    private async Task RestoreCheckpoint() {
        var checkpoint = _checkpoints[_currentCheckpoint];
        var state = JsonSerializer.Deserialize<ArtifactState>(checkpoint.State);
        
        // Emit event to restore application state
        await OnCheckpointRestore.InvokeAsync(state);
        
        StateHasChanged();
    }
    
    private async Task JumpToCheckpoint(int index) {
        _currentCheckpoint = index;
        await RestoreCheckpoint();
    }
}
```

### Automatic Checkpoint Creation

Intercept agent actions and create checkpoints automatically:

```csharp
private async Task HandleAgentAction(AgentActionEvent evt) {
    // Create checkpoint BEFORE applying change
    _timeTravelRef.CreateCheckpoint(
        summary: $"Agent: {evt.ActionName}",
        actionType: "agent",
        state: _currentState
    );
    
    // Apply the change
    await ApplyAgentAction(evt);
    
    // Update UI
    StateHasChanged();
}
```

## Pattern 4: Diff Preview Before Approval

For code changes or document edits, show a diff view before approval.

### Diff Component

```razor
@* DiffPreview.razor *@
<div class="diff-preview">
    <div class="diff-header">
        <h4>@FileName</h4>
        <div class="diff-stats">
            <span class="additions">+@_additions lines</span>
            <span class="deletions">-@_deletions lines</span>
        </div>
    </div>
    
    <div class="diff-viewer">
        @foreach (var line in _diffLines) {
            <div class="diff-line @line.Type">
                <span class="line-number old">@line.OldLineNumber</span>
                <span class="line-number new">@line.NewLineNumber</span>
                <span class="line-content">@line.Content</span>
            </div>
        }
    </div>
</div>

@code {
    [Parameter] public string OldContent { get; set; }
    [Parameter] public string NewContent { get; set; }
    [Parameter] public string FileName { get; set; }
    
    private List<DiffLine> _diffLines = new();
    private int _additions = 0;
    private int _deletions = 0;
    
    protected override void OnParametersSet() {
        GenerateDiff();
    }
    
    private void GenerateDiff() {
        // Use DiffPlex or similar library
        var differ = new Differ();
        var diff = differ.CreateLineDiffs(OldContent, NewContent, false);
        
        _diffLines.Clear();
        int oldLine = 1, newLine = 1;
        
        foreach (var line in diff.DiffBlocks) {
            if (line.DeleteCountA > 0) {
                for (int i = 0; i < line.DeleteCountA; i++) {
                    _diffLines.Add(new DiffLine {
                        Type = "deletion",
                        OldLineNumber = oldLine++,
                        NewLineNumber = null,
                        Content = OldContent.Split('\n')[oldLine - 2]
                    });
                    _deletions++;
                }
            }
            
            if (line.InsertCountB > 0) {
                for (int i = 0; i < line.InsertCountB; i++) {
                    _diffLines.Add(new DiffLine {
                        Type = "addition",
                        OldLineNumber = null,
                        NewLineNumber = newLine++,
                        Content = NewContent.Split('\n')[newLine - 2]
                    });
                    _additions++;
                }
            }
        }
    }
}
```

### Integrate with Approval Card

```razor
<div class="approval-card">
    <h4>Code Change Requested</h4>
    
    <DiffPreview OldContent="@approval.OldCode"
                 NewContent="@approval.NewCode"
                 FileName="@approval.FileName" />
    
    <div class="approval-actions">
        <button @onclick="ApproveChanges">✓ Apply Changes</button>
        <button @onclick="RejectChanges">✗ Reject</button>
    </div>
</div>
```

## Pattern 5: The Panic Button (Kill Switch)

For autonomous agent loops, provide an emergency stop that halts execution AND reverts state.

### Implementation

```razor
<div class="agent-controls">
    @if (_agentIsRunning) {
        <button @onclick="EmergencyStop" 
                class="panic-button"
                title="Stop agent and revert changes">
            🛑 EMERGENCY STOP
        </button>
    }
</div>

@code {
    private bool _agentIsRunning = false;
    private string _preRunCheckpointId;
    
    private async Task EmergencyStop() {
        // 1. Cancel any pending requests
        _cancellationTokenSource?.Cancel();
        
        // 2. Send stop signal to agent
        await _httpClient.PostAsync($"{_agentEndpoint}/stop", null);
        
        // 3. Revert to pre-run checkpoint
        if (!string.IsNullOrEmpty(_preRunCheckpointId)) {
            var checkpoint = _checkpoints.FirstOrDefault(c => c.Id == _preRunCheckpointId);
            if (checkpoint != null) {
                await RestoreCheckpoint(checkpoint);
            }
        }
        
        // 4. Clear pending approvals
        _pendingApprovals.Clear();
        
        // 5. Notify user
        await ShowAlert("Agent stopped and changes reverted", "warning");
        
        _agentIsRunning = false;
        StateHasChanged();
    }
}
```

## Pattern 6: Approval Policies

Define rules for which actions require approval based on context.

```csharp
public class ApprovalPolicy {
    public bool RequiresApproval(
        string actionName, 
        Dictionary<string, object> parameters,
        UserContext user) 
    {
        // High-risk actions always require approval
        if (HighRiskActions.Contains(actionName)) {
            return true;
        }
        
        // Destructive operations require approval
        if (actionName.Contains("delete") || actionName.Contains("drop")) {
            return true;
        }
        
        // Large-scale operations (e.g., >100 items) require approval
        if (parameters.TryGetValue("count", out var count) 
            && (int)count > 100) {
            return true;
        }
        
        // Operations on production resources require approval
        if (parameters.TryGetValue("environment", out var env) 
            && env.ToString() == "production") {
            return true;
        }
        
        // Allow junior users less autonomy
        if (user.Role == "junior") {
            return true;
        }
        
        return false;
    }
    
    public string DetermineRiskLevel(
        string actionName, 
        Dictionary<string, object> parameters) 
    {
        if (actionName.Contains("delete") && parameters.ContainsKey("cascade")) {
            return "high";
        }
        
        if (parameters.TryGetValue("count", out var count) && (int)count > 1000) {
            return "high";
        }
        
        if (actionName.StartsWith("read") || actionName.StartsWith("get")) {
            return "low";
        }
        
        return "medium";
    }
}
```

## Best Practices

1. **Non-blocking UI**: Approval queue should be a sidebar or tab, not a modal
2. **Batch approvals**: Allow users to approve multiple low-risk actions at once
3. **Edit before approve**: Let users modify parameters before confirming
4. **Show impact**: Clearly explain what will happen (e.g., "50 files deleted")
5. **Risk-based UX**: High-risk actions get red borders, warnings, extra confirmation
6. **Automatic checkpoints**: Create undo points before every agent action
7. **Diff previews**: For code/document changes, show before/after comparison
8. **Timeout policies**: Auto-reject approvals that sit for too long
9. **Audit trail**: Log all approvals/rejections for compliance
10. **Keyboard shortcuts**: Ctrl+Y to approve, Ctrl+N to reject for power users

## Accessibility

```razor
<div role="region" 
     aria-label="Pending approvals"
     aria-live="polite">
    
    <button aria-describedby="approval-desc-@approval.Id"
            @onclick="Approve">
        Approve
    </button>
    
    <div id="approval-desc-@approval.Id" class="sr-only">
        Approval required for @approval.ActionName. 
        Risk level: @approval.RiskLevel. 
        @approval.Description
    </div>
</div>
```

## Next Steps

- For dual-pane integration: See [blazor-dual-pane-implementation.md](blazor-dual-pane-implementation.md)
- For observability: See [blazor-observability-patterns.md](blazor-observability-patterns.md)
- For mobile patterns: See [blazor-mobile-patterns.md](blazor-mobile-patterns.md)
