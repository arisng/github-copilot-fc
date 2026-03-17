# Display & Data Components Reference

Use this file for status display, loading/empty states, presentation helpers, and data-heavy surfaces. This file exists to keep display/data concerns separate from layout, forms, and overlays.

**Sources:**
- https://blazorblueprintui.com/llms/components/alert.txt
- https://blazorblueprintui.com/llms/components/empty.txt
- https://blazorblueprintui.com/llms/components/timeline.txt
- https://blazorblueprintui.com/llms/components/data-table.txt
- https://blazorblueprintui.com/llms/components/data-view.txt
- https://blazorblueprintui.com/llms/components/data-grid.txt
- https://blazorblueprintui.com/llms/blueprints.txt

## TOC
- [Choose the right display surface](#choose-the-right-display-surface)
- [Status and feedback components](#status-and-feedback-components)
- [DataTable vs DataGrid vs DataView](#datatable-vs-datagrid-vs-dataview)
- [Reference examples](#reference-examples)
- [Routing notes](#routing-notes)

## Choose the right display surface

| Need | Prefer | Notes |
| --- | --- | --- |
| Inline status / category | `BbBadge`, `BbKbd` | Cheap metadata and shortcut display. |
| Important message or inline callout | `BbAlert` | Supports variants, dismiss, countdown, and action slot. |
| Identity / profile chip | `BbAvatar` | Usually paired with `BbBadge` or `BbItem`. |
| Loading / pending state | `BbSkeleton`, `BbSpinner`, `BbProgress` | Pick based on whether the final shape is known. |
| Empty or no-results state | `BbEmpty` | Preferred fallback for tables, lists, and dashboards. |
| Rich row layout | `BbItem` | Great for inboxes, settings lists, and mobile-friendly rows. |
| Chronological flow | `BbTimeline` | Use for activity feeds, deployments, workflows, and roadmaps. |
| Basic pageable data table | `BbDataTable<TData>` | Sorting, filtering, pagination, selection, and templates with low ceremony. |
| Enterprise grid | `BbDataGrid<TData>` | Grouping, hierarchy, virtualization, pinning, resize/reorder, server providers. |
| List/grid catalog | `BbDataView<TItem>` | Toolbar search, sort, pagination, and list/grid template switching. |
| Rich text content presentation | `BbTypography*` components | Keep docs, marketing, and long-form pages visually consistent. |
| Slide or media presentation | `BbCarousel` | Display concern, not layout shell. |

## Status and feedback components

High-value notes:
- `BbAlert` now supports semantic variants, accent borders, dismiss buttons, auto-dismiss, countdown bars, and action slots.
- `BbEmpty` is the preferred default fallback for “no rows”, “no search results”, and “no content yet”.
- `BbTimeline` supports status-based styling, alignment modes, connector styles, and optional collapsible detail content.

Pair display components intentionally:
- `BbSkeleton` while loading
- `BbEmpty` when data is absent
- `BbAlert` when an operation failed or needs attention

## DataTable vs DataGrid vs DataView

| Component | Best for | Key strengths |
| --- | --- | --- |
| `BbDataTable<TData>` | CRUD tables and common admin pages | Declarative columns, global search, pagination, row selection, simple preprocessing hooks |
| `BbDataGrid<TData>` | Enterprise or analyst workflows | Multi-column sort, per-column filters, grouping, hierarchy, virtualization, state persistence, pinning, row context menu |
| `BbDataView<TItem>` | Catalogs, card grids, searchable list views | List/grid templates, toolbar search, sorting, pagination, infinite scroll |

Guidance:
- Start with `BbDataTable` unless you already know you need grid-grade features.
- Use `BbDataGrid` when you need server-side providers, hierarchy, grouping, or heavy operator-driven filtering.
- Use `BbDataView` when the visual shape is not tabular.

## Reference examples

### Data table

```razor
<BbDataTable TData="Person" Data="@people" SelectionMode="DataTableSelectionMode.Multiple">
    <Columns>
        <BbDataTableColumn TData="Person" TValue="string"
                           Header="Name"
                           Property="@(p => p.Name)"
                           Sortable="true"
                           Filterable="true" />
        <BbDataTableColumn TData="Person" TValue="string" Header="Status">
            <CellTemplate Context="person">
                <BbBadge>@person.Status</BbBadge>
            </CellTemplate>
        </BbDataTableColumn>
    </Columns>
</BbDataTable>
```

### Data view with list/grid routing

```razor
<BbDataView TItem="Product" Data="@products">
    <Fields>
        <BbDataViewColumn TItem="Product" TValue="string"
                          Header="Name"
                          Property="@(p => p.Name)"
                          Sortable
                          Filterable />
        <BbDataViewListTemplate TItem="Product" Context="product">
            <BbItem>
                <BbItemContent>
                    <BbItemTitle>@product.Name</BbItemTitle>
                    <BbItemDescription>@product.Price.ToString("C")</BbItemDescription>
                </BbItemContent>
            </BbItem>
        </BbDataViewListTemplate>
        <BbDataViewGridTemplate TItem="Product" Context="product">
            <BbCard>
                <BbCardContent class="p-4">@product.Name</BbCardContent>
            </BbCard>
        </BbDataViewGridTemplate>
    </Fields>
</BbDataView>
```

### Empty state

```razor
<BbEmpty Title="No results found"
         Description="Try changing the search or filter criteria.">
    <Icon>
        <LucideIcon Name="search" />
    </Icon>
    <BbButton Variant="ButtonVariant.Outline">Clear filters</BbButton>
</BbEmpty>
```

## Routing notes

- Layout shells and navigation belong in `components-layout.md`.
- Floating menus, tooltips, dialogs, and toasts belong in `components-overlays.md`.
- Input and editing workflows belong in `components-forms.md`.
- Data dashboards that need charts should pair this file with `components-charts.md`.
