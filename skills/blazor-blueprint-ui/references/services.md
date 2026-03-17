# Services

Source: https://blazorblueprintui.com/llms/services.txt

## Registration levels

```csharp
builder.Services.AddBlazorBlueprintPrimitives();
builder.Services.AddBlazorBlueprintComponents();
```

Use `AddBlazorBlueprintPrimitives()` for headless-only apps.  
Use `AddBlazorBlueprintComponents()` for styled components; it also registers the primitive services.

All documented runtime services are scoped except the default localizer.

## Primitive-level services

These show up even in primitive-only setups:
- `IPortalService` - portal rendering for overlays.
- `IFocusManager` - focus trap/restore for modal flows.
- `IPositioningService` - floating UI placement for popovers, tooltips, and menus.
- `DropdownManagerService` - keeps dropdown-style overlays coordinated.
- `IKeyboardShortcutService` - global keyboard shortcut registration.

You rarely call these directly unless you are extending primitives or building custom infrastructure around them.

## Component-level services

### `ToastService`

Requires `<BbToastProvider />` in the layout.

Typical usage:

```razor
@inject ToastService ToastService

<BbButton OnClick="() => ToastService.Success(\"Saved changes.\", \"Success\")">
    Save
</BbButton>
```

Use `Show(...)` for full control, `Success(...)`/`Error(...)` for common cases, and `Dismiss`/`DismissAll` when you need lifecycle control.

### `DialogService`

Requires `<BbDialogProvider />` in the layout.

Use it for awaitable programmatic dialogs instead of only markup-driven triggers:
- `AlertAsync(...)`
- `Confirm(...)`
- `PromptAsync(...)`
- `OpenAsync<TComponent>(...)`

```csharp
var confirmed = await DialogService.Confirm(
    "Delete item",
    "This action cannot be undone.");
```

## Providers checklist

Add these where appropriate in the root layout:

```razor
<BbPortalHost />
<BbToastProvider />
<BbDialogProvider />
```

- Always add `BbPortalHost` when using overlays.
- Add toast/dialog providers only if the corresponding service is used.

## Localization service hook

`AddBlazorBlueprintComponents(Action<DefaultBbLocalizer>?)` also lets you override built-in strings during startup. Read [localization.md](localization.md) when text, labels, or culture formatting need customization.
