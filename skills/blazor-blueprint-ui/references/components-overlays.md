# Overlay & Display Components Reference

Reference for overlay and display components in BlazorBlueprint.

**Source Component Docs:** https://blazorblueprintui.com/llms/components/

---

## Overlay Components

All overlay components require `<PortalHost />` in your layout.

### Dialog
Modal dialog with backdrop, focus management, and composition-based structure

```razor
<Dialog>
    <DialogTrigger>Open Dialog</DialogTrigger>
    <DialogContent>
        <DialogHeader>
            <DialogTitle>Dialog Title</DialogTitle>
            <DialogDescription>Dialog description</DialogDescription>
        </DialogHeader>
        <p>Dialog content</p>
        <DialogFooter>
            <DialogClose>Cancel</DialogClose>
            <Button>Confirm</Button>
        </DialogFooter>
    </DialogContent>
</Dialog>
```

**Features:** Backdrop overlay, focus trap, escape key to close, controlled/uncontrolled modes

### Alert Dialog
Modal dialog requiring user acknowledgement, cannot be dismissed by clicking outside

```razor
<AlertDialog>
    <AlertDialogTrigger AsChild>
        <Button Variant="destructive">Delete Account</Button>
    </AlertDialogTrigger>
    <AlertDialogContent>
        <AlertDialogHeader>
            <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
            <AlertDialogDescription>
                This action cannot be undone.
            </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction>Delete</AlertDialogAction>
        </AlertDialogFooter>
    </AlertDialogContent>
</AlertDialog>
```

### Sheet
Side panel that slides in from viewport edges with overlay

```razor
<Sheet>
    <SheetTrigger>Open Sheet</SheetTrigger>
    <SheetContent Side="right">
        <SheetHeader>
            <SheetTitle>Sheet Title</SheetTitle>
            <SheetDescription>Sheet description</SheetDescription>
        </SheetHeader>
        <!-- Sheet content -->
        <SheetFooter>
            <SheetClose>Close</SheetClose>
        </SheetFooter>
    </SheetContent>
</Sheet>
```

**Sides:** `left`, `right`, `top`, `bottom`

### Drawer
Mobile-friendly panel sliding from screen edge (similar to Sheet)

```razor
<Drawer>
    <DrawerTrigger>Open Drawer</DrawerTrigger>
    <DrawerContent>
        <DrawerHeader>
            <DrawerTitle>Drawer Title</DrawerTitle>
        </DrawerHeader>
        <!-- Drawer content -->
    </DrawerContent>
</Drawer>
```

### Popover
Floating panel for additional content and actions

```razor
<Popover>
    <PopoverTrigger AsChild>
        <Button Variant="outline">Open Popover</Button>
    </PopoverTrigger>
    <PopoverContent>
        <div class="space-y-2">
            <h4 class="font-medium">Popover Title</h4>
            <p class="text-sm">Popover content goes here</p>
        </div>
    </PopoverContent>
</Popover>
```

### Tooltip
Brief informational popup on hover or focus

```razor
<Tooltip>
    <TooltipTrigger AsChild>
        <Button Size="icon">
            <LucideIcon Name="info" Size="16" />
        </Button>
    </TooltipTrigger>
    <TooltipContent>
        <p>Additional information</p>
    </TooltipContent>
</Tooltip>
```

### Hover Card
Rich preview card on hover with delay control

```razor
<HoverCard>
    <HoverCardTrigger>
        <span class="underline">Hover me</span>
    </HoverCardTrigger>
    <HoverCardContent>
        <div class="flex space-x-4">
            <Avatar>
                <AvatarImage Src="user.jpg" />
                <AvatarFallback>JD</AvatarFallback>
            </Avatar>
            <div>
                <h4 class="font-semibold">John Doe</h4>
                <p class="text-sm">Software Engineer</p>
            </div>
        </div>
    </HoverCardContent>
</HoverCard>
```

### Dropdown Menu
Context menu with items, separators, keyboard shortcuts, nested submenus

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
            <LucideIcon Name="copy" Size="16" />
            Duplicate
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem>
            <LucideIcon Name="trash" Size="16" />
            Delete
        </DropdownMenuItem>
    </DropdownMenuContent>
</DropdownMenu>
```

### Context Menu
Right-click menu with customizable items and shortcuts

```razor
<ContextMenu>
    <ContextMenuTrigger>
        <div class="border p-8 text-center">
            Right-click me
        </div>
    </ContextMenuTrigger>
    <ContextMenuContent>
        <ContextMenuItem>Edit</ContextMenuItem>
        <ContextMenuItem>Copy</ContextMenuItem>
        <ContextMenuSeparator />
        <ContextMenuItem>Delete</ContextMenuItem>
    </ContextMenuContent>
</ContextMenu>
```

### Menubar
Desktop application-style menu bar with dropdown menus

```razor
<Menubar>
    <MenubarMenu>
        <MenubarTrigger>File</MenubarTrigger>
        <MenubarContent>
            <MenubarItem>New <MenubarShortcut>⌘N</MenubarShortcut></MenubarItem>
            <MenubarItem>Open <MenubarShortcut>⌘O</MenubarShortcut></MenubarItem>
            <MenubarSeparator />
            <MenubarItem>Exit</MenubarItem>
        </MenubarContent>
    </MenubarMenu>
    <MenubarMenu>
        <MenubarTrigger>Edit</MenubarTrigger>
        <MenubarContent>
            <MenubarItem>Undo</MenubarItem>
            <MenubarItem>Redo</MenubarItem>
        </MenubarContent>
    </MenubarMenu>
</Menubar>
```

### Combobox
Autocomplete input with searchable dropdown

```razor
<Combobox @bind-Value="selected" Placeholder="Search...">
    <ComboboxTrigger>
        <ComboboxValue Placeholder="Select option" />
    </ComboboxTrigger>
    <ComboboxContent>
        <ComboboxInput Placeholder="Search..." />
        <ComboboxList>
            <ComboboxEmpty>No results found.</ComboboxEmpty>
            <ComboboxItem Value="option1">Option 1</ComboboxItem>
            <ComboboxItem Value="option2">Option 2</ComboboxItem>
            <ComboboxItem Value="option3">Option 3</ComboboxItem>
        </ComboboxList>
    </ComboboxContent>
</Combobox>
```

### Command
Command palette for quick actions with keyboard shortcuts and virtualized groups

```razor
<Dialog>
    <DialogTrigger AsChild>
        <Button Variant="outline">
            <LucideIcon Name="search" Size="16" />
            Search commands... <kbd>⌘K</kbd>
        </Button>
    </DialogTrigger>
    <DialogContent Class="p-0">
        <Command>
            <CommandInput Placeholder="Type a command or search..." />
            <CommandList>
                <CommandEmpty>No results found.</CommandEmpty>
                
                <CommandGroup Heading="Suggestions">
                    <CommandItem>
                        <LucideIcon Name="home" Size="16" />
                        Dashboard
                    </CommandItem>
                    <CommandItem>
                        <LucideIcon Name="folder" Size="16" />
                        Projects
                    </CommandItem>
                </CommandGroup>
                
                <CommandSeparator />
                
                <CommandGroup Heading="Actions">
                    <CommandItem>
                        <LucideIcon Name="plus" Size="16" />
                        Create Project <kbd>⌘N</kbd>
                    </CommandItem>
                </CommandGroup>
            </CommandList>
        </Command>
    </DialogContent>
</Dialog>
```

### Toast
Temporary notification messages with service-based API

```razor
@inject IToastService ToastService

<Button OnClick="ShowToast">Show Toast</Button>

@code {
    private void ShowToast()
    {
        ToastService.Show("Success!", "Your changes have been saved.", ToastVariant.Success);
    }
}
```

**Variants:** `Default`, `Success`, `Error`, `Warning`, `Info`  
**Positions:** `TopLeft`, `TopCenter`, `TopRight`, `BottomLeft`, `BottomCenter`, `BottomRight`

---

## Display Components

### Avatar
User profile image with fallback support

```razor
<Avatar>
    <AvatarImage Src="user.jpg" Alt="John Doe" />
    <AvatarFallback>JD</AvatarFallback>
</Avatar>
```

### Badge
Label component for displaying status, categories, metadata

```razor
<Badge>Default</Badge>
<Badge Variant="secondary">Secondary</Badge>
<Badge Variant="destructive">Destructive</Badge>
<Badge Variant="outline">Outline</Badge>
```

### Alert
Callout component for important messages with semantic variants

```razor
<Alert Variant="default">
    <AlertTitle>
        <LucideIcon Name="info" Size="16" />
        Info
    </AlertTitle>
    <AlertDescription>
        This is an informational message.
    </AlertDescription>
</Alert>

<Alert Variant="success">
    <AlertTitle>Success</AlertTitle>
    <AlertDescription>Your changes have been saved.</AlertDescription>
</Alert>

<Alert Variant="warning">
    <AlertTitle>Warning</AlertTitle>
    <AlertDescription>This action cannot be undone.</AlertDescription>
</Alert>

<Alert Variant="danger">
    <AlertTitle>Error</AlertTitle>
    <AlertDescription>Something went wrong.</AlertDescription>
</Alert>
```

**Variants:** `Default`, `Success`, `Info`, `Warning`, `Danger`

### Skeleton
Animated loading placeholder for content and images

```razor
<div class="space-y-2">
    <Skeleton Class="h-4 w-[250px]" />
    <Skeleton Class="h-4 w-[200px]" />
    <Skeleton Class="h-32 w-full" />
</div>
```

### Progress
Progress bar showing completion percentage

```razor
<Progress Value="@progress" Max="100" />

@code {
    private int progress = 65;
}
```

### Spinner
Loading spinner for indeterminate operations

```razor
<Spinner Size="default" />
<Spinner Size="small" />
<Spinner Size="large" />
```

### Empty
Empty state placeholder with icon, title, description, and action slots

```razor
<Empty Size="Default">
    <EmptyIcon>
        <LucideIcon Name="inbox" Size="48" />
    </EmptyIcon>
    <EmptyTitle>No items found</EmptyTitle>
    <EmptyDescription>
        Get started by creating your first item.
    </EmptyDescription>
    <EmptyAction>
        <Button>Create Item</Button>
    </EmptyAction>
</Empty>
```

**Sizes:** `Small`, `Default`, `Large`

### Kbd
Keyboard shortcut display component

```razor
<p>Press <Kbd>⌘</Kbd> + <Kbd>K</Kbd> to open command palette</p>
<p>Save with <Kbd>Ctrl</Kbd> + <Kbd>S</Kbd></p>
```

### Data Table
Powerful table with sorting, filtering, pagination, row selection - see components-forms.md

---

## Overlay Best Practices

### AsChild Pattern

Use `AsChild` with styled Button components as triggers:

```razor
<Dialog>
    <DialogTrigger AsChild>
        <Button Variant="destructive">Delete</Button>
    </DialogTrigger>
    <DialogContent>
        <!-- Dialog content -->
    </DialogContent>
</Dialog>
```

### Confirmation Dialogs

```razor
<AlertDialog>
    <AlertDialogTrigger AsChild>
        <Button Variant="destructive">Delete Account</Button>
    </AlertDialogTrigger>
    <AlertDialogContent>
        <AlertDialogHeader>
            <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
            <AlertDialogDescription>
                This action cannot be undone.
            </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction>Delete</AlertDialogAction>
        </AlertDialogFooter>
    </AlertDialogContent>
</AlertDialog>
```

### Context-Aware Menus

```razor
<DropdownMenu>
    <DropdownMenuTrigger AsChild>
        <Button Size="icon" Variant="ghost">
            <LucideIcon Name="more-horizontal" Size="16" />
        </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent>
        <DropdownMenuItem OnClick="Edit">
            <LucideIcon Name="edit" Size="16" />
            Edit
        </DropdownMenuItem>
        <DropdownMenuItem OnClick="Duplicate">
            <LucideIcon Name="copy" Size="16" />
            Duplicate
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem OnClick="Delete" Class="text-destructive">
            <LucideIcon Name="trash" Size="16" />
            Delete
        </DropdownMenuItem>
    </DropdownMenuContent>
</DropdownMenu>
```
