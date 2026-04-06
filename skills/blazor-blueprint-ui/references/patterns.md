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
- [Root layout providers](#root-layout-providers)
- [Dashboard and app shell pattern](#dashboard-and-app-shell-pattern)
- [Loading empty and error states](#loading-empty-and-error-states)
- [Blueprint-first acceleration](#blueprint-first-acceleration)

## No unmatched attribute capture

**Critical**: BB components do **not** declare `[Parameter(CaptureUnmatchedValues = true)]`. Passing arbitrary HTML attributes — `@onclick`, `style=`, `class=`, `data-*`, etc. — directly on a BB component throws at runtime:

```
System.InvalidOperationException: Object of type 'BlazorBlueprint.Components.BbCard'
does not have a property matching the name 'onclick'.
```

**Affected components**: `BbCard`, `BbBadge`, `LucideIcon`, and most other BB components.

**Fix**: Wrap in a native HTML element and put the attribute on the wrapper:

```razor
❌ Don't do this:
<BbCard @onclick="OpenDetail">...</BbCard>
<BbBadge style="margin-top: 4px">Active</BbBadge>

✅ Do this instead:
<div @onclick="OpenDetail" class="cursor-pointer">
    <BbCard>...</BbCard>
</div>
<span style="margin-top: 4px">
    <BbBadge>Active</BbBadge>
</span>
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
- Prefer `BbInputField<TValue>` only when typed parsing or formatting is needed.
- Use `BbFormWizard` or `BbDynamicForm` only when the flow actually benefits from the abstraction.

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
