# Primitives

Source: https://blazorblueprintui.com/llms/index.txt

## When to use primitives

Use `BlazorBlueprint.Primitives` when the task requires headless behavior with your own markup/classes, or when you are building a reusable design system on top of BlazorBlueprint rather than using the default styled components.

Stay on `BlazorBlueprint.Components` for normal app work unless the user explicitly needs custom styling control.

## What primitives provide

The primitives layer supplies accessibility, focus management, keyboard interaction, portal behavior, positioning, and compound-component state without shipping CSS.

The styled components layer is built on top of these primitives.

## Setup reminder

```bash
dotnet add package BlazorBlueprint.Primitives
```

```csharp
builder.Services.AddBlazorBlueprintPrimitives();
```

If the primitive is an overlay or floating surface, you still need `BbPortalHost` in the layout.

## Primitive groups to expect

The upstream index currently lists 28 primitive docs. Common groups include:
- Overlay/floating: dialog, sheet, popover, tooltip, hover-card, dropdown-menu, context-menu
- Selection/input state: checkbox, radio-group, select, slider, switch, tabs, toggle
- Layout/data helpers: accordion, scroll-area, separator, table, tree-view, data-grid, sortable, filtering

## Practical rule of thumb

Choose primitives when you need one or more of these:
- Full control over HTML structure or Tailwind classes
- A custom design system that should not inherit the default BlazorBlueprint styling
- Behavior-level reuse without the opinionated component shell

If the task is mostly "make it look like shadcn/ui in Blazor", use the Components package instead.

## Where to get exact APIs

Use the upstream primitive docs for exact parameters and composition patterns:
- `https://blazorblueprintui.com/llms/index.txt`
- `https://blazorblueprintui.com/llms/primitives/`

Open the specific primitive doc you need rather than loading the whole set.
