# Localization

Source: https://blazorblueprintui.com/llms/localization.txt

## What the library localizes

BlazorBlueprint routes component chrome text through `IBbLocalizer`: button labels, placeholder text, ARIA labels, status messages, pagination text, and similar UI strings.

The upstream doc lists 189 keys. Load the official `localization.txt` when you need the full key catalog.

## Default behavior

```csharp
builder.Services.AddBlazorBlueprintComponents();
```

This registers `DefaultBbLocalizer` with English defaults.

## Override a few strings at startup

```csharp
builder.Services.AddBlazorBlueprintComponents(localizer =>
{
    localizer.Set("DataGrid.Loading", "Laden...");
    localizer.Set("Pagination.RowsPerPage", "Zeilen pro Seite");
});
```

Use this path when only a handful of labels need to change.

## Integrate with `IStringLocalizer`

Use a custom `IBbLocalizer` when the app already has a localization pipeline:

```csharp
public class AppBbLocalizer(IStringLocalizer<SharedResources> localizer) : DefaultBbLocalizer
{
    public override string this[string key] =>
        localizer[key] is { ResourceNotFound: false } found ? found.Value : base[key];
}

builder.Services.AddBlazorBlueprintComponents();
builder.Services.AddScoped<IBbLocalizer, AppBbLocalizer>();
```

Use scoped lifetime for per-circuit culture switching in Blazor Server.

## Resolution order

When a component needs text, the docs describe this order:
1. Explicit component parameter value
2. `IBbLocalizer` from DI
3. Built-in English default

## Key conventions

Keys use dot notation such as:
- `DataGrid.Loading`
- `Pagination.RowsPerPage`
- `FormWizard.Next`

Parameterized strings use normal `string.Format` placeholders.

## Culture-aware areas

The docs call out culture-sensitive behavior in components such as:
- `BbCalendar`
- `BbDatePicker`
- `BbDateRangePicker`
- `BbNumericInput`

If the task is about date labels, separators, or formatted counts, check both the component parameters and the localizer keys.
