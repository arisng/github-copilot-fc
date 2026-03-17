# Icons

Source: https://blazorblueprintui.com/llms/icons.txt

## Pick the icon package intentionally

- `BlazorBlueprint.Icons.Lucide` - 1,665 stroke icons; best default for most app UI.
- `BlazorBlueprint.Icons.Heroicons` - 1,288 icons across Outline, Solid, Mini, and Micro variants.
- `BlazorBlueprint.Icons.Feather` - 286 lightweight stroke icons.

Install only the package(s) you need:

```bash
dotnet add package BlazorBlueprint.Icons.Lucide
dotnet add package BlazorBlueprint.Icons.Heroicons
dotnet add package BlazorBlueprint.Icons.Feather
```

No service registration is required.

## Import the right namespace

```razor
@using BlazorBlueprint.Icons.Lucide.Components
@using BlazorBlueprint.Icons.Lucide.Data
```

Swap `Lucide` for `Heroicons` or `Feather` as needed.

## Typical usage

```razor
<LucideIcon Name="search" Class="h-4 w-4" />
<HeroIcon Name="home" Variant="HeroIconVariant.Solid" />
<FeatherIcon Name="camera" Size="20" />
```

Use Tailwind classes for sizing/alignment when icons sit inside BlazorBlueprint components.

## Accessibility rule

For icon-only actions, provide an accessible label:

```razor
<BbButton Variant="ButtonVariant.Ghost" Size="ButtonSize.Icon">
    <LucideIcon Name="settings" AriaLabel="Settings" />
</BbButton>
```

If visible text is already present next to the icon, the extra label is usually unnecessary.

## Name format and lookup

Icon names are kebab-case and case-insensitive:
- `arrow-right`
- `magnifying-glass`
- `check-circle`

Use the upstream catalog files when you need exact names:
- `https://blazorblueprintui.com/llms/icons/lucide.txt`
- `https://blazorblueprintui.com/llms/icons/heroicons.txt`
- `https://blazorblueprintui.com/llms/icons/feather.txt`

## Programmatic lookup

Each package also ships a data helper class (`LucideIconData`, `HeroIconData`, `FeatherIconData`) for existence checks and iteration.
