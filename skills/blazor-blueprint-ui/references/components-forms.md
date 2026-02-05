# Form Components Reference

Comprehensive reference for all 26 form components in BlazorBlueprint.

**Source Component Docs:** https://blazorblueprintui.com/llms/components/

---

## Button

Interactive button with multiple visual variants, sizes, and states.

**Source:** https://blazorblueprintui.com/llms/components/button.txt

### Variants
- `Default` - Primary action button
- `Destructive` - Dangerous actions (red)
- `Outline` - Secondary action with border
- `Secondary` - Less prominent actions
- `Ghost` - Minimal styling
- `Link` - Link-styled button

### Sizes
- `Small` - Compact (h-9)
- `Default` - Standard (h-10)
- `Large` - Larger (h-11)
- `Icon`, `IconSmall`, `IconLarge` - Square icon buttons

### Example

```razor
<Button Variant="ButtonVariant.Default">Click me</Button>
<Button Variant="ButtonVariant.Destructive">Delete</Button>
<Button Size="ButtonSize.Icon" AriaLabel="Add">
    <LucideIcon Name="plus" Size="20" />
</Button>
```

### Key Parameters
- `Variant`, `Size`, `Type` (Button/Submit/Reset)
- `Disabled`, `OnClick`, `AriaLabel`
- `Icon`, `IconPosition` (Start/End)

---

## Input Components

### Input
Text input fields (text, email, password, etc.)

```razor
<Input @bind-Value="value" Type="email" Placeholder="name@example.com" />
```

### Input Group
Enhanced inputs with icons/buttons/addons

```razor
<InputGroup>
    <InputGroupInput Placeholder="Search..." />
    <InputGroupAddon Align="InlineEnd">
        <InputGroupButton>
            <LucideIcon Name="search" Size="16" />
        </InputGroupButton>
    </InputGroupAddon>
</InputGroup>
```

### Textarea
Multi-line text input with auto-sizing

```razor
<Textarea @bind-Value="bio" Rows="4" Placeholder="Tell us about yourself..." />
```

### Masked Input
Structured formats (phone, SSN, credit card, date)

```razor
<MaskedInput @bind-Value="phone" Mask="(999) 999-9999" />
<MaskedInput @bind-Value="ssn" Mask="999-99-9999" />
<MaskedInput @bind-Value="card" Mask="9999 9999 9999 9999" />
```

**Mask Patterns:**
- `9` = digit
- `A` = letter
- `*` = alphanumeric

### Numeric Input
Generic numeric input with increment/decrement

```razor
<NumericInput @bind-Value="quantity" Min="0" Max="100" Step="1" />
```

### Currency Input
Locale-aware currency input with 40+ currencies

```razor
<CurrencyInput @bind-Value="amount" Currency="USD" />
<CurrencyInput @bind-Value="amount" Currency="EUR" />
```

### Input OTP
One-time password input with individual digit boxes

```razor
<InputOTP @bind-Value="otp" Length="6" />
```

---

## Selection Components

### Checkbox
Binary selection with indeterminate state

```razor
<Checkbox Id="terms" @bind-Checked="accepted" />
<Label For="terms">Accept terms</Label>
```

### Radio Group
Mutually exclusive selections

```razor
<RadioGroup @bind-Value="selectedOption">
    <RadioGroupItem Value="option1" Id="opt1" />
    <Label For="opt1">Option 1</Label>
    
    <RadioGroupItem Value="option2" Id="opt2" />
    <Label For="opt2">Option 2</Label>
</RadioGroup>
```

### Switch
Toggle for binary on/off states

```razor
<Switch @bind-Checked="isEnabled" />
<Label>Enable notifications</Label>
```

### Select
Dropdown selection with groups

```razor
<Select @bind-Value="selected">
    <SelectTrigger>
        <SelectValue Placeholder="Choose option" />
    </SelectTrigger>
    <SelectContent>
        <SelectItem Value="option1">Option 1</SelectItem>
        <SelectItem Value="option2">Option 2</SelectItem>
    </SelectContent>
</Select>
```

### MultiSelect
Searchable multi-select with tags and Select All

```razor
<MultiSelect @bind-Values="selectedItems" Placeholder="Select frameworks...">
    <MultiSelectItem Value="react">React</MultiSelectItem>
    <MultiSelectItem Value="vue">Vue</MultiSelectItem>
    <MultiSelectItem Value="angular">Angular</MultiSelectItem>
</MultiSelect>
```

### Native Select
Browser-native select element

```razor
<NativeSelect @bind-Value="selected">
    <option value="">Choose...</option>
    <option value="1">Option 1</option>
    <option value="2">Option 2</option>
</NativeSelect>
```

---

## Date & Time Components

### Calendar
Interactive calendar with full keyboard navigation

```razor
<Calendar @bind-SelectedDate="date" MinDate="DateTime.Today" />
```

### Date Picker
Date picker with popover calendar

```razor
<DatePicker @bind-Date="selectedDate" Placeholder="Pick a date" />
```

### Date Range Picker
Date range selection with preset ranges

```razor
<DateRangePicker @bind-StartDate="start" @bind-EndDate="end">
    <DateRangePreset Label="Last 7 days" Days="7" />
    <DateRangePreset Label="Last 30 days" Days="30" />
    <DateRangePreset Label="This month" IsCurrentMonth="true" />
</DateRangePicker>
```

### Time Picker
Time selection with 12/24-hour format

```razor
<TimePicker @bind-Time="time" Format="12" ShowSeconds="false" />
```

---

## Slider Components

### Slider
Range input for selecting numeric values

```razor
<Slider @bind-Value="volume" Min="0" Max="100" Step="1" />
```

### Range Slider
Dual-handle slider for value ranges

```razor
<RangeSlider @bind-MinValue="min" @bind-MaxValue="max" Min="0" Max="100" />
```

---

## Advanced Input Components

### Rich Text Editor
WYSIWYG editor built on Quill.js v2

```razor
<RichTextEditor @bind-Html="content" />
```

### Color Picker
Visual color selection with hex/RGB input

```razor
<ColorPicker @bind-Color="selectedColor" ShowAlpha="true" />
```

### File Upload
Drag-and-drop file upload with previews

```razor
<FileUpload 
    @bind-Files="uploadedFiles"
    Accept="image/*"
    MaxSize="5242880"
    Multiple="true" />
```

### Rating
Star rating with half-value and custom icons

```razor
<Rating @bind-Value="rating" Max="5" AllowHalf="true" />
<Rating @bind-Value="rating" Icon="Heart" />
<Rating @bind-Value="rating" Icon="ThumbsUp" />
```

---

## Form Layout Components

### Label
Accessible label for form controls

```razor
<Label For="email">Email Address</Label>
<Input Id="email" @bind-Value="email" Type="email" />
```

### Field
Combines labels, controls, help text, error messages

```razor
<Field>
    <FieldLabel>Email</FieldLabel>
    <FieldContent>
        <Input @bind-Value="email" Type="email" />
    </FieldContent>
    <FieldDescription>We'll never share your email.</FieldDescription>
    <FieldError>
        <ValidationMessage For="@(() => email)" />
    </FieldError>
</Field>
```

### Button Group
Visually groups related buttons

```razor
<ButtonGroup>
    <Button>Left</Button>
    <Button>Center</Button>
    <Button>Right</Button>
</ButtonGroup>
```

### Toggle
Two-state button for toggleable options

```razor
<Toggle @bind-Pressed="isBold" AriaLabel="Toggle bold">
    <LucideIcon Name="bold" Size="16" />
</Toggle>
```

---

## Form Best Practices

### Accessible Forms

Always use Field component for proper structure:

```razor
<Field>
    <FieldLabel>Required field</FieldLabel>
    <FieldContent>
        <Input @bind-Value="value" Required="true" />
    </FieldContent>
    <FieldDescription>Help text here</FieldDescription>
    <FieldError>
        <ValidationMessage For="@(() => value)" />
    </FieldError>
</Field>
```

### Loading States

```razor
<Button Disabled="@isSubmitting">
    @if (isSubmitting)
    {
        <LucideIcon Name="loader-2" Size="16" Class="animate-spin" />
        <span>Submitting...</span>
    }
    else
    {
        <span>Submit</span>
    }
</Button>
```

### Form Validation

```razor
<EditForm Model="@model" OnValidSubmit="@HandleSubmit">
    <DataAnnotationsValidator />
    
    <Field>
        <FieldLabel>Email</FieldLabel>
        <FieldContent>
            <Input @bind-Value="model.Email" Type="email" />
        </FieldContent>
        <FieldError>
            <ValidationMessage For="@(() => model.Email)" />
        </FieldError>
    </Field>
    
    <Button Type="ButtonType.Submit">Submit</Button>
</EditForm>
```
