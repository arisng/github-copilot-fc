# Layout & Navigation Components Reference

Use this file for shells, page structure, and navigation. Display-heavy and data-heavy components now live in `components-display-data.md`.

**Sources:** https://blazorblueprintui.com/llms/components/sidebar.txt and https://blazorblueprintui.com/llms/components/

## TOC
- [Choose the right layout tool](#choose-the-right-layout-tool)
- [App shell and navigation](#app-shell-and-navigation)
- [Page structure and containers](#page-structure-and-containers)
- [High-value example](#high-value-example)
- [Routing notes](#routing-notes)

## Choose the right layout tool

| Need | Prefer | Notes |
| --- | --- | --- |
| Full application shell | `BbSidebarProvider`, `BbSidebar`, `BbSidebarInset` | Best default for dashboards and authenticated apps. |
| Lightweight top navigation | `BbNavigationMenu`, `BbResponsiveNav` | Use `BbResponsiveNav` when mobile disclosure is central. |
| In-page hierarchy / location | `BbBreadcrumb` | Pair with headers and page actions. |
| Section switching | `BbTabs`, `BbAccordion`, `BbCollapsible` | `BbTabs` for peer views, `BbAccordion` for expandable content sets. |
| Card-like grouping | `BbCard` | Default building block for pages, forms, and dashboard panels. |
| Resizable work areas | `BbResizablePanelGroup` | Great for IDE, mail, and analytics layouts. |
| Managed scrolling | `BbScrollArea` | Use inside fixed-height panels or drawers. |
| Media aspect lock | `BbAspectRatio` | Keeps images/video placeholders stable. |
| Visual separation | `BbSeparator` | Cheap structure signal for headers, toolbars, and menus. |
| Paging long datasets | `BbPagination` | Usually paired with `BbDataTable`, `BbDataView`, or server-driven pages. |

## App shell and navigation

`BbSidebar` is the most important current navigation surface:
- Desktop sidebar + mobile sheet behavior are built into the same system.
- `BbSidebarProvider` manages state, keyboard shortcut support, and cookie persistence.
- Visual variants include sidebar, floating, and inset styles.
- Collapsed icon mode, tooltips, badges, and submenu structures are first-class.

`BbNavigationMenu` is the right fit for top-site navigation with dropdown content.

`BbResponsiveNav` is the simpler route when you mainly need a mobile menu trigger and content region instead of the full sidebar model.

## Page structure and containers

Common structure patterns:
- `BbCard` for most bounded content regions
- `BbTabs` for peer-level panels such as settings pages
- `BbAccordion` for FAQ or grouped settings content
- `BbCollapsible` for optional inline expansion
- `BbResizablePanelGroup` for multi-pane workspaces
- `BbScrollArea` for fixed-height panel interiors

Keep layout responsibilities here; do not route tables, alerts, timelines, or empty states into this file.

## High-value example

```razor
<BbSidebarProvider>
    <BbSidebar>
        <BbSidebarHeader>
            <BbSidebarHeaderContent>
                <div class="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                    A
                </div>
                <BbSidebarHeaderInfo>
                    <span class="truncate font-semibold">Acme</span>
                    <span class="truncate text-xs text-muted-foreground">Workspace</span>
                </BbSidebarHeaderInfo>
            </BbSidebarHeaderContent>
        </BbSidebarHeader>

        <BbSidebarContent>
            <BbSidebarGroup>
                <BbSidebarGroupLabel>Platform</BbSidebarGroupLabel>
                <BbSidebarGroupContent>
                    <BbSidebarMenu>
                        <BbSidebarMenuItem>
                            <BbSidebarMenuButton Href="/dashboard" Tooltip="Dashboard">
                                <LucideIcon Name="home" />
                                <span>Dashboard</span>
                            </BbSidebarMenuButton>
                        </BbSidebarMenuItem>
                    </BbSidebarMenu>
                </BbSidebarGroupContent>
            </BbSidebarGroup>
        </BbSidebarContent>

        <BbSidebarRail />
    </BbSidebar>

    <BbSidebarInset>
        <header class="flex h-16 items-center gap-2 border-b px-4">
            <BbSidebarTrigger />
            <BbBreadcrumb>
                <BbBreadcrumbList>
                    <BbBreadcrumbItem>
                        <BbBreadcrumbPage>Dashboard</BbBreadcrumbPage>
                    </BbBreadcrumbItem>
                </BbBreadcrumbList>
            </BbBreadcrumb>
        </header>

        <main class="p-6">
            <BbCard>
                <BbCardHeader>
                    <BbCardTitle>Overview</BbCardTitle>
                </BbCardHeader>
                <BbCardContent>...</BbCardContent>
            </BbCard>
        </main>
    </BbSidebarInset>
</BbSidebarProvider>
```

## Routing notes

- For charts, load `components-charts.md`.
- For alerts, badges, timelines, tables, and empty states, load `components-display-data.md`.
- For dialogs, menus, and tooltips, load `components-overlays.md`.
- For input-heavy pages, pair this file with `components-forms.md`.
