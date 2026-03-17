# Form Components Reference

Concise routing for the current BlazorBlueprint form layer. Use this to choose the right component family quickly instead of memorizing the full catalog.

**Sources:** https://blazorblueprintui.com/llms/components/ and https://blazorblueprintui.com/llms/patterns.txt

## TOC
- [Choose the right family](#choose-the-right-family)
- [Core form scaffold](#core-form-scaffold)
- [Text and typed input](#text-and-typed-input)
- [Selection controls](#selection-controls)
- [Date time and structured entry](#date-time-and-structured-entry)
- [Rich media and advanced input](#rich-media-and-advanced-input)
- [Generated and multi-step forms](#generated-and-multi-step-forms)
- [Reference example](#reference-example)

## Choose the right family

| Need | Prefer | Notes |
| --- | --- | --- |
| Plain text input | `BbInput`, `BbTextarea`, `BbInputGroup` | Fastest path for most fields. |
| Typed parsing / formatting | `BbInputField<TValue>`, `BbNumericInput`, `BbCurrencyInput`, `BbMaskedInput` | Use when string-only binding is not enough. |
| Single choice | `BbSelect`, `BbNativeSelect`, `BbRadioGroup`, `BbCombobox` | `BbCombobox` is best when search matters. |
| Multiple choice | `BbMultiSelect`, `BbCheckboxGroup`, `BbTagInput`, `BbToggleGroup` | Pick based on whether the values come from a fixed set or free-form entry. |
| Boolean / toggled state | `BbCheckbox`, `BbSwitch`, `BbToggle` | `BbSwitch` reads best for settings. |
| Date or time | `BbCalendar`, `BbDatePicker`, `BbDateRangePicker`, `BbTimePicker` | `BbDateRangePicker` is the dashboard/reporting choice. |
| OTP / short structured entry | `BbInputOTP` | Best for verification flows. |
| Uploads or rich editing | `BbFileUpload`, `BbRichTextEditor`, `BbMarkdownEditor`, `BbColorPicker`, `BbRating` | Use only when plain inputs are too limited. |
| Reusable form layout | `BbField`, `BbFormSection`, `BbFormField*` helpers | Best for consistent labels, descriptions, and validation output. |
| Wizard or generated form | `BbFormWizard`, `BbDynamicForm` | Use for multi-step or schema-driven UI. |
| Compound action buttons | `BbButton`, `BbButtonGroup`, `BbSplitButton` | Action surfaces, not data-entry controls. |

## Core form scaffold

Start with `BbField` when you want a predictable accessible layout:

```razor
<BbField>
    <BbFieldLabel>Email</BbFieldLabel>
    <BbFieldContent>
        <BbInput @bind-Value="model.Email"
                 ValueExpression="@(() => model.Email)" />
    </BbFieldContent>
    <BbFieldDescription>We only use this for account messages.</BbFieldDescription>
    <BbFieldError>
        <ValidationMessage For="@(() => model.Email)" />
    </BbFieldError>
</BbField>
```

Use the `BbFormField*` wrappers when you want this structure pre-bundled for a specific input type.

## Text and typed input

### `BbInput` vs `BbInputField<TValue>`
- `BbInput` is the default for plain string entry.
- `BbInputField<TValue>` is the general typed input when you need parsing, formatting, debounce control, or custom validation for non-string values.

`BbInputField<TValue>` is especially useful for dates, decimals, and typed business values:

```razor
<BbInputField TValue="decimal"
              @bind-Value="model.Budget"
              Format="N2"
              Validation="@(value => value >= 0)" />
```

Prefer specialized typed inputs when they match the domain more directly:
- `BbNumericInput` for increment/decrement numeric editing
- `BbCurrencyInput` for localized money entry
- `BbMaskedInput` for phone, card, ID, and other format-constrained text
- `BbInputOTP` for verification code entry

## Selection controls

Selection routing:
- Use `BbSelect` for standard styled dropdown selection.
- Use `BbNativeSelect` when browser-native behavior is enough or desirable.
- Use `BbCombobox` when the option list needs search or async filtering.
- Use `BbMultiSelect` for fixed-option multi-pick.
- Use `BbTagInput` when users create their own values.
- Use `BbCheckboxGroup` or `BbRadioGroup` when visible options improve comprehension.

`BbCombobox` is especially important in the current docs because it supports external filtering:

```razor
<BbCombobox TValue="int"
            Options="@countryOptions"
            @bind-Value="selectedCountryId"
            @bind-SearchQuery="searchQuery"
            SearchQueryChanged="LoadCountriesAsync"
            MatchTriggerWidth />
```

## Date time and structured entry

Use:
- `BbCalendar` for inline calendar UI
- `BbDatePicker` for a single-date field with overlay calendar
- `BbDateRangePicker` for reporting, analytics, and filter bars
- `BbTimePicker` for time-only entry

For structured short values, `BbMaskedInput` and `BbInputOTP` are the main tools.

## Rich media and advanced input

High-value components in this group:
- `BbFileUpload` for drag/drop or previewable uploads
- `BbRichTextEditor` and `BbMarkdownEditor` for authored content
- `BbColorPicker` for theme/editor workflows
- `BbRating` for feedback and review flows

These are powerful but heavier than basic inputs, so use them only when the workflow clearly benefits.

## Generated and multi-step forms

Use these only when the workflow justifies the added abstraction:
- `BbDynamicForm` for schema/config-driven forms
- `BbFormWizard` for step-based onboarding or checkout
- `BbFormSection` for grouping long forms into readable regions

If the form is mostly static, plain `EditForm` + `BbField` remains easier for AI to generate and maintain.

## Reference example

```razor
<EditForm Model="@model" OnValidSubmit="SaveAsync">
    <DataAnnotationsValidator />

    <BbField>
        <BbFieldLabel>Name</BbFieldLabel>
        <BbFieldContent>
            <BbInput @bind-Value="model.Name"
                     ValueExpression="@(() => model.Name)"
                     Placeholder="Acme Corp" />
        </BbFieldContent>
        <BbFieldError>
            <ValidationMessage For="@(() => model.Name)" />
        </BbFieldError>
    </BbField>

    <BbField>
        <BbFieldLabel>Tags</BbFieldLabel>
        <BbFieldContent>
            <BbTagInput @bind-Tags="model.Tags"
                        TagsExpression="@(() => model.Tags)"
                        Placeholder="Add tag..." />
        </BbFieldContent>
    </BbField>

    <BbButton type="submit">Save</BbButton>
</EditForm>
```
