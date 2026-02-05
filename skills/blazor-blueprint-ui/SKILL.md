---
name: blazor-blueprint-ui
description: Comprehensive Blazor component library based on shadcn/ui design with 88 components (15 headless Primitives, 73 pre-styled Components), 1,640+ Lucide icons, and chart library. Use when building Blazor web applications that need UI components like forms (buttons, inputs, date pickers, tables), navigation (tabs, menus, sidebars), overlays (dialogs, sheets, tooltips, popovers), displays (avatars, badges, alerts, skeletons), charts (bar, line, area, pie, radar, radial), or when working with shadcn/ui-style Blazor components. Supports both controlled/uncontrolled state patterns, composition-based component structure, and dark mode.
metadata: 
  version: 1.0.0
  authors: arisng
  homepage: https://blazorblueprintui.com
---

# BlazorBlueprint UI

Build modern Blazor web applications using the BlazorBlueprint component library based on shadcn/ui design.

**Repository:** https://github.com/blazorblueprintui/ui  
**Documentation:** https://blazorblueprintui.com  
**Original Source:** https://blazorblueprintui.com/llms/index.txt

## Package Overview

Three packages available:

- **BlazorBlueprint.Components** - Pre-styled components with shadcn/ui design (Recommended)
- **BlazorBlueprint.Primitives** - Headless components for custom styling
- **BlazorBlueprint.Icons** - 1,640+ Lucide icons

## Quick Navigation

### Setup & Installation
Read [references/setup.md](references/setup.md) for:
- Package installation (NuGet)
- Quick start configuration (3 steps)
- Theming and customization (shadcn/ui compatible)
- Dark mode setup
- Hosting model differences
- Troubleshooting

### Icons
Read [references/icons.md](references/icons.md) for:
- LucideIcon component usage
- 1,640+ available icons
- Icon styling and theming
- Accessibility best practices
- Common use cases (buttons, navigation, menus, status messages)

### Common Patterns
Read [references/patterns.md](references/patterns.md) for:
- Form with validation
- Dialog with form
- Data table with sorting/pagination
- Sidebar navigation
- Command palette
- Settings page with tabs
- Confirmation dialogs
- AsChild pattern

## Component Categories

### Form Components (26)
Read [references/components-forms.md](references/components-forms.md) for comprehensive details on:

**Basic Inputs:** Button, Input, Textarea, Label, Field, Button Group  
**Selection:** Checkbox, Radio Group, Switch, Select, MultiSelect, Native Select  
**Advanced Inputs:** Masked Input, Numeric Input, Currency Input, Input OTP, Color Picker, File Upload, Rating, Rich Text Editor  
**Date/Time:** Calendar, Date Picker, Date Range Picker, Time Picker  
**Sliders:** Slider, Range Slider  
**Other:** Toggle, Input Group

### Layout & Navigation Components (19)
Read [references/components-layout.md](references/components-layout.md) for comprehensive details on:

**Navigation:** Navigation Menu, Sidebar, Responsive Nav, Breadcrumb, Pagination  
**Layout:** Card, Accordion, Tabs, Collapsible, Separator, Scroll Area, Aspect Ratio, Resizable  
**Display:** Carousel, Item, Toggle Group, Typography  
**Form Layout:** Field

### Overlay Components (12)
Read [references/components-overlays.md](references/components-overlays.md) for comprehensive details on:

**Modals:** Dialog, Alert Dialog, Sheet, Drawer  
**Floating:** Popover, Tooltip, Hover Card  
**Menus:** Dropdown Menu, Context Menu, Menubar, Combobox, Command  
**Notifications:** Toast

**All overlay components require `<PortalHost />` in your layout.**

### Display Components (11)
Read [references/components-overlays.md](references/components-overlays.md) for comprehensive details on:

**Identity:** Avatar, Badge  
**Feedback:** Alert, Skeleton, Progress, Spinner, Empty  
**Data:** Data Table, Select  
**Other:** Kbd

### Chart Components (6)
Read [references/components-charts.md](references/components-charts.md) for comprehensive details on:

BarChart, LineChart, AreaChart, PieChart, RadarChart, RadialChart

Built on Blazor-ApexCharts with dark mode support and theme integration.

## Key Architecture Patterns

### State Management

**Uncontrolled (default):**
```razor
<Tabs DefaultValue="tab1">...</Tabs>
```

**Controlled:**
```razor
<Tabs @bind-Value="currentTab">...</Tabs>
```

### Composition Pattern

```razor
<Card>
    <CardHeader><CardTitle>Title</CardTitle></CardHeader>
    <CardContent>Content</CardContent>
    <CardFooter>Actions</CardFooter>
</Card>
```

### AsChild Pattern

Allows trigger components to pass behavior to child elements:

```razor
<Dialog>
    <DialogTrigger AsChild>
        <Button Variant="destructive">Delete</Button>
    </DialogTrigger>
    <DialogContent>...</DialogContent>
</Dialog>
```

### Portal Pattern

Overlay components render via portals for proper z-index stacking. Requires `<PortalHost />` in layout.

## Workflow

1. **Read setup.md** - Install packages and configure your project
2. **Choose component category** - Forms, Layout, Overlays, Display, or Charts
3. **Read component reference** - Get details, examples, and best practices
4. **Implement with composition** - Use ChildContent and nested components
5. **Style with Tailwind** - Add custom classes via `Class` parameter
6. **Test dark mode** - Ensure `.dark` class toggles properly

## When to Load References

- **setup.md:** First time setup, theming issues, dark mode configuration
- **icons.md:** Using icons, icon styling, accessibility for icon-only buttons
- **patterns.md:** Multi-component workflows, complex forms, data tables, navigation patterns
- **components-forms.md:** Building forms, input validation, date/time selection, file uploads
- **components-layout.md:** Page layouts, navigation, cards, tabs, sidebars, responsive design
- **components-overlays.md:** Modals, dropdowns, tooltips, notifications, command palettes
- **components-charts.md:** Data visualization, dashboards, reports

## Primitives (Advanced Users)

15 headless primitive components available for full styling control. See original source URLs for primitive documentation:
https://blazorblueprintui.com/llms/primitives/

Most users should use pre-styled Components instead.
