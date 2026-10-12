# BlazorBlueprint Setup & Installation Guide

Use this file first. It reflects the current v4 docs and official `Bb*` naming.

**Sources:**
- https://blazorblueprintui.com/llms/setup.txt
- https://blazorblueprintui.com/llms/index.txt
- https://blazorblueprintui.com/llms/services.txt
- https://blazorblueprintui.com/llms/migration-v3-to-v4.txt

## TOC
- [Install packages](#install-packages)
- [Register services](#register-services)
- [Add imports and CSS](#add-imports-and-css)
- [Configure layout providers](#configure-layout-providers)
- [Theme and dark mode](#theme-and-dark-mode)
- [The bb: utility prefix](#the-bb-utility-prefix)
- [Native dialog rendering](#native-dialog-rendering)
- [App.razor head order](#apprazor-head-order)
- [Verify the install](#verify-the-install)
- [Troubleshooting](#troubleshooting)

## Install packages

Start with the styled component package unless you explicitly want a headless-only build:

```bash
dotnet add package BlazorBlueprint.Components
```

Notes:
- `BlazorBlueprint.Components` already includes the primitives layer and depends on `BlazorBlueprint.Icons.Lucide` (arrives transitively).
- No Tailwind build step is required for the components themselves; `blazorblueprint.css` is prebuilt.
- Use `BlazorBlueprint.Primitives` only when you want to supply all styling yourself.
- **.NET 10 minimum.** Version 4 targets `net10.0` only. .NET 8 and .NET 9 apps cannot consume it; retarget to `net10.0` and reference the 10.0.x `Microsoft.AspNetCore.Components` packages first.

Optional icon packages:

```bash
dotnet add package BlazorBlueprint.Icons.Heroicons
dotnet add package BlazorBlueprint.Icons.Feather
dotnet add package BlazorBlueprint.Icons.FontAwesome
```

## Register services

Register the library in `Program.cs`:

```csharp
builder.Services.AddBlazorBlueprintComponents();
```

Use this instead only for primitive-only scenarios (no `ToastService`, `DialogService`, `ThemeService` or `IBbLocalizer`):

```csharp
builder.Services.AddBlazorBlueprintPrimitives();
```

Signatures (both methods chain and return `IServiceCollection`):

```csharp
// namespace BlazorBlueprint.Components
AddBlazorBlueprintComponents(
    Action<DefaultBbLocalizer>? configureLocalizer = null,
    Action<ThemeOptions>? configureTheme = null,
    Action<OverlayRenderingOptions>? configureOverlays = null)

// namespace BlazorBlueprint.Primitives.Extensions
AddBlazorBlueprintPrimitives(Action<OverlayRenderingOptions>? configureOverlays = null)
```

Important service implications:
- `AddBlazorBlueprintComponents()` internally calls `AddBlazorBlueprintPrimitives(configureOverlays)` — never call both for a standard setup.
- `configureLocalizer` overrides localization keys at startup.
- `configureTheme` sets `ThemeService` defaults (see [services.md](services.md)).
- `configureOverlays` sets the app-wide overlay rendering strategy (JavaScript portal vs native `<dialog>`; see below).
- `ThemeOptions`, `ThemeService` and `IBbLocalizer` use `TryAdd` — a registration made before `AddBlazorBlueprintComponents()` wins.

## Add imports and CSS

`_Imports.razor`:

```razor
@using BlazorBlueprint.Components
@using BlazorBlueprint.Primitives
@using BlazorBlueprint.Primitives.Services
@using BlazorBlueprint.Icons.Lucide.Components
@using BlazorBlueprint.Icons.FontAwesome.Components
```

In v4 the portal host components (`BbPortalHost` and friends) live in **`BlazorBlueprint.Primitives`**, not `BlazorBlueprint.Primitives.Services`. `@using BlazorBlueprint.Primitives` is required where `<BbPortalHost />` is written.

Stylesheet and theme script for a Blazor Web App (put them in `App.razor`; standalone WebAssembly uses `wwwroot/index.html`):

```html
<head>
    <!-- 1. Your theme variables (optional). Load BEFORE blazorblueprint.css. -->
    <link rel="stylesheet" href="styles/theme.css" />

    <!-- 2. Your own Tailwind build output, if you have one. Any position. -->
    <link rel="stylesheet" href="css/app.css" />

    <!-- 3. Required: BlazorBlueprint styles. -->
    <link rel="stylesheet" href="_content/BlazorBlueprint.Components/blazorblueprint.css" />

    <!-- 4. Optional: base/primary color presets used by ThemeService and BbThemeSwitcher. -->
    <link rel="stylesheet" href="_content/BlazorBlueprint.Components/css/themes.css" />

    <HeadOutlet @rendermode="InteractiveServer" />

    <!-- 5. Recommended: applies the saved theme before the first paint. -->
    <script src="_content/BlazorBlueprint.Components/js/theme-init.js"></script>
</head>
```

Load order rule: theme variables before `blazorblueprint.css`; the prebuilt library CSS needs no Tailwind setup. Primitives-only apps load `_content/BlazorBlueprint.Primitives/css/primitives.css` instead of `blazorblueprint.css`.

JavaScript modules need no tags — components import their own ES modules on demand (core bundle, primitives bundle, and Apache ECharts for charts). Import URLs carry the library version as a query string, so new releases are never served from a stale cache.

## Configure layout providers

Minimal root layout:

```razor
@inherits LayoutComponentBase

<div class="min-h-screen">
    @Body
</div>

<BbPortalHost />
<BbToastProvider />
<BbDialogProvider />
```

Provider rules:
- `BbPortalHost` is required for overlay content such as `BbDialog`, `BbSheet`, `BbPopover`, `BbTooltip`, `BbDropdownMenu`, `BbHoverCard`, `BbContextMenu`, and similar floating UI.
- `BbToastProvider` is required when using `ToastService` or toast notifications.
- `BbDialogProvider` is required when using `DialogService` for programmatic alert / confirm / prompt dialogs.
- Keep these near the end of the root layout so they are always present.
- The host must be in the same render-mode scope as the interactive content that opens overlays. Under per-page interactivity with a static layout, render the providers as interactive islands with their own `@rendermode`.

## Theme and dark mode

BlazorBlueprint v4 follows the shadcn/ui-style CSS variable model, applied to `<html>` by `ThemeService` through JS interop.

High-value variables:
- Base UI: `--background`, `--foreground`, `--primary`, `--secondary`, `--accent`, `--muted`, `--border`, `--input`, `--ring`, `--radius`
- Sidebar: `--sidebar-background`, `--sidebar-foreground`, `--sidebar-primary`, `--sidebar-border`, `--sidebar-ring`
- Charts: `--chart-1` through `--chart-5`

Theme behavior:
- `theme-init.js` in `<head>` applies the saved theme (localStorage key `bb-theme`) before first paint.
- `ThemeService.InitializeAsync()` loads the saved theme, falls back to the OS color scheme (when `DetectSystemPreference` is true) and then the configured defaults.
- `BbThemeSwitcher`, `BbDarkModeToggle` and `BbThemeScope` provide ready-made theme UI.
- `ThemePresets` (Standard, Balanced, Compact, Spacious, Sharp, Dense, Glass) are the built-in starting points.

## The bb: utility prefix

**Every utility in `blazorblueprint.css` is prefixed `bb:`** (e.g. `.bb\:flex`, `.bb\:sm\:hidden`) and lives in its own `bb-utilities` cascade layer. Library classes and your own Tailwind classes can never share a name, so they never collide.

Rules for consumer markup:
- Write `Class` values **without** the prefix. The class merge (`ClassNames.cn`, a clsx + tailwind-merge equivalent) strips the library prefix before resolving conflicts, so `Class="p-6"` replaces the library's `bb:p-4`.
- `group` and `peer` markers reach the DOM in both forms (`class="group bb:group ..."`), so your own `group-*` / `peer-*` variants hung off library markup keep working.
- Two utilities are safelisted for consumers to apply by name: `bb:shimmer` (animated gradient sweep) and `bb:scroll-fade-x` (horizontal scroll edge fade).
- Do not target library internals by utility class (`.flex-col`, `.hidden`) — in v4 they carry the prefix. Prefer the `data-slot`, `data-state` and other data attributes components render.

**Apps without their own Tailwind build**: page-level utilities (`class="flex gap-4"` on your own markup) have no effect, because `blazorblueprint.css` only contains `bb:`-prefixed utilities. Either add a Tailwind build (the standalone CLI needs no Node.js) or use `bb:`-prefixed classes as a stopgap. Blueprint code has the same requirement — see [blueprints.md](blueprints.md).

## Native dialog rendering

`BbDialog` can render through the browser's native `<dialog>` element instead of the portal. A native dialog lives in the top layer, needs no `BbPortalHost`, and works across render-mode boundaries (e.g. a dialog opened from an InteractiveWebAssembly island inside a static layout).

Per dialog:

```razor
<BbDialog RenderingStrategy="OverlayRenderingStrategy.Native">
    ...
</BbDialog>
```

App-wide default (default is `OverlayRenderingStrategy.JavaScript`):

```csharp
builder.Services.AddBlazorBlueprintComponents(configureOverlays: o =>
    o.DefaultStrategy = OverlayRenderingStrategy.Native);
```

Notes:
- Only `BbDialog` has a `RenderingStrategy` parameter. `BbAlertDialog`, `BbCommandDialog`, the `BbRichTextEditor` link dialog and the `BbScheduler` event editor dialog follow the app-wide default; other overlays always use the portal path.
- Browsers without `<dialog>.showModal()` fall back to the JavaScript strategy automatically — keep `BbPortalHost` in the layout regardless.

## App.razor head order

The v4 `App.razor` head order is the stylesheet sequence in [Add imports and CSS](#add-imports-and-css): theme variables, your Tailwind build, `blazorblueprint.css`, `themes.css`, then `theme-init.js` after the stylesheets. There is no `BbProvider` wrapper in v4 — theme initialization runs through `ThemeService` and `theme-init.js`, not a root component wrapper.

## Verify the install

A small smoke test page is usually enough:

```razor
@page "/bpui-test"

<BbButton>Styled button</BbButton>

<BbDialog>
    <BbDialogTrigger AsChild>
        <BbButton Variant="ButtonVariant.Outline">Open dialog</BbButton>
    </BbDialogTrigger>
    <BbDialogContent>
        <BbDialogHeader>
            <BbDialogTitle>BlazorBlueprint is wired up</BbDialogTitle>
            <BbDialogDescription>
                If this dialog opens and is styled correctly, setup is working.
            </BbDialogDescription>
        </BbDialogHeader>
    </BbDialogContent>
</BbDialog>
```

## Troubleshooting

### Components render with no styling
- Confirm the CSS link points to `_content/BlazorBlueprint.Components/blazorblueprint.css`.
- Confirm your theme file loads before the library stylesheet.
- Confirm you actually have a Tailwind build if your page markup uses standard utilities (see [The bb: utility prefix](#the-bb-utility-prefix)).

### Dialogs, popovers, or tooltips never appear
- Confirm `<BbPortalHost />` exists in the root layout.
- Confirm `@using BlazorBlueprint.Primitives` is in scope where the host is written. Without it, Razor emits a literal `<bbportalhost>` element — no build error, no host, and overlays silently fail. Adding `@rendermode` to the tag then fails with RZ10023, which confirms it.
- Confirm the page is interactive when the component requires JS interop.
- With `OverlayRenderingStrategy.Native`, confirm the browser supports `<dialog>.showModal()`; otherwise the library falls back to the portal path (which still needs the host).

### Toasts or programmatic dialogs do nothing
- Confirm `AddBlazorBlueprintComponents()` is registered.
- Confirm `<BbToastProvider />` and/or `<BbDialogProvider />` are present in the layout.

### Dark mode does not apply
- Confirm `theme-init.js` is loaded in `<head>` after the stylesheets.
- Confirm `ThemeService.InitializeAsync()` has run (it is called automatically by `BbThemeSwitcher` / `BbDarkModeToggle` on first render).
- Confirm your dark theme variables exist in the custom theme CSS.
