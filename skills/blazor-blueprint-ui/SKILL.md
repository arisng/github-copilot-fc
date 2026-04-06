---
name: blazor-blueprint-ui
description: Build and customize .NET 8+ Blazor UIs with BlazorBlueprint. Use when choosing between BlazorBlueprint.Components and BlazorBlueprint.Primitives, wiring setup and providers, using ToastService/DialogService/localization, selecting icon packs, applying shadcn-ui-style theming, or copying and adapting BlazorBlueprint blueprints.
metadata: 
    version: 0.2.0
    author: arisng
---

# BlazorBlueprint UI

Build modern Blazor web applications using the current BlazorBlueprint component library.

**Repository:** https://github.com/blazorblueprintui/ui
**Documentation:** https://blazorblueprintui.com
**Original Source:** https://blazorblueprintui.com/llms.txt
**Full Bundle:** https://blazorblueprintui.com/llms/llms-full.txt

Examples in the refreshed references use the official upstream `Bb*` naming.

## Package Overview

Core packages:

- **BlazorBlueprint.Components** - Styled component library; includes primitives
- **BlazorBlueprint.Primitives** - Headless accessibility and behavior layer
- **BlazorBlueprint.Icons.Lucide** - Lucide icon pack
- **BlazorBlueprint.Icons.Heroicons** - Heroicons pack
- **BlazorBlueprint.Icons.Feather** - Feather icon pack

## Quick Navigation

### Setup & Installation
Read [references/setup.md](references/setup.md) for:
- NuGet installation and service registration
- CSS, imports, and provider setup
- `BbPortalHost`, `BbToastProvider`, and `BbDialogProvider`
- Theme variables and dark mode
- Verification and troubleshooting

### Services & Localization
Read [references/services.md](references/services.md) for:
- `AddBlazorBlueprintComponents()` vs `AddBlazorBlueprintPrimitives()`
- `ToastService` and `DialogService`
- provider requirements and programmatic dialog usage

Read [references/localization.md](references/localization.md) for:
- `IBbLocalizer` and startup string overrides
- `IStringLocalizer` integration patterns
- culture-sensitive component text and formatting

### Icons
Read [references/icons.md](references/icons.md) for icon component usage and styling guidance.

### Blueprints & Primitives
Read [references/blueprints.md](references/blueprints.md) for:
- category routing across auth, sidebar, apps, dashboards, forms, data, marketing, and ecommerce
- the upstream blueprint catalog and per-category files
- copy/adapt workflow for production-shaped screens

Read [references/primitives.md](references/primitives.md) for:
- when to stay on `BlazorBlueprint.Components`
- when to switch to `BlazorBlueprint.Primitives`
- headless behavior and custom design-system guidance

### Common Patterns
Read [references/patterns.md](references/patterns.md) for:
- controlled vs uncontrolled state
- `EditForm` + `BbField` conventions
- root provider patterns
- dashboard / app shell defaults
- blueprint-first acceleration

## Component Categories

### Form Components
Read [references/components-forms.md](references/components-forms.md) for:
- text, typed, and structured inputs
- selection controls and searchable selection
- date/time and OTP flows
- uploads, editors, and advanced inputs
- form sections, wizards, and dynamic forms

### Layout & Navigation Components
Read [references/components-layout.md](references/components-layout.md) for:
- sidebars, responsive nav, navigation menus, and breadcrumbs
- cards, tabs, accordions, and collapsible content
- resizable work areas, scroll areas, separators, and aspect-ratio containers
- routing guidance for shells vs display/data surfaces

### Overlay Components
Read [references/components-overlays.md](references/components-overlays.md) for:
- dialogs, alert dialogs, sheets, drawers, and popovers
- menus, tooltips, hover cards, and command surfaces
- `DialogService` and `ToastService` usage
- provider and portal requirements

### Display & Data Components
Read [references/components-display-data.md](references/components-display-data.md) for:
- alerts, badges, avatars, shortcuts, loading states, and empty states
- items, timelines, typography, and carousel-style presentation
- `BbDataTable`, `BbDataGrid`, and `BbDataView` routing
- dashboard/data-screen guidance

### Chart Components
Read [references/components-charts.md](references/components-charts.md) for:
- the current Apache ECharts-based chart stack
- `BbChart` composite charts and `ChartConfig`
- dedicated bar, line, area, pie, radial bar, gauge, radar, and scatter charts
- `BbChartContainer` and chart theming

## Key Architecture Patterns

### Controlled vs uncontrolled state

**Uncontrolled:**
```razor
<BbTabs DefaultValue="overview">...</BbTabs>
```

**Controlled:**
```razor
<BbTabs @bind-Value="currentTab">...</BbTabs>
```

### Composition pattern

```razor
<BbCard>
    <BbCardHeader><BbCardTitle>Title</BbCardTitle></BbCardHeader>
    <BbCardContent>Content</BbCardContent>
    <BbCardFooter>Actions</BbCardFooter>
</BbCard>
```

### AsChild pattern

```razor
<BbDialog>
    <BbDialogTrigger AsChild>
        <BbButton Variant="ButtonVariant.Destructive">Delete</BbButton>
    </BbDialogTrigger>
    <BbDialogContent>...</BbDialogContent>
</BbDialog>
```

### Portal and provider pattern

Overlay components render through `BbPortalHost`. App-wide toasts and service-driven dialogs also need `BbToastProvider` and `BbDialogProvider` in the root layout.

## Known Pitfalls

These are hard-won constraints — check them before generating any BB component code:

1. **No unmatched attribute capture** — BB components do not accept arbitrary HTML attributes (`@onclick`, `style`, `class`, etc.) and will throw at runtime. Wrap with a native element instead. See [patterns.md § No unmatched attribute capture](references/patterns.md).

2. **Tailwind subset only** — BB ships only the utilities its own components use; writing other Tailwind classes silently has no effect. Add missing utilities as custom CSS. See [setup.md § Tailwind subset limitation](references/setup.md).

3. **Lucide icon names change** — Several names have been renamed upstream (e.g. `check-circle` → `circle-check`, `home` → `house`). A broken icon renders ⚠️. Verify names at `https://blazorblueprintui.com/llms/icons/lucide.txt`. See [icons.md § Renamed icons](references/icons.md).

4. **Auth pages are SSR-only** — Login/signup blueprints use `[ExcludeFromInteractiveRouting]`. Use HTML form POST + `[SupplyParameterFromForm]`; do not add `@rendermode InteractiveServer`. See [blueprints.md § Auth pages and SSR](references/blueprints.md).

5. **`BbProvider` must be the outermost wrapper** — Bootstrap order in `App.razor` matters: `<BbProvider>` wraps everything. See [setup.md § App.razor bootstrap order](references/setup.md).

## Workflow

1. **Read setup.md** for installation and providers.
2. **Choose components vs primitives** before building custom shells or behavior-heavy surfaces.
3. **Pick a category**: forms, layout/navigation, overlays, display/data, or charts.
4. **Load patterns.md** when composing multiple surfaces together.
5. **Load blueprints.md** when you need a production-shaped screen quickly.
6. **Style through theme variables** and validate dark mode.

## When to Load References

- **setup.md:** first-time setup, providers, theming, dark mode, icons import questions
- **services.md:** DI registration differences, `ToastService`, `DialogService`, provider requirements
- **localization.md:** label overrides, `IBbLocalizer` customization, culture-sensitive component text
- **blueprints.md:** rapid auth, sidebar, dashboard, data, marketing, or ecommerce screen scaffolding
- **primitives.md:** headless composition, custom design systems, or behavior-only reuse
- **components-forms.md:** editing flows, validation, selection, wizards, schema-driven forms
- **components-layout.md:** shells, responsive navigation, cards, tabs, resizable work areas
- **components-overlays.md:** dialogs, menus, tooltips, command palettes, toasts
- **components-display-data.md:** alerts, status display, tables, grids, data views, empty/loading states
- **components-charts.md:** dashboards, KPI visuals, mixed/composite chart composition
- **patterns.md:** cross-component conventions and blueprint-first workflows

## Blueprints and Primitives

- **Blueprints** provide ready-to-copy compositions for auth, sidebar shells, dashboards, forms, data screens, marketing, and ecommerce. Read [references/blueprints.md](references/blueprints.md) for category routing and upstream blueprint entry points.
- **Primitives** are the headless layer for advanced users who want BlazorBlueprint behavior without the styled component surface. Read [references/primitives.md](references/primitives.md) when markup ownership matters more than the default component styling.
