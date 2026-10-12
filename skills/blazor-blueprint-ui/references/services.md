# Services

Source: https://blazorblueprintui.com/llms/services.txt

## Registration levels

```csharp
builder.Services.AddBlazorBlueprintPrimitives();
builder.Services.AddBlazorBlueprintComponents();
```

Use `AddBlazorBlueprintPrimitives()` for headless-only apps.  
Use `AddBlazorBlueprintComponents()` for styled components; it internally calls `AddBlazorBlueprintPrimitives(configureOverlays)` and then registers the component services.

All documented runtime services are scoped except `OverlayRenderingOptions`, `ThemeOptions` and the default localizer (singletons).

## Primitive-level services

These show up even in primitive-only setups:
- `OverlayRenderingOptions` (singleton) - app-wide default overlay rendering strategy (`OverlayRenderingStrategy.JavaScript` portal vs `Native` `<dialog>`).
- `INativeOverlayService` - resolves the effective strategy and drives the native `<dialog>` element; auto-falls back to JavaScript when the browser lacks `showModal()`.
- `IPortalService` - portal rendering for overlays.
- `IFocusManager` - focus trap/restore for modal flows.
- `IPositioningService` - floating UI placement for popovers, tooltips, and menus.
- `DropdownManagerService` - keeps dropdown-style overlays coordinated (registered as the concrete type).
- `IKeyboardShortcutService` - global keyboard shortcut registration with suspend/resume.

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

API summary:
- `Show(ToastData)` / `Show(description, title, variant, duration)` - full control.
- `Success(...)` / `Info(...)` / `Warning(...)` / `Error(...)` - common cases.
- `Dismiss(id)` / `DismissAll()` / `SetPosition(...)` / `ResetPosition()` - lifecycle control.
- `ToastData` carries `Title`, `Description`, `Variant` (`Default`/`Success`/`Info`/`Warning`/`Destructive`), `Size` (`Default`/`Compact`), `Position`, `Duration` (0 disables auto-dismiss), `ShowIcon`, `ShowClose`, `ActionText`/`OnAction`, `ShowCountdown`, `Class`.

### `DialogService`

Requires `<BbDialogProvider />` in the layout.

Use it for awaitable programmatic dialogs instead of only markup-driven triggers:
- `AlertAsync(...)`
- `ConfirmAsync(...)` — the synchronous `Confirm(...)` is `[Obsolete]`; use `ConfirmAsync` and check `result.Confirmed`.
- `PromptAsync(...)`
- `OpenAsync<TComponent>(...)` - custom component dialogs; the component receives a cascaded `IDialogReference` with `CloseAsync(result)` / `CancelAsync()`.

```csharp
var result = await DialogService.ConfirmAsync(
    "Delete item",
    "This action cannot be undone.");

if (result.Confirmed)
{
    ToastService.Success("Item deleted.");
}
```

## Providers checklist

Add these where appropriate in the root layout:

```razor
<BbPortalHost />
<BbToastProvider />
<BbDialogProvider />
```

- Always add `BbPortalHost` when using overlays (also keep it when using the native dialog strategy - the fallback path needs it).
- Add toast/dialog providers only if the corresponding service is used.

## Configuration overloads

`AddBlazorBlueprintComponents()` accepts optional callbacks:

```csharp
// Localization overrides
builder.Services.AddBlazorBlueprintComponents(localizer =>
{
    localizer.Set("DataGrid.Loading", "Laden...");
});

// Theme configuration at startup
builder.Services.AddBlazorBlueprintComponents(
    configureTheme: theme =>
    {
        theme.DefaultDarkMode = false;
        theme.DefaultBaseColor = BaseColor.Stone;
        theme.DefaultPrimaryColor = PrimaryColor.Blue;
        theme.DefaultRadius = 0.5;
    }
);

// App-wide overlay rendering strategy
builder.Services.AddBlazorBlueprintComponents(configureOverlays: o =>
    o.DefaultStrategy = OverlayRenderingStrategy.Native);
```

The `configureTheme` callback accepts `ThemeOptions` with:
- `DefaultPreset` (`ThemePreset?`) - replaces the four `Default*` values when set
- `DefaultDarkMode` (bool) - initial light/dark preference
- `DefaultBaseColor` (`BaseColor` enum: Zinc, Slate, Gray, Neutral, Stone)
- `DefaultPrimaryColor` (`PrimaryColor` enum: Default, Blue, Violet, ... Pink)
- `DefaultRadius` (double, 0 to 4 rem)
- `DetectSystemPreference` (bool) - OS preference when nothing is saved
- `PersistToLocalStorage` (bool)

## ThemeService

`ThemeService` (scoped) provides runtime theme control. Setters take the strongly-typed enums, not strings:

```csharp
@inject ThemeService ThemeService

// Toggle between light and dark
await ThemeService.ToggleDarkModeAsync();

// Change base color at runtime
await ThemeService.SetBaseColorAsync(BaseColor.Zinc);

// Change primary color at runtime
await ThemeService.SetPrimaryColorAsync(PrimaryColor.Violet);

// Apply a built-in preset
await ThemeService.SetPresetAsync(ThemePresets.Balanced);
```

`ThemeService.InitializeAsync()` loads the saved theme (localStorage key `bb-theme`), falling back to the OS preference and then the configured defaults. `BbThemeSwitcher`, `BbDarkModeToggle` and `BbThemeScope` provide ready-made theme UI.

## Localization service hook

`AddBlazorBlueprintComponents(Action<DefaultBbLocalizer>?)` also lets you override built-in strings during startup. `IBbLocalizer` is registered with `TryAddSingleton`, so a localizer registered before the library wins. Read [localization.md](localization.md) when text, labels, or culture formatting need customization.
