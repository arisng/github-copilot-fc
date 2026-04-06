# BlazorBlueprint Setup & Installation Guide

Use this file first. It reflects the current v3 docs and official `Bb*` naming.

**Sources:**
- https://blazorblueprintui.com/llms/setup.txt
- https://blazorblueprintui.com/llms/index.txt
- https://blazorblueprintui.com/llms/services.txt

## TOC
- [Install packages](#install-packages)
- [Register services](#register-services)
- [Add imports and CSS](#add-imports-and-css)
- [Configure layout providers](#configure-layout-providers)
- [Theme and dark mode](#theme-and-dark-mode)
- [Tailwind subset limitation](#tailwind-subset-limitation)
- [App.razor bootstrap order](#apprazor-bootstrap-order)
- [Verify the install](#verify-the-install)
- [Troubleshooting](#troubleshooting)

## Install packages

Start with the styled component package unless you explicitly want a headless-only build:

```bash
dotnet add package BlazorBlueprint.Components
```

Notes:
- `BlazorBlueprint.Components` already includes the primitives layer.
- No Tailwind build step is required in the consuming app.
- Use `BlazorBlueprint.Primitives` only when you want to supply all styling yourself.

Optional icon packages:

```bash
dotnet add package BlazorBlueprint.Icons.Lucide
dotnet add package BlazorBlueprint.Icons.Heroicons
dotnet add package BlazorBlueprint.Icons.Feather
```

## Register services

Register the library in `Program.cs`:

```csharp
builder.Services.AddBlazorBlueprintComponents();
```

Use this instead only for primitive-only scenarios:

```csharp
builder.Services.AddBlazorBlueprintPrimitives();
```

Important service implications:
- `AddBlazorBlueprintComponents()` registers the primitive services plus `ToastService` and `DialogService`.
- You do **not** call both registration methods.
- Localization overrides can be supplied through the optional callback overload of `AddBlazorBlueprintComponents(...)`.

## Add imports and CSS

`_Imports.razor`:

```razor
@using BlazorBlueprint.Components
@using BlazorBlueprint.Primitives
@using BlazorBlueprint.Icons.Lucide.Components
```

Add the stylesheet to `App.razor` (Blazor Web App) or `_Host.cshtml` (older Blazor Server hosting):

```html
<link rel="stylesheet" href="_content/BlazorBlueprint.Components/blazorblueprint.css" />
```

If you maintain a custom theme file, load it **before** `blazorblueprint.css` so the CSS variables already exist.

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

## Theme and dark mode

BlazorBlueprint follows the shadcn/ui-style CSS variable model.

High-value variables:
- Base UI: `--background`, `--foreground`, `--primary`, `--secondary`, `--accent`, `--muted`, `--border`, `--input`, `--ring`, `--radius`
- Sidebar: `--sidebar-background`, `--sidebar-foreground`, `--sidebar-primary`, `--sidebar-border`, `--sidebar-ring`
- Charts: `--chart-1` through `--chart-5`

Dark mode is activated by applying `.dark` to `<html>`. The library will automatically consume the dark variables from your theme.

## Tailwind subset limitation

**BB does not bundle the full Tailwind CSS utility catalog.** It only ships the utilities its own components actually use. Writing a Tailwind class that is absent from BB's bundle silently has no effect — there is no build error and no browser warning.

**Confirmed absent utilities** (common ones that will not render):

| Missing class | Substitute / workaround |
|---|---|
| `lg:grid-cols-2` | Use `md:grid-cols-2` (available) |
| `lg:block` | Custom CSS |
| `pb-20`, `md:pb-0` | Custom CSS |
| `rounded-xl` | Use `rounded-lg` (available) |
| `p-10` | Use `p-8` (available) |
| `bg-primary/10` | `color-mix(in srgb, var(--color-primary) 10%, transparent)` |
| `bg-background/70` | `color-mix(in srgb, var(--color-background) 70%, transparent)` |
| `xl:*` (most xl variants) | `@media (min-width: 1280px)` in custom CSS |

**Fix pattern**: Add missing utilities to a custom CSS override file:

```css
/* Compensate for BB's missing Tailwind utilities */
.pb-20 { padding-bottom: 5rem; }
@media (min-width: 768px) {
    .md\:pb-0 { padding-bottom: 0; }
}

/* Opacity modifiers */
.my-cover-panel {
    background-color: color-mix(in srgb, var(--color-primary) 8%, transparent);
}
```

**Audit approach**: If a utility class doesn't render, open DevTools → computed styles → verify the rule is present. If absent, it is not in BB's bundle.

## App.razor bootstrap order

`App.razor` must wrap the entire app in `<BbProvider>` so the theme configuration is set before anything renders. `ThemeInitializer` (or equivalent) runs inside `<CascadingAuthenticationState>` after authentication to load tenant/user-specific theme overrides.

The required order is:

1. `<BbProvider>` — outermost wrapper in `App.razor`; sets the static theme
2. `<CascadingAuthenticationState>` — authentication state cascade inside `<BbProvider>`
3. Theme initializer component — loads dynamic overrides once the user is known

**Rule**: `<BbProvider>` must always be the outermost wrapper. Placing it inside `<CascadingAuthenticationState>` or another component will break theme initialization for unauthenticated routes.

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

### Dialogs, popovers, or tooltips never appear
- Confirm `<BbPortalHost />` exists in the root layout.
- Confirm the page is interactive when the component requires JS interop.

### Toasts or programmatic dialogs do nothing
- Confirm `AddBlazorBlueprintComponents()` is registered.
- Confirm `<BbToastProvider />` and/or `<BbDialogProvider />` are present in the layout.

### Dark mode does not apply
- Confirm the `.dark` class is toggled on `<html>`.
- Confirm your dark theme variables exist in the custom theme CSS.
