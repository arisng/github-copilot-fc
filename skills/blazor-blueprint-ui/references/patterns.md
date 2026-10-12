# BlazorBlueprint Common Patterns

Load this file after the relevant component reference when you need conventions, composition guidance, or a good default implementation pattern.

**Sources:**
- https://blazorblueprintui.com/llms/patterns.txt
- https://blazorblueprintui.com/llms/services.txt
- https://blazorblueprintui.com/llms/blueprints.txt

## TOC
- [Naming and composition conventions](#naming-and-composition-conventions)
- [Controlled vs uncontrolled state](#controlled-vs-uncontrolled-state)
- [EditForm and validation pattern](#editform-and-validation-pattern)
- [AsChild pattern and defaults](#aschild-pattern-and-defaults)
- [Class parameter and the bb: prefix](#class-parameter-and-the-bb-prefix)
- [Overlay behavior: Escape and initial focus](#overlay-behavior-escape-and-initial-focus)
- [Root layout providers](#root-layout-providers)
- [Dashboard and app shell pattern](#dashboard-and-app-shell-pattern)
- [Loading empty and error states](#loading-empty-and-error-states)
- [Blueprint-first acceleration](#blueprint-first-acceleration)

## Unmatched attribute capture

As of v4, **most** BB components declare `[Parameter(CaptureUnmatchedValues = true)]` and pass arbitrary HTML attributes through to the root element:

```razor
✅ This now works on most components:
<BbButton id="my-btn" data-testid="submit" aria-label="Submit form">Submit</BbButton>
<BbCard @onclick="OpenDetail" class="cursor-pointer">...</BbCard>
<BbBadge style="margin-top: 4px">Active</BbBadge>
```

**However, not all components support this.** If a component does not declare `CaptureUnmatchedValues`, passing unknown attributes will throw at runtime:

```
System.InvalidOperationException: Object of type 'BlazorBlueprint.Components.BbCard'
does not have a property matching the name 'onclick'.
```

**Check**: When in doubt, search for `CaptureUnmatchedValues` in the component's source at [github.com/blazorblueprintui/ui](https://github.com/blazorblueprintui/ui) or test the component interactively.

**Fallback**: Wrap in a native HTML element and put the attribute on the wrapper:

```razor
// For components that lack CaptureUnmatchedValues:
<div @onclick="OpenDetail" class="cursor-pointer">
    <BbCard>...</BbCard>
</div>
```

## Naming and composition conventions

Current upstream docs use official `Bb*` component names.

Compound components rely heavily on cascading context, so prefer the documented parent/child composition instead of flattening everything into one tag. Examples:
- `BbTabs` + `BbTabsList` + `BbTabsTrigger` + `BbTabsContent`
- `BbDialog` + `BbDialogTrigger` + `BbDialogContent`
- `BbSelect` + `BbSelectTrigger` + `BbSelectContent`
- `BbDataTable` + `BbDataTableColumn`

## Controlled vs uncontrolled state

Many components support both `Value` / `Open` and `DefaultValue` / `DefaultOpen` patterns.

Use controlled state when the page logic needs to own it:

```razor
<BbDialog @bind-Open="isOpen">
    ...
</BbDialog>
```

Use uncontrolled state when the component can manage itself:

```razor
<BbTabs DefaultValue="overview">
    ...
</BbTabs>
```

`OnValueChange` is notification-only; it does not mean you own the state.

## EditForm and validation pattern

Prefer `EditForm` + `BbField` + `ValidationMessage` for hand-authored forms:

```razor
<EditForm Model="@model" OnValidSubmit="SaveAsync">
    <DataAnnotationsValidator />

    <BbField>
        <BbFieldLabel>Email</BbFieldLabel>
        <BbFieldContent>
            <BbInput @bind-Value="model.Email"
                     ValueExpression="@(() => model.Email)" />
        </BbFieldContent>
        <BbFieldError>
            <ValidationMessage For="@(() => model.Email)" />
        </BbFieldError>
    </BbField>

    <BbButton type="submit">Save</BbButton>
</EditForm>
```

Good default rules:
- Use `ValueExpression` when the control participates in form validation.
- Do **not** set `ValueExpression` explicitly next to `@bind-Value` — the shorthand already generates it and Razor rejects a parameter supplied twice. Set it yourself only when binding with separate `Value` / `ValueChanged` attributes.
- Text inputs (`BbInput`, `BbTextarea`, `BbInputGroup*`) implement `Value`/`ValueChanged` directly and do **not** inherit from `InputBase<T>`.
- Prefer `BbInputField<TValue>` only when typed parsing or formatting is needed.
- Use `BbFormWizard` or `BbDynamicForm` only when the flow actually benefits from the abstraction.

## AsChild pattern and defaults

Trigger/close components either render their own element or hand their behavior to a child through `AsChild`. When `AsChild="true"` the trigger cascades a `TriggerContext` (callbacks, ARIA attributes, element reference) that context-consuming children such as `BbButton` use; plain markup, text and icons do not.

v4 defaults in the styled Components layer:

| Component | AsChild default | Element when `AsChild="false"` |
| --- | --- | --- |
| `BbDialogTrigger` / `BbDialogClose` / `BbSheetTrigger` / `BbSheetClose` | `true` | `<button>` |
| `BbPopoverTrigger` / `BbAlertDialogTrigger` / `BbAlertDialogAction` / `BbAlertDialogCancel` | `true` | `<button>` |
| `BbDropdownMenuTrigger` / `BbCollapsibleTrigger` | `true` | `<button>` |
| `BbHoverCardTrigger` | `true` | `<div>` with hover/focus handlers |
| `BbDrawerTrigger` / `BbDrawerClose` | `false` | `<button type="button">` |
| `BbTooltipTrigger` | `false` | `<span>` (display: contents) > `<span>` |

Every Primitives-layer trigger defaults `AsChild` to `false`.

Hard rules for v4 code:
- `BbTooltipTrigger` wrapping a `BbButton` (or another context consumer) needs `AsChild="true"`. A bare icon or text needs nothing.
- `BbDrawerTrigger` / `BbDrawerClose` wrapping a `BbButton` need `AsChild="true"` — otherwise a `<button>` nests inside a `<button>` (invalid HTML). A plain `<button>` child cannot read the trigger context, so it opens nothing; use `BbButton` instead. Plain content (text, icon, `<span>`) needs nothing and is keyboard-reachable.
- Triggers defaulting to `true` take a `BbButton` child as-is. For plain content set `AsChild="false"` so the trigger renders its own element.
- With `AsChild="true"`, triggers log a Development-only warning when no child read the context.

## Class parameter and the bb: prefix

All styled components accept `Class`, merged with the component's defaults through `ClassNames.cn` (clsx + tailwind-merge equivalent):

```razor
<BbPopoverContent Class="p-6">
@* renders class="... p-6 ...": the library's bb:p-4 is removed *@
```

- Write `Class` values **unprefixed**; the merge strips the `bb:` prefix before resolving conflicts.
- `group` / `peer` markers are emitted in both forms, so your `group-*` / `peer-*` variants apply to library markup.
- Safelisted prefixed utilities for consumers: `bb:shimmer`, `bb:scroll-fade-x`.
- Never target library internals by utility class in CSS/JS/tests (`.flex-col`, `.hidden`) — v4 emits them as `.bb\:flex-col` etc. Prefer `data-slot`, `data-state` and other data attributes.

## Overlay behavior: Escape and initial focus

- Escape dismisses only the topmost overlay, one layer per press. Overlays whose content holds focus (`BbSelect`, `BbDropdownMenu`, `BbContextMenu`, `BbMenubar`) handle Escape themselves and stop propagation.
- `BbDialogContent`, `BbSheetContent` and `BbDrawerContent` accept `InitialFocus` (`FocusTrapInitialFocus.FirstFocusable` / `.Container` / `.None`) and `InitialFocusElement`. Resolution order: `InitialFocusElement`, then `[data-autofocus]`, then the `InitialFocus` mode, then the first tabbable descendant.

## Root layout providers

The common root pattern is:

```razor
<BbPortalHost />
<BbToastProvider />
<BbDialogProvider />
```

Why:
- overlays need the portal host
- app-wide notifications need the toast provider
- service-driven confirm / prompt / custom dialogs need the dialog provider

## Dashboard and app shell pattern

A strong default for authenticated apps is:
- `BbSidebarProvider` + `BbSidebar` + `BbSidebarInset`
- `BbBreadcrumb` in the header
- `BbCard` for page regions
- `BbChartContainer` or `BbCard` for charts
- `BbDataTable` or `BbDataView` for the main data surface

This pattern aligns with the current dashboard, apps, sidebar, and data blueprints.

## Loading empty and error states

Prefer this sequence for async content:
- `BbSkeleton` while loading
- `BbEmpty` when the result is empty
- `BbAlert` when the operation failed or requires immediate attention
- toast via `ToastService` for transient success/failure feedback

This is usually better than overloading dialogs for status communication.

## Blueprint-first acceleration

The current docs include 60 blueprints across auth, sidebar, apps, dashboard, forms, navigation, data, marketing, and ecommerce.

Blueprint guidance:
- Start from a blueprint when you need a production-shaped composition quickly.
- Prefer blueprint code for app shells, auth pages, dashboard cards, or composite data screens.
- Then simplify the copied result to the smallest version your app actually needs.

High-value blueprint categories for AI work:
- `blueprints/sidebar.txt` for application shells
- `blueprints/apps.txt` for rich end-to-end compositions
- `blueprints/dashboard.txt` and `blueprints/data.txt` for analytics and CRUD pages
- `blueprints/forms.txt` for onboarding, profile, and checkout flows
