# BlazorBlueprint Icon Libraries

BlazorBlueprint provides Lucide icon library with 1,640+ stroke-based SVG icons as Blazor components.

**Source:** https://blazorblueprintui.com/llms/icons.txt

---

## Installation

```bash
dotnet add package BlazorBlueprint.Icons
```

## Setup

Add the namespace to `_Imports.razor`:

```razor
@using BlazorBlueprint.Icons
```

---

## Lucide Icons

### Basic Usage

```razor
<LucideIcon Name="camera" />
<LucideIcon Name="heart" Size="32" Color="red" />
<LucideIcon Name="check" Class="text-green-500" />
```

### API Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Name` | `string` | **Required** | Icon name in kebab-case (e.g., "camera", "chevron-down") |
| `Size` | `int` | `24` | Icon size in pixels |
| `Color` | `string` | `"currentColor"` | CSS color value |
| `StrokeWidth` | `double` | `2.0` | SVG stroke width |
| `Class` | `string` | `null` | Additional CSS classes |
| `AriaLabel` | `string` | `null` | Accessibility label |

### Examples

```razor
@* Basic icon *@
<LucideIcon Name="home" />

@* Customized icon *@
<LucideIcon
    Name="settings"
    Size="20"
    Color="#3B82F6"
    StrokeWidth="1.5"
    Class="rotate-90" />

@* In a button *@
<Button>
    <LucideIcon Name="plus" Size="16" />
    Add Item
</Button>

@* With loading state *@
@if (isLoading)
{
    <LucideIcon Name="loader-2" Size="16" Class="animate-spin" />
}
```

### Popular Lucide Icon Names

**Navigation:** `home`, `menu`, `x`, `chevron-down`, `chevron-up`, `arrow-left`, `arrow-right`  
**Actions:** `plus`, `minus`, `edit`, `trash`, `save`, `download`, `upload`, `search`  
**Status:** `check`, `check-circle`, `x-circle`, `alert-circle`, `alert-triangle`, `info`  
**User:** `user`, `user-plus`, `users`, `log-in`, `log-out`, `lock`, `unlock`  
**Media:** `image`, `file`, `folder`, `camera`, `video`, `music`

**Browse all:** https://lucide.dev/icons

---

## Common Use Cases

### Icons in Buttons

```razor
@using BlazorBlueprint.Components

<Button>
    <LucideIcon Name="plus" Size="16" />
    Add Item
</Button>

@* Icon-only button *@
<Button Size="icon" Variant="ghost">
    <LucideIcon Name="more-horizontal" Size="20" />
</Button>
```

### Icons in Navigation

```razor
<nav class="space-y-2">
    <a href="/" class="flex items-center space-x-2">
        <LucideIcon Name="home" Size="20" />
        <span>Dashboard</span>
    </a>
    <a href="/settings" class="flex items-center space-x-2">
        <LucideIcon Name="settings" Size="20" />
        <span>Settings</span>
    </a>
</nav>
```

### Icons in Dropdown Menus

```razor
<DropdownMenu>
    <DropdownMenuTrigger AsChild>
        <Button Variant="outline">
            Actions
            <LucideIcon Name="chevron-down" Size="16" />
        </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent>
        <DropdownMenuItem>
            <LucideIcon Name="edit" Size="16" />
            Edit
        </DropdownMenuItem>
        <DropdownMenuItem>
            <LucideIcon Name="trash-2" Size="16" />
            Delete
        </DropdownMenuItem>
    </DropdownMenuContent>
</DropdownMenu>
```

### Status Messages with Icons

```razor
@* Success *@
<div class="flex items-start space-x-3 p-4 bg-green-50 border border-green-200 rounded-lg">
    <LucideIcon Name="check-circle" Size="20" Class="text-green-600" />
    <div>
        <h4 class="font-medium text-green-900">Success</h4>
        <p class="text-sm text-green-700">Your changes have been saved.</p>
    </div>
</div>

@* Error *@
<div class="flex items-start space-x-3 p-4 bg-red-50 border border-red-200 rounded-lg">
    <LucideIcon Name="x-circle" Size="20" Class="text-red-600" />
    <div>
        <h4 class="font-medium text-red-900">Error</h4>
        <p class="text-sm text-red-700">Something went wrong.</p>
    </div>
</div>

@* Warning *@
<div class="flex items-start space-x-3 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
    <LucideIcon Name="alert-triangle" Size="20" Class="text-yellow-600" />
    <div>
        <h4 class="font-medium text-yellow-900">Warning</h4>
        <p class="text-sm text-yellow-700">This action cannot be undone.</p>
    </div>
</div>
```

### Loading States

```razor
<Button Disabled="@isLoading">
    @if (isLoading)
    {
        <LucideIcon Name="loader-2" Size="16" Class="animate-spin" />
    }
    else
    {
        <LucideIcon Name="save" Size="16" />
    }
    Save
</Button>

@code {
    private bool isLoading = false;
}
```

### Icons in Badges

```razor
<Badge>
    <LucideIcon Name="check" Size="14" />
    Verified
</Badge>

<Badge Variant="destructive">
    <LucideIcon Name="x" Size="14" />
    Failed
</Badge>

<Badge Variant="outline">
    <LucideIcon Name="clock" Size="14" />
    Pending
</Badge>
```

---

## Styling Icons

### Using Tailwind CSS Classes

```razor
@* Color *@
<LucideIcon Name="heart" Class="text-red-500" />

@* Size (alternative to Size parameter) *@
<LucideIcon Name="home" Class="w-4 h-4" />
<LucideIcon Name="home" Class="w-6 h-6" />
<LucideIcon Name="home" Class="w-8 h-8" />

@* Rotation *@
<LucideIcon Name="arrow-right" Class="rotate-45" />

@* Animation *@
<LucideIcon Name="loader-2" Class="animate-spin" />

@* Hover effects *@
<LucideIcon Name="heart" Class="hover:text-red-500 transition-colors" />
```

### Using CSS Variables (Theming)

```razor
<LucideIcon Name="sun" Color="var(--primary)" />
<LucideIcon Name="moon" Color="var(--foreground)" />
<LucideIcon Name="star" Color="var(--accent)" />
```

---

## Accessibility

### Adding ARIA Labels

For icons that convey meaning (not just decoration), add `AriaLabel`:

```razor
@* Icon-only button - needs aria-label *@
<Button Size="icon">
    <LucideIcon Name="x" Size="20" AriaLabel="Close" />
</Button>

@* Icon with text - no aria-label needed *@
<Button>
    <LucideIcon Name="save" Size="16" />
    Save
</Button>
```

### Decorative vs. Meaningful Icons

```razor
@* Decorative (icon + text) - no aria-label needed *@
<Button>
    <LucideIcon Name="download" Size="16" />
    Download
</Button>

@* Meaningful (icon only) - aria-label required *@
<Button Size="icon">
    <LucideIcon Name="download" Size="20" AriaLabel="Download file" />
</Button>
```

---

## Icon Name Format

All icon libraries use **kebab-case** for icon names:

```razor
@* Correct *@
<LucideIcon Name="chevron-down" />
<LucideIcon Name="user-plus" />
<LucideIcon Name="alert-triangle" />

@* Wrong *@
<LucideIcon Name="ChevronDown" />  @* PascalCase - won't work *@
<LucideIcon Name="userPlus" />      @* camelCase - won't work *@
<LucideIcon Name="alertTriangle" /> @* camelCase - won't work *@
```

---

## Finding Icon Names

### Lucide Icons
https://lucide.dev/icons  
Browse all 1,640 icons, search by keyword, copy names

---

## Troubleshooting

### Icon doesn't appear

**Cause:** Icon name is incorrect or not in kebab-case

**Solution:**
- Check icon name on official website (lucide.dev)
- Ensure name is kebab-case: `"chevron-down"` not `"ChevronDown"`
- Verify the correct icon package is installed
- Verify namespace is imported in `_Imports.razor`

### Icon color doesn't change

**Cause:** Using both `Color` parameter and CSS color classes

**Solution:**
```razor
@* Choose ONE approach *@

@* Option 1: Use Color parameter *@
<LucideIcon Name="heart" Color="red" />

@* Option 2: Use CSS class (preferred for theming) *@
<LucideIcon Name="heart" Class="text-red-500" />
```
