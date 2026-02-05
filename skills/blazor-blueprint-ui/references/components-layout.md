# Layout & Navigation Components Reference

Reference for all layout and navigation components in BlazorBlueprint.

**Source Component Docs:** https://blazorblueprintui.com/llms/components/

---

## Navigation Components

### Navigation Menu
Horizontal navigation with dropdown menus for site-wide navigation. Includes ResponsiveNav components for mobile.

```razor
<NavigationMenu>
    <NavigationMenuItem>
        <NavigationMenuTrigger>Products</NavigationMenuTrigger>
        <NavigationMenuContent>
            <NavigationMenuLink Href="/products/item1">Item 1</NavigationMenuLink>
            <NavigationMenuLink Href="/products/item2">Item 2</NavigationMenuLink>
        </NavigationMenuContent>
    </NavigationMenuItem>
    <NavigationMenuItem>
        <NavigationMenuLink Href="/about">About</NavigationMenuLink>
    </NavigationMenuItem>
</NavigationMenu>
```

**Features:** Dropdown menus, opt-in keyboard navigation (`EnableKeyboardNavigation="true"`), auto-close on navigation

### Sidebar
Responsive navigation sidebar with collapsible menus and keyboard shortcuts (Ctrl/Cmd+B)

```razor
<SidebarProvider>
    <Sidebar>
        <SidebarHeader>
            <SidebarHeaderContent>
                <div class="flex items-center space-x-2">
                    <LucideIcon Name="zap" Size="20" />
                    <span class="font-bold">My App</span>
                </div>
            </SidebarHeaderContent>
        </SidebarHeader>
        
        <SidebarContent>
            <SidebarMenu>
                <SidebarMenuItem>
                    <SidebarMenuButton Href="/">
                        <LucideIcon Name="home" Size="16" />
                        <span>Dashboard</span>
                    </SidebarMenuButton>
                </SidebarMenuItem>
            </SidebarMenu>
        </SidebarContent>
        
        <SidebarFooter>
            <!-- User menu -->
        </SidebarFooter>
    </Sidebar>
    
    <SidebarInset>
        <main>@Body</main>
    </SidebarInset>
</SidebarProvider>
```

### Responsive Nav
Mobile-friendly navigation with hamburger trigger and Sheet-based mobile content

```razor
<ResponsiveNavProvider>
    <ResponsiveNavTrigger />
    <ResponsiveNavContent>
        <!-- Mobile navigation content -->
    </ResponsiveNavContent>
</ResponsiveNavProvider>
```

### Breadcrumb
Navigation trail showing hierarchical location

```razor
<Breadcrumb>
    <BreadcrumbList>
        <BreadcrumbItem>
            <BreadcrumbLink Href="/">Home</BreadcrumbLink>
        </BreadcrumbItem>
        <BreadcrumbSeparator />
        <BreadcrumbItem>
            <BreadcrumbLink Href="/products">Products</BreadcrumbLink>
        </BreadcrumbItem>
        <BreadcrumbSeparator />
        <BreadcrumbItem>
            <BreadcrumbPage>Current Page</BreadcrumbPage>
        </BreadcrumbItem>
    </BreadcrumbList>
</Breadcrumb>
```

### Pagination
Page navigation with previous/next controls and state management

```razor
<Pagination State="@paginationState">
    <div class="flex w-full items-center justify-between py-4">
        <PaginationInfo />
        
        <PaginationContent>
            <PaginationItem><PaginationFirst /></PaginationItem>
            <PaginationItem><PaginationPrevious ShowText="false" /></PaginationItem>
            <PaginationItem><PaginationPageDisplay /></PaginationItem>
            <PaginationItem><PaginationNext ShowText="false" /></PaginationItem>
            <PaginationItem><PaginationLast /></PaginationItem>
        </PaginationContent>
        
        <PaginationPageSizeSelector />
    </div>
</Pagination>
```

---

## Layout Components

### Card
Container component with header, body, and footer sections

```razor
<Card>
    <CardHeader>
        <CardTitle>Card Title</CardTitle>
        <CardDescription>Card description</CardDescription>
    </CardHeader>
    <CardContent>
        <!-- Card content -->
    </CardContent>
    <CardFooter>
        <Button>Action</Button>
    </CardFooter>
</Card>
```

### Accordion
Collapsible content sections with smooth animations

```razor
<Accordion Type="AccordionType.Single" Collapsible="true">
    <AccordionItem Value="item1">
        <AccordionTrigger>Section 1</AccordionTrigger>
        <AccordionContent>
            Content for section 1
        </AccordionContent>
    </AccordionItem>
    <AccordionItem Value="item2">
        <AccordionTrigger>Section 2</AccordionTrigger>
        <AccordionContent>
            Content for section 2
        </AccordionContent>
    </AccordionItem>
</Accordion>
```

### Tabs
Tabbed interface for organizing related content

```razor
<Tabs DefaultValue="tab1">
    <TabsList>
        <TabsTrigger Value="tab1">Tab 1</TabsTrigger>
        <TabsTrigger Value="tab2">Tab 2</TabsTrigger>
    </TabsList>
    
    <TabsContent Value="tab1">
        Content for tab 1
    </TabsContent>
    <TabsContent Value="tab2">
        Content for tab 2
    </TabsContent>
</Tabs>
```

### Collapsible
Expandable content area with trigger control

```razor
<Collapsible>
    <CollapsibleTrigger AsChild>
        <Button>
            <LucideIcon Name="chevron-down" Size="16" />
            Toggle Content
        </Button>
    </CollapsibleTrigger>
    <CollapsibleContent>
        <!-- Hidden content -->
    </CollapsibleContent>
</Collapsible>
```

### Separator
Visual divider for content sections

```razor
<Separator Orientation="horizontal" />
<Separator Orientation="vertical" Class="h-6" />
```

### Scroll Area
Custom scrollable area with styled scrollbars

```razor
<ScrollArea Class="h-96 w-full">
    <!-- Scrollable content -->
</ScrollArea>
```

### Aspect Ratio
Container that maintains specified aspect ratio (16:9, 4:3, 1:1, etc.)

```razor
<AspectRatio Ratio="16/9">
    <img src="image.jpg" alt="Image" class="object-cover" />
</AspectRatio>
```

### Resizable
Resizable panel layout with draggable handles and min/max constraints

```razor
<ResizablePanelGroup Orientation="horizontal">
    <ResizablePanel DefaultSize="50" MinSize="30">
        Left panel
    </ResizablePanel>
    <ResizableHandle />
    <ResizablePanel DefaultSize="50" MinSize="30">
        Right panel
    </ResizablePanel>
</ResizablePanelGroup>
```

---

## Display Components

### Carousel
Slideshow component for cycling through content

```razor
<Carousel>
    <CarouselContent>
        <CarouselItem>Slide 1</CarouselItem>
        <CarouselItem>Slide 2</CarouselItem>
        <CarouselItem>Slide 3</CarouselItem>
    </CarouselContent>
    <CarouselPrevious />
    <CarouselNext />
</Carousel>
```

### Item
Flexible list item component with media (avatar/icon), content, and action areas

```razor
<Item>
    <ItemMedia>
        <Avatar>
            <AvatarImage Src="user.jpg" />
            <AvatarFallback>JD</AvatarFallback>
        </Avatar>
    </ItemMedia>
    <ItemContent>
        <ItemTitle>John Doe</ItemTitle>
        <ItemDescription>Software Engineer</ItemDescription>
    </ItemContent>
    <ItemAction>
        <Button Size="icon" Variant="ghost">
            <LucideIcon Name="more-horizontal" Size="16" />
        </Button>
    </ItemAction>
</Item>
```

### Toggle Group
Group of toggles with single or multiple selection

```razor
<ToggleGroup Type="single" @bind-Value="alignment">
    <ToggleGroupItem Value="left" AriaLabel="Align left">
        <LucideIcon Name="align-left" Size="16" />
    </ToggleGroupItem>
    <ToggleGroupItem Value="center" AriaLabel="Align center">
        <LucideIcon Name="align-center" Size="16" />
    </ToggleGroupItem>
    <ToggleGroupItem Value="right" AriaLabel="Align right">
        <LucideIcon Name="align-right" Size="16" />
    </ToggleGroupItem>
</ToggleGroup>
```

### Typography
Pre-styled typography components for consistent text rendering

```razor
<TypographyH1>Heading 1</TypographyH1>
<TypographyH2>Heading 2</TypographyH2>
<TypographyH3>Heading 3</TypographyH3>
<TypographyH4>Heading 4</TypographyH4>
<TypographyP>Paragraph text</TypographyP>
<TypographyLead>Lead text</TypographyLead>
<TypographyLarge>Large text</TypographyLarge>
<TypographySmall>Small text</TypographySmall>
<TypographyMuted>Muted text</TypographyMuted>
<TypographyBlockquote>Quote text</TypographyBlockquote>
<TypographyInlineCode>code</TypographyInlineCode>
```

---

## Field Component

Combines labels, controls, help text, and error messages for accessible forms

```razor
<Field>
    <FieldLabel>Email Address</FieldLabel>
    <FieldContent>
        <Input @bind-Value="email" Type="email" />
    </FieldContent>
    <FieldDescription>
        We'll never share your email with anyone else.
    </FieldDescription>
    <FieldError>
        <ValidationMessage For="@(() => email)" />
    </FieldError>
</Field>
```

---

## Layout Best Practices

### Responsive Sidebar Navigation

Use SidebarProvider for full sidebar functionality:

```razor
<SidebarProvider>
    <Sidebar>
        <!-- Sidebar content -->
    </Sidebar>
    <SidebarInset>
        <header class="flex h-16 items-center gap-2 border-b px-4">
            <SidebarTrigger />
            <Separator Orientation="vertical" Class="h-6" />
            <h1>@pageTitle</h1>
        </header>
        <main class="flex-1 p-6">
            @Body
        </main>
    </SidebarInset>
</SidebarProvider>
```

### Card Composition

```razor
<div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
    <Card>
        <CardHeader>
            <CardTitle>Revenue</CardTitle>
            <CardDescription>This month</CardDescription>
        </CardHeader>
        <CardContent>
            <p class="text-2xl font-bold">$45,231</p>
        </CardContent>
    </Card>
    <!-- More cards -->
</div>
```

### Tabbed Settings Page

```razor
<Tabs DefaultValue="profile">
    <TabsList>
        <TabsTrigger Value="profile">Profile</TabsTrigger>
        <TabsTrigger Value="account">Account</TabsTrigger>
        <TabsTrigger Value="notifications">Notifications</TabsTrigger>
    </TabsList>
    
    <TabsContent Value="profile">
        <Card>
            <CardHeader>
                <CardTitle>Profile Settings</CardTitle>
            </CardHeader>
            <CardContent>
                <!-- Profile form -->
            </CardContent>
        </Card>
    </TabsContent>
    <!-- Other tab contents -->  
</Tabs>
```
