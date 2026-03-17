# Chart Components Reference

Current BlazorBlueprint charts are built on **Apache ECharts**, not ApexCharts. Use this file to pick the right chart surface and understand the current chart composition model.

**Sources:**
- https://blazorblueprintui.com/llms/components/chart.txt
- https://blazorblueprintui.com/llms/components/chart-container.txt
- https://blazorblueprintui.com/llms/components/bar-chart.txt
- https://blazorblueprintui.com/llms/components/pie-chart.txt
- https://blazorblueprintui.com/llms/components/radial-bar-chart.txt
- https://blazorblueprintui.com/llms/components/scatter-chart.txt
- https://blazorblueprintui.com/llms/components/gauge-chart.txt

## TOC
- [Choose the chart surface](#choose-the-chart-surface)
- [Current chart model](#current-chart-model)
- [Reference examples](#reference-examples)
- [Chart-specific guidance](#chart-specific-guidance)
- [Theme and styling](#theme-and-styling)

## Choose the chart surface

| Need | Prefer | Notes |
| --- | --- | --- |
| Mixed series in one plot | `BbChart` | Combine `BbBar`, `BbLine`, `BbArea`, `BbScatter`, and shared axes/legend/tooltip. |
| Standard cartesian chart | `BbBarChart`, `BbLineChart`, `BbAreaChart`, `BbScatterChart` | Best when all series belong to one family. |
| Part-to-whole chart | `BbPieChart` | Use `InnerRadius` for donut charts. |
| Circular progress or comparative arcs | `BbRadialBarChart` | Great for completion metrics and ring summaries. |
| Single KPI gauge | `BbGaugeChart` | Meter/speedometer style. |
| Radial comparison | `BbRadarChart` | Best for comparing several dimensions on one shape. |
| Specialized analytics | `BbHeatmapChart`, `BbFunnelChart`, `BbCandlestickChart` | Load the specific upstream doc only when needed. |
| Consistent card-like wrapper | `BbChartContainer` | Preferred visual shell for dashboards. |

## Current chart model

The v3 chart mental model is:

1. `Data` is typically an `IEnumerable<T>` of records or objects.
2. Series extract values with `DataKey` (and `NameKey` where relevant).
3. `ChartConfig.Create(...)` maps series keys to labels and colors.
4. Axes, tooltip, legend, grid, and series are composed as child components.
5. ECharts JS is lazy-loaded automatically through JS interop.

Minimal config example:

```csharp
private ChartConfig chartConfig = ChartConfig.Create(
    ("revenue", new ChartSeriesConfig { Label = "Revenue", Color = "var(--chart-1)" }),
    ("profit", new ChartSeriesConfig { Label = "Profit", Color = "var(--chart-2)" })
);
```

Important differences from the old guidance:
- Use `Height="350px"`, not an integer height convention.
- Use series components such as `BbBar`, `BbLine`, `BbPie`, and `BbRadialBar`.
- Pie, radial bar, and gauge charts do **not** use `BbXAxis`, `BbYAxis`, or `BbGrid`.

## Reference examples

### Composite chart

```razor
<BbChartContainer>
    <BbChart Data="@data" Config="@chartConfig" Height="350px">
        <BbXAxis DataKey="month" />
        <BbYAxis />
        <BbChartTooltip />
        <BbChartLegend />
        <BbBar DataKey="revenue" BorderRadius="4" />
        <BbLine DataKey="profit" Curve="CurveType.Smooth" StrokeWidth="3" />
    </BbChart>
</BbChartContainer>
```

### Donut chart with center label

```razor
<BbChartContainer>
    <BbPieChart Data="@browserData" Config="@chartConfig">
        <BbChartTooltip />
        <BbChartLegend Position="LegendPosition.Right" />
        <BbPie DataKey="visitors" NameKey="browser" InnerRadius="60">
            <BbCenterLabel Value="1,024" Title="Visitors" />
        </BbPie>
    </BbPieChart>
</BbChartContainer>
```

### Radial progress summary

```razor
<BbRadialBarChart Data="@browserData" Config="@chartConfig" Height="300px">
    <BbChartTooltip />
    <BbRadialBar DataKey="visitors" NameKey="browser" ShowBackground="true">
        <BbCenterLabel Text="Browsers" FontSize="18" />
    </BbRadialBar>
</BbRadialBarChart>
```

## Chart-specific guidance

### Bar and cartesian charts
- `BbBarChart` supports grouped, stacked, horizontal, labeled, and per-item colored bars (`FillKey`).
- `BbScatterChart` becomes a bubble chart when you add `SymbolSizeKey`.
- Use `BbChart` instead of forcing mixed bar/line/area behavior into a single-type chart.

### Pie and radial charts
- `BbPie` with `InnerRadius > 0` is the donut path.
- `BbRadialBarChart` is the better choice for progress rings and completion summaries.
- Both support `BbCenterLabel`.

### Gauge and specialized charts
- `BbGaugeChart` is for a small number of headline KPIs.
- `BbHeatmapChart`, `BbFunnelChart`, and `BbCandlestickChart` are available, but only load their dedicated upstream docs when the scenario truly needs them.

## Theme and styling

Charts integrate with the standard chart palette variables:

```css
:root {
    --chart-1: oklch(...);
    --chart-2: oklch(...);
    --chart-3: oklch(...);
    --chart-4: oklch(...);
    --chart-5: oklch(...);
}
```

Best practices:
- Wrap charts in `BbChartContainer` or `BbCard` for dashboard consistency.
- Pair chart loading states with `BbSkeleton`.
- Pair no-data states with `BbEmpty`.
- Prefer `ChartConfig` over hard-coding labels/colors in multiple places.
