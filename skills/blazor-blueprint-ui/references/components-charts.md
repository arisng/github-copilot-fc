# Chart Components Reference

Comprehensive charting library built on Blazor-ApexCharts with 6 chart types.

**Source:** https://blazorblueprintui.com/llms/components/chart.txt

---

## Overview

BlazorBlueprint Charts provide a comprehensive charting solution built on Blazor-ApexCharts with shadcn/ui design integration, dark mode support, and theme integration.

**Features:**
- 6 chart types (Bar, Line, Area, Pie, Radar, Radial)
- Multiple variants per chart type
- Dark mode compatible
- Responsive design
- Interactive tooltips
- Smooth animations
- Theme color integration

---

## Installation

Charts are included in the main BlazorBlueprint.Components package:

```bash
dotnet add package BlazorBlueprint.Components
```

---

## Chart Types

### BarChart

Vertical or horizontal bar charts with multiple variants.

**Variants:**
- `Default` - Standard vertical bars
- `Horizontal` - Horizontal bars
- `Stacked` - Stacked vertical bars
- `StackedHorizontal` - Stacked horizontal bars

```razor
<BarChart
    Categories="@categories"
    Series="@series"
    Variant="BarChartVariant.Default"
    Height="350" />

@code {
    private string[] categories = { "Jan", "Feb", "Mar", "Apr", "May", "Jun" };
    private List<ChartSeries> series = new()
    {
        new ChartSeries { Name = "Revenue", Data = new double[] { 23, 45, 34, 56, 76, 98 } },
        new ChartSeries { Name = "Expenses", Data = new double[] { 15, 25, 20, 35, 45, 60 } }
    };
}
```

### LineChart

Line charts with various line styles.

**Variants:**
- `Default` - Smooth curved lines
- `Straight` - Straight line segments
- `Stepped` - Stepped line style

```razor
<LineChart
    Categories="@categories"
    Series="@series"
    Variant="LineChartVariant.Default"
    Height="350" />

@code {
    private string[] categories = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    private List<ChartSeries> series = new()
    {
        new ChartSeries { Name = "Sales", Data = new double[] { 30, 40, 35, 50, 49, 60, 70 } }
    };
}
```

### AreaChart

Filled area charts.

**Variants:**
- `Default` - Filled area with smooth curve
- `Stacked` - Stacked filled areas

```razor
<AreaChart
    Categories="@categories"
    Series="@series"
    Variant="AreaChartVariant.Default"
    Height="350" />

@code {
    private string[] categories = { "Q1", "Q2", "Q3", "Q4" };
    private List<ChartSeries> series = new()
    {
        new ChartSeries { Name = "Product A", Data = new double[] { 44, 55, 57, 56 } },
        new ChartSeries { Name = "Product B", Data = new double[] { 76, 85, 101, 98 } }
    };
}
```

### PieChart

Circular pie or donut charts.

**Variants:**
- `Pie` - Standard pie chart
- `Donut` - Donut chart with center hole

```razor
<PieChart
    Labels="@labels"
    Data="@data"
    Variant="PieChartVariant.Donut"
    Height="350" />

@code {
    private string[] labels = { "Chrome", "Firefox", "Safari", "Edge", "Other" };
    private double[] data = { 55.2, 18.5, 15.3, 8.7, 2.3 };
}
```

### RadarChart

Spider/radar charts for multivariate data.

```razor
<RadarChart
    Categories="@categories"
    Series="@series"
    Height="350" />

@code {
    private string[] categories = { "Speed", "Reliability", "Comfort", "Safety", "Efficiency" };
    private List<ChartSeries> series = new()
    {
        new ChartSeries { Name = "Model A", Data = new double[] { 80, 90, 70, 85, 75 } },
        new ChartSeries { Name = "Model B", Data = new double[] { 75, 85, 90, 70, 80 } }
    };
}
```

### RadialChart

Circular progress/radial bar charts.

```razor
<RadialChart
    Labels="@labels"
    Data="@data"
    Height="350" />

@code {
    private string[] labels = { "Complete", "In Progress", "Pending" };
    private double[] data = { 76, 67, 61 };
}
```

---

## Common Parameters

All chart components share these parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Height` | `int` | `350` | Chart height in pixels |
| `Width` | `string` | `"100%"` | Chart width (CSS value) |
| `Categories` | `string[]` | - | X-axis categories (Bar, Line, Area, Radar) |
| `Series` | `List<ChartSeries>` | - | Data series for multi-series charts |
| `Labels` | `string[]` | - | Labels for Pie/Radial charts |
| `Data` | `double[]` | - | Data for single-series Pie/Radial charts |
| `Variant` | `enum` | - | Chart variant (varies by chart type) |
| `Colors` | `string[]` | - | Custom color palette (overrides theme) |
| `ShowLegend` | `bool` | `true` | Display legend |
| `ShowGrid` | `bool` | `true` | Display grid lines (Bar, Line, Area) |
| `Animations` | `bool` | `true` | Enable animations |

---

## ChartSeries Model

```csharp
public class ChartSeries
{
    public string Name { get; set; } = "";
    public double[] Data { get; set; } = Array.Empty<double>();
}
```

---

## Theming & Colors

Charts automatically use theme colors from CSS variables:

```css
:root {
    --chart-1: oklch(0.6 0.2 220); /* Blue */
    --chart-2: oklch(0.7 0.15 150); /* Green */
    --chart-3: oklch(0.65 0.2 50); /* Yellow */
    --chart-4: oklch(0.6 0.2 350); /* Red */
    --chart-5: oklch(0.65 0.15 280); /* Purple */
}
```

### Custom Colors

Override theme colors with `Colors` parameter:

```razor
<BarChart
    Categories="@categories"
    Series="@series"  
    Colors="@(new[] { "#3b82f6", "#10b981", "#f59e0b" })"
    Height="350" />
```

---

## Examples

### Multi-Series Bar Chart

```razor
<Card>
    <CardHeader>
        <CardTitle>Sales Overview</CardTitle>
        <CardDescription>Monthly revenue and expenses</CardDescription>
    </CardHeader>
    <CardContent>
        <BarChart
            Categories="@months"
            Series="@salesData"
            Variant="BarChartVariant.Default"
            Height="350" />
    </CardContent>
</Card>

@code {
    private string[] months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun" };
    private List<ChartSeries> salesData = new()
    {
        new ChartSeries 
        { 
            Name = "Revenue", 
            Data = new double[] { 45000, 52000, 48000, 61000, 58000, 67000 } 
        },
        new ChartSeries 
        { 
            Name = "Expenses", 
            Data = new double[] { 28000, 30000, 29000, 35000, 34000, 38000 } 
        }
    };
}
```

### Dashboard with Multiple Charts

```razor
<div class="grid gap-4 md:grid-cols-2">
    <Card>
        <CardHeader>
            <CardTitle>Revenue Trend</CardTitle>
        </CardHeader>
        <CardContent>
            <LineChart
                Categories="@quarters"
                Series="@revenueData"
                Height="300" />
        </CardContent>
    </Card>
    
    <Card>
        <CardHeader>
            <CardTitle>Market Share</CardTitle>
        </CardHeader>
        <CardContent>
            <PieChart
                Labels="@products"
                Data="@marketShare"
                Variant="PieChartVariant.Donut"
                Height="300" />
        </CardContent>
    </Card>
    
    <Card>
        <CardHeader>
            <CardTitle>Performance Metrics</CardTitle>
        </CardHeader>
        <CardContent>
            <RadarChart
                Categories="@metrics"
                Series="@performanceData"
                Height="300" />
        </CardContent>
    </Card>
    
    <Card>
        <CardHeader>
            <CardTitle>Progress</CardTitle>
        </CardHeader>
        <CardContent>
            <RadialChart
                Labels="@tasks"
                Data="@completion"
                Height="300" />
        </CardContent>
    </Card>
</div>
```

---

## Best Practices

### Responsive Charts

Charts automatically adapt to container width. Wrap in responsive containers:

```razor
<div class="container mx-auto">
    <BarChart Categories="@categories" Series="@series" Height="350" />
</div>
```

### Loading States

Show skeleton while data loads:

```razor
@if (isLoading)
{
    <Skeleton Class="h-[350px] w-full" />
}
else
{
    <BarChart Categories="@categories" Series="@series" Height="350" />
}
```

### Empty States

Handle no data gracefully:

```razor
@if (!series.Any() || series.All(s => !s.Data.Any()))
{
    <Empty>
        <EmptyIcon><LucideIcon Name="bar-chart" Size="48" /></EmptyIcon>
        <EmptyTitle>No data available</EmptyTitle>
        <EmptyDescription>Start tracking data to see charts here.</EmptyDescription>
    </Empty>
}
else
{
    <BarChart Categories="@categories" Series="@series" Height="350" />
}
```

### Card Composition

Always wrap charts in Card components for consistent styling:

```razor
<Card>
    <CardHeader>
        <CardTitle>Chart Title</CardTitle>
        <CardDescription>Chart description</CardDescription>
    </CardHeader>
    <CardContent>
        <BarChart Categories="@categories" Series="@series" Height="350" />
    </CardContent>
</Card>
```

---

## Dark Mode

Charts automatically adapt to dark mode when `.dark` class is applied to `<html>`:

- Background colors adapt to theme
- Grid lines and labels adjust contrast
- Chart colors remain vibrant and visible
- Tooltips and legends follow dark theme

No additional configuration needed!

---

## Performance Tips

1. **Limit data points:** For optimal performance, limit to ~100-200 data points per series
2. **Disable animations:** Set `Animations="false"` for large datasets
3. **Use appropriate chart type:** Choose chart types that match your data structure
4. **Virtualize large datasets:** Consider data aggregation for large time-series data
