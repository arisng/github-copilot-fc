# Overlay Components Reference

Use this file for floating, blocking, and transient surfaces. This is now overlay-only; display and data components moved to `components-display-data.md`.

**Sources:**
- https://blazorblueprintui.com/llms/components/
- https://blazorblueprintui.com/llms/components/command.txt
- https://blazorblueprintui.com/llms/components/combobox.txt
- https://blazorblueprintui.com/llms/components/toast.txt
- https://blazorblueprintui.com/llms/services.txt

## TOC
- [Overlay prerequisites](#overlay-prerequisites)
- [Choose the right overlay](#choose-the-right-overlay)
- [Declarative vs service-driven dialogs](#declarative-vs-service-driven-dialogs)
- [Search and action surfaces](#search-and-action-surfaces)
- [Reference examples](#reference-examples)

## Overlay prerequisites

Root layout requirements:
- `<BbPortalHost />` is required for floating and modal content.
- `<BbToastProvider />` is required for `ToastService` / toast notifications.
- `<BbDialogProvider />` is required for `DialogService`.

Use `AsChild` whenever you want a styled trigger such as `BbButton` to own the rendered element.

## Choose the right overlay

| Need | Prefer | Notes |
| --- | --- | --- |
| Standard modal workflow | `BbDialog` | Best for forms and medium-complexity modal content. |
| Non-dismissable destructive confirmation | `BbAlertDialog` | Prefer this over a custom dialog for high-risk actions. |
| Slide-over panel | `BbSheet` | Best for edit panels and side inspectors. |
| Mobile-first bottom or edge panel | `BbDrawer` | Good for touch-centric interactions. |
| Anchored content / mini form | `BbPopover` | Small floating content tied to a trigger. |
| Tiny explanatory hint | `BbTooltip` | Keep content short. |
| Rich preview on hover | `BbHoverCard` | Better than a tooltip when content has structure. |
| Triggered action list | `BbDropdownMenu`, `BbContextMenu`, `BbMenubar` | Pick based on trigger style and platform convention. |
| Command palette / searchable action list | `BbCommand`, `BbCommandDialog` | `BbCommandDialog` is the current best route for Ctrl/Cmd+K palettes. |
| Searchable single selection | `BbCombobox` | Selection control, not a general command surface. |
| Temporary notification | `ToastService` + `BbToastProvider` | Prefer service-driven calls for app feedback. |

## Declarative vs service-driven dialogs

Use declarative components when the dialog content belongs in the current page component.

Use `DialogService` when the action is global, reusable, or triggered from command handlers / services:

```razor
@inject DialogService DialogService
@inject ToastService ToastService

<BbButton Variant="ButtonVariant.Destructive" OnClick="DeleteAsync">
    Delete item
</BbButton>

@code {
    private async Task DeleteAsync()
    {
        var confirmed = await DialogService.Confirm(
            "Delete item",
            "This action cannot be undone.");

        if (!confirmed)
            return;

        ToastService.Success("Item deleted.", "Success");
    }
}
```

## Search and action surfaces

`BbCommand` and `BbCommandDialog` are current high-value primitives for AI-generated UX:
- grouped actions
- keyboard navigation
- shortcut hints
- optional dialog wrapper with built-in shortcut handling

`BbCombobox` should be chosen only when the user is selecting a value, not invoking arbitrary commands. It supports external async filtering via `SearchQuery` / `SearchQueryChanged`.

## Reference examples

### Declarative confirmation

```razor
<BbAlertDialog>
    <BbAlertDialogTrigger AsChild>
        <BbButton Variant="ButtonVariant.Destructive">Delete account</BbButton>
    </BbAlertDialogTrigger>
    <BbAlertDialogContent>
        <BbAlertDialogHeader>
            <BbAlertDialogTitle>Are you absolutely sure?</BbAlertDialogTitle>
            <BbAlertDialogDescription>
                This action cannot be undone.
            </BbAlertDialogDescription>
        </BbAlertDialogHeader>
        <BbAlertDialogFooter>
            <BbAlertDialogCancel>Cancel</BbAlertDialogCancel>
            <BbAlertDialogAction>Delete</BbAlertDialogAction>
        </BbAlertDialogFooter>
    </BbAlertDialogContent>
</BbAlertDialog>
```

### Command palette

```razor
<BbCommandDialog Shortcut="Ctrl+K" @bind-Open="isOpen">
    <BbCommandInput Placeholder="Type a command or search..." />
    <BbCommandList>
        <BbCommandEmpty>No results found.</BbCommandEmpty>
        <BbCommandGroup Heading="Actions">
            <BbCommandItem Value="new-project">New project</BbCommandItem>
            <BbCommandItem Value="open-settings">Open settings</BbCommandItem>
        </BbCommandGroup>
    </BbCommandList>
</BbCommandDialog>
```

### Toast feedback

```razor
@inject ToastService ToastService

<BbButton OnClick="ShowSavedToast">
    Save
</BbButton>

@code {
    private void ShowSavedToast()
    {
        ToastService.Success("Saved changes.", "Success");
    }
}
```
