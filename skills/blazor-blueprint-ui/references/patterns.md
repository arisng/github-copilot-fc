# BlazorBlueprint Common Patterns & Multi-Component Examples

This guide shows real-world patterns for using multiple BlazorBlueprint components together.

**Source:** https://blazorblueprintui.com/llms/patterns.txt

---

## Form with Validation

Combine Field, Label, Input, and error handling for accessible forms:

```razor
@using BlazorBlueprint.Components

<EditForm Model="@model" OnValidSubmit="@HandleSubmit">
    <DataAnnotationsValidator />
    
    <Field>
        <FieldLabel>Email</FieldLabel>
        <FieldContent>
            <Input @bind-Value="model.Email" Type="email" Placeholder="name@example.com" />
        </FieldContent>
        <FieldDescription>We'll never share your email with anyone else.</FieldDescription>
        <FieldError>
            <ValidationMessage For="@(() => model.Email)" />
        </FieldError>
    </Field>
    
    <Field>
        <FieldLabel>Password</FieldLabel>
        <FieldContent>
            <Input @bind-Value="model.Password" Type="password" />
        </FieldContent>
        <FieldDescription>Must be at least 8 characters long.</FieldDescription>
        <FieldError>
            <ValidationMessage For="@(() => model.Password)" />
        </FieldError>
    </Field>
    
    <div class="flex items-center space-x-2">
        <Checkbox Id="remember" @bind-Checked="model.RememberMe" />
        <Label For="remember">Remember me</Label>
    </div>
    
    <Button Type="submit" Class="w-full">Sign In</Button>
</EditForm>

@code {
    private LoginModel model = new();
    
    private async Task HandleSubmit()
    {
        // Handle form submission
    }
    
    public class LoginModel
    {
        [Required]
        [EmailAddress]
        public string Email { get; set; } = "";
        
        [Required]
        [MinLength(8)]
        public string Password { get; set; } = "";
        
        public bool RememberMe { get; set; }
    }
}
```

---

## Dialog with Form

Use Dialog to create modal forms for editing or creating data:

```razor
@using BlazorBlueprint.Components

<Dialog>
    <DialogTrigger>Edit Profile</DialogTrigger>
    <DialogContent>
        <DialogHeader>
            <DialogTitle>Edit Profile</DialogTitle>
            <DialogDescription>
                Make changes to your profile here. Click save when you're done.
            </DialogDescription>
        </DialogHeader>
        
        <div class="space-y-4 py-4">
            <Field>
                <FieldLabel>Name</FieldLabel>
                <FieldContent>
                    <Input @bind-Value="name" Placeholder="John Doe" />
                </FieldContent>
            </Field>
            
            <Field>
                <FieldLabel>Email</FieldLabel>
                <FieldContent>
                    <Input @bind-Value="email" Type="email" Placeholder="john@example.com" />
                </FieldContent>
            </Field>
            
            <Field>
                <FieldLabel>Bio</FieldLabel>
                <FieldContent>
                    <Textarea @bind-Value="bio" Placeholder="Tell us about yourself..." />
                </FieldContent>
                <FieldDescription>Brief description for your profile.</FieldDescription>
            </Field>
        </div>
        
        <DialogFooter>
            <DialogClose>Cancel</DialogClose>
            <Button OnClick="SaveProfile">Save Changes</Button>
        </DialogFooter>
    </DialogContent>
</Dialog>

@code {
    private string name = "John Doe";
    private string email = "john@example.com";
    private string bio = "";
    
    private async Task SaveProfile()
    {
        // Save profile changes
        await Task.CompletedTask;
    }
}
```

---

## Data Table with Sorting and Pagination

Build powerful data tables with sorting, filtering, and pagination - see full example at source URL.

---

## Sidebar Navigation

Create a responsive sidebar with collapsible menus and keyboard shortcuts - see full example at source URL.

**Note:** Sidebar supports keyboard shortcuts - press `Ctrl/Cmd+B` to toggle!

---

## Command Palette

Build a searchable command palette for quick actions - see full example at source URL.

---

## Settings Page with Tabs and Forms

Organize complex settings using Tabs, Cards, and Forms - see full example at source URL.

---

## Confirmation Dialog

Create reusable confirmation dialogs for destructive actions:

```razor
@using BlazorBlueprint.Components

<Dialog @bind-Open="isOpen">
    <DialogContent>
        <DialogHeader>
            <DialogTitle>Are you absolutely sure?</DialogTitle>
            <DialogDescription>
                This action cannot be undone. This will permanently delete your
                account and remove your data from our servers.
            </DialogDescription>
        </DialogHeader>
        
        <div class="bg-destructive/10 border border-destructive/20 rounded-lg p-4 my-4">
            <div class="flex items-start space-x-2">
                <LucideIcon Name="alert-triangle" Size="20" Class="text-destructive mt-0.5" />
                <div>
                    <p class="font-medium text-destructive">Warning</p>
                    <p class="text-sm text-muted-foreground">
                        All of your data will be permanently deleted.
                    </p>
                </div>
            </div>
        </div>
        
        <DialogFooter>
            <DialogClose>Cancel</DialogClose>
            <Button Variant="destructive" OnClick="ConfirmDelete">
                Delete Account
            </Button>
        </DialogFooter>
    </DialogContent>
</Dialog>

<Button Variant="destructive" OnClick="() => isOpen = true">
    Delete Account
</Button>

@code {
    private bool isOpen = false;
    
    private async Task ConfirmDelete()
    {
        // Handle deletion
        isOpen = false;
    }
}
```

---

## Multi-Select with Popover

Create a multi-select dropdown using Popover and Checkbox - see full example at source URL.

---

## AsChild Pattern

The `AsChild` pattern allows trigger and close components to pass their behavior to a child component instead of rendering their own button element.

### Basic AsChild Usage

```razor
@using BlazorBlueprint.Components

@* Use Button as DialogTrigger *@
<Dialog>
    <DialogTrigger AsChild>
        <Button Variant="ButtonVariant.Destructive">Delete Account</Button>
    </DialogTrigger>
    <DialogContent>
        <DialogHeader>
            <DialogTitle>Confirm Deletion</DialogTitle>
        </DialogHeader>
        <DialogFooter>
            <DialogClose AsChild>
                <Button Variant="ButtonVariant.Outline">Cancel</Button>
            </DialogClose>
            <Button Variant="ButtonVariant.Destructive">Delete</Button>
        </DialogFooter>
    </DialogContent>
</Dialog>
```

### DropdownMenu with Button Trigger

```razor
<DropdownMenu>
    <DropdownMenuTrigger AsChild>
        <Button Variant="ButtonVariant.Outline">
            Actions
            <LucideIcon Name="chevron-down" Size="16" />
        </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent>
        <DropdownMenuItem>Edit</DropdownMenuItem>
        <DropdownMenuItem>Delete</DropdownMenuItem>
    </DropdownMenuContent>
</DropdownMenu>
```

### Components Supporting AsChild

The following components support the `AsChild` parameter:
- `DialogTrigger` / `DialogClose`
- `DropdownMenuTrigger`
- `PopoverTrigger`
- `SheetTrigger` / `SheetClose`
- `TooltipTrigger`
- `HoverCardTrigger`
- `CollapsibleTrigger`

When `AsChild` is true, the trigger passes a `TriggerContext` to child components via `CascadingValue`. The `Button` component automatically consumes this context and applies the appropriate click handlers, aria attributes, and keyboard handling.
