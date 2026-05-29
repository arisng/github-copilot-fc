# Shape Reference: tldraw Drawing Types

Complete guide to all shape types available in tldraw with examples and properties.

## Overview

tldraw supports a rich set of shape types for creating diverse diagrams:

| Shape | Use Case | Example |
|-------|----------|---------|
| Geo | Diagrams, flowcharts, containers | Rectangles, circles, diamonds |
| Text | Labels, annotations | Titles, notes, captions |
| Arrow | Connections, flows | Relationships, data flow |
| Frame | Organization, grouping | Swimlanes, artboards, sections |
| Image | Visual content | Photos, logos, diagrams |
| Note | Quick ideas | Sticky notes, reminders |
| Bookmark | References | Links to external pages |

---

## Geo Shapes

Geometric shapes with customizable properties. Most versatile shape type.

### Properties

```typescript
interface GeoShapeProps {
  w: number;                           // Width (pixels)
  h: number;                           // Height (pixels)
  geo: 'rectangle' | 'ellipse' | 'diamond' | 'triangle' | 'line' | 'pentagon' | 'hexagon' | 'star';
  fill: 'solid' | 'pattern' | 'none';
  color: string;                       // Color name
  opacityForShape: number;             // 0-1
  dash: 'draw' | 'dashed' | 'dotted' | 'solid';
  size: 's' | 'm' | 'l' | 'xl';
  text: string;                        // Label inside shape
  align: 'start' | 'middle' | 'end';
  verticalAlign: 'start' | 'middle' | 'end';
  font: 'draw' | 'sans' | 'serif' | 'mono';
}
```

### Geo Types

#### Rectangle

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 200, h: 100,
    geo: 'rectangle',
    fill: 'solid',
    color: 'blue',
    text: 'Frontend'
  }
}
```

**Use Cases**: Components, containers, swimlanes, nodes in flowcharts

#### Ellipse/Circle

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 100, h: 100,
    geo: 'ellipse',
    fill: 'solid',
    color: 'red',
    text: 'Start',
    align: 'middle',
    verticalAlign: 'middle'
  }
}
```

**Use Cases**: Process start/end nodes, highlights, emphasis

#### Diamond

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 120, h: 120,
    geo: 'diamond',
    fill: 'solid',
    color: 'orange',
    text: 'Decision?'
  }
}
```

**Use Cases**: Decision points in flowcharts, conditionals

#### Triangle

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 100, h: 100,
    geo: 'triangle',
    fill: 'solid',
    color: 'green'
  }
}
```

**Use Cases**: Direction indicators, warnings, caution

#### Pentagon/Hexagon

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 100, h: 100,
    geo: 'pentagon',
    fill: 'solid',
    color: 'purple'
  }
}
```

**Use Cases**: Complex diagrams, process stages

#### Line

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 200, h: 2,
    geo: 'line',
    color: 'black',
    dash: 'solid'
  }
}
```

**Use Cases**: Separators, dividers, visual organization

#### Star

```typescript
{
  type: 'geo',
  x: 100, y: 100,
  props: {
    w: 100, h: 100,
    geo: 'star',
    fill: 'solid',
    color: 'yellow'
  }
}
```

**Use Cases**: Important items, highlights, favorites

---

## Text Shape

Standalone text boxes for labels, annotations, and notes.

### Properties

```typescript
interface TextShapeProps {
  text: string;                  // Text content
  color: string;                 // Text color
  size: 's' | 'm' | 'l' | 'xl';
  align: 'start' | 'middle' | 'end';
  font: 'draw' | 'sans' | 'serif' | 'mono';
  opacityForShape: number;       // 0-1
}
```

### Examples

**Title Text**:

```typescript
{
  type: 'text',
  x: 50, y: 20,
  props: {
    text: 'System Architecture',
    size: 'xl',
    align: 'start',
    color: 'black',
    font: 'sans'
  }
}
```

**Code Block**:

```typescript
{
  type: 'text',
  x: 100, y: 200,
  props: {
    text: 'const result = await fn();',
    size: 's',
    font: 'mono',
    color: 'black'
  }
}
```

**Annotation**:

```typescript
{
  type: 'text',
  x: 250, y: 350,
  props: {
    text: 'This is a critical path',
    size: 's',
    align: 'start',
    color: 'orange',
    font: 'sans'
  }
}
```

---

## Arrow Shape

Connectors between shapes or standalone arrows. Essential for flowcharts and diagrams.

### Properties

```typescript
interface ArrowShapeProps {
  start: ArrowPoint;             // Start position/binding
  end: ArrowPoint;               // End position/binding
  bend: number;                  // Curvature (0 = straight)
  dash: 'draw' | 'dashed' | 'dotted' | 'solid';
  size: 's' | 'm' | 'l' | 'xl';
  color: string;
  text: string;                  // Label on arrow
}

type ArrowPoint = 
  | { type: 'point'; x: number; y: number }
  | { type: 'binding'; boundShapeId: string; normalizedAnchor: { x: number; y: number } };
```

### Arrow Point Types

#### Free-form Point

Arrow starts/ends at absolute coordinates:

```typescript
{
  type: 'arrow',
  x: 0, y: 0,
  props: {
    start: { type: 'point', x: 100, y: 100 },
    end: { type: 'point', x: 300, y: 300 },
    dash: 'solid',
    color: 'black'
  }
}
```

#### Binding to Shape

Arrow connects to another shape:

```typescript
{
  type: 'arrow',
  x: 0, y: 0,
  props: {
    start: { type: 'binding', boundShapeId: 'shape_1', normalizedAnchor: { x: 1, y: 0.5 } },
    end: { type: 'binding', boundShapeId: 'shape_2', normalizedAnchor: { x: 0, y: 0.5 } },
    color: 'blue',
    text: 'connects'
  }
}
```

**Normalized Anchor Positions**:
- `{ x: 0, y: 0.5 }`: Left center
- `{ x: 1, y: 0.5 }`: Right center
- `{ x: 0.5, y: 0 }`: Top center
- `{ x: 0.5, y: 1 }`: Bottom center
- `{ x: 0, y: 0 }`: Top-left corner
- `{ x: 1, y: 1 }`: Bottom-right corner

### Arrow Styles

**Straight Arrow**:

```typescript
{
  type: 'arrow',
  x: 0, y: 0,
  props: {
    start: { type: 'binding', boundShapeId: 'shape_1', normalizedAnchor: { x: 1, y: 0.5 } },
    end: { type: 'binding', boundShapeId: 'shape_2', normalizedAnchor: { x: 0, y: 0.5 } },
    bend: 0,
    dash: 'solid'
  }
}
```

**Curved Arrow**:

```typescript
{
  type: 'arrow',
  x: 0, y: 0,
  props: {
    start: { type: 'binding', boundShapeId: 'shape_1', normalizedAnchor: { x: 1, y: 0.5 } },
    end: { type: 'binding', boundShapeId: 'shape_2', normalizedAnchor: { x: 0, y: 0.5 } },
    bend: 0.3,  // Positive = curve up, negative = curve down
    dash: 'solid'
  }
}
```

**Dashed Arrow**:

```typescript
{
  type: 'arrow',
  x: 0, y: 0,
  props: {
    start: { type: 'binding', boundShapeId: 'shape_1', normalizedAnchor: { x: 1, y: 0.5 } },
    end: { type: 'binding', boundShapeId: 'shape_2', normalizedAnchor: { x: 0, y: 0.5 } },
    dash: 'dashed',
    color: 'gray'
  }
}
```

---

## Frame Shape

Container/artboard for grouping and organizing shapes (like Figma frames).

### Properties

```typescript
interface FrameShapeProps {
  w: number;
  h: number;
  name: string;
}
```

### Example

**Swimlane Frame**:

```typescript
{
  type: 'frame',
  x: 0, y: 0,
  props: {
    w: 400, h: 300,
    name: 'User Flow'
  }
}
```

**Use Cases**: Swimlanes in process diagrams, grouping related components, artboards

---

## Image Shape

Embedded or linked images within a diagram.

### Properties

```typescript
interface ImageShapeProps {
  w: number;
  h: number;
  assetId: string;              // Reference to asset in document
  name: string;
}
```

### Example

```typescript
{
  type: 'image',
  x: 100, y: 100,
  props: {
    w: 200, h: 150,
    assetId: 'asset_logo',
    name: 'Logo'
  }
}
```

---

## Note Shape

Sticky note for quick ideas and reminders.

### Properties

```typescript
interface NoteShapeProps {
  text: string;
  color: string;               // Note color
  align: 'start' | 'middle' | 'end';
  font: 'draw' | 'sans' | 'serif' | 'mono';
}
```

### Example

```typescript
{
  type: 'note',
  x: 100, y: 100,
  props: {
    text: 'Remember to test this component',
    color: 'yellow'
  }
}
```

---

## Bookmark Shape

Reference to external content (web links, articles, resources).

### Properties

```typescript
interface BookmarkShapeProps {
  url: string;
  assetId: string;             // Preview image asset
}
```

### Example

```typescript
{
  type: 'bookmark',
  x: 100, y: 100,
  props: {
    url: 'https://example.com/api-docs',
    assetId: 'asset_bookmark_preview'
  }
}
```

---

## Color Palette

Available colors for shapes and text:

```
Primary Colors:
  - blue
  - red
  - green
  - yellow
  - orange
  - purple

Extended Colors:
  - pink
  - violet
  - gray
  - black
  - white (for backgrounds)

Recommended Combinations:
  - blue + green: Technical diagrams
  - orange + purple: Design systems
  - red + yellow: Warnings, alerts
  - blue + gray: Neutral, professional
```

---

## Common Patterns

### Flowchart

```typescript
// Decision diamond → Yes arrow → Success circle → No arrow → Error diamond

shapes: [
  {
    type: 'geo', x: 100, y: 100,
    props: { w: 100, h: 100, geo: 'diamond', color: 'orange', text: 'Check?' }
  },
  {
    type: 'geo', x: 50, y: 300,
    props: { w: 100, h: 100, geo: 'ellipse', color: 'green', text: 'Success' }
  },
  {
    type: 'geo', x: 250, y: 300,
    props: { w: 100, h: 100, geo: 'ellipse', color: 'red', text: 'Error' }
  }
]
```

### Swimlane

```typescript
// Three frames for different actors/systems
shapes: [
  { type: 'frame', x: 0, y: 0, props: { w: 300, h: 400, name: 'User' } },
  { type: 'frame', x: 300, y: 0, props: { w: 300, h: 400, name: 'Backend' } },
  { type: 'frame', x: 600, y: 0, props: { w: 300, h: 400, name: 'Database' } }
]
```

### Entity-Relationship

```typescript
// Rectangles for entities, arrows for relationships
shapes: [
  { type: 'geo', x: 100, y: 100, props: { w: 150, h: 80, geo: 'rectangle', color: 'blue', text: 'Users' } },
  { type: 'geo', x: 400, y: 100, props: { w: 150, h: 80, geo: 'rectangle', color: 'green', text: 'Orders' } },
  { type: 'arrow', props: { ... } }  // Relationship
]
```

---

## Best Practices

1. **Use consistent colors** for similar concept types (e.g., all services blue, all databases green)
2. **Label everything** - Add descriptive text to shapes
3. **Use appropriate shapes** - Diamond for decisions, circles for start/end
4. **Group with frames** - Use frames to organize related components
5. **Keep arrows clear** - Use straight arrows for clarity, curves for aesthetics
6. **Size proportionally** - Larger/important shapes can be bigger
7. **Limit text** - Keep labels concise; detailed notes go in comments
8. **Use white space** - Don't clutter; leave breathing room between elements
