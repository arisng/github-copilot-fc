# API Reference: tldraw-creator

Complete reference for programmatic board creation, shapes, bindings, and API endpoints.

## Document Structure

### Top-Level Schema

```typescript
interface TLDrawDocument {
  version: number;           // Document format version (e.g., 15)
  document: TLDocument;
}

interface TLDocument {
  id: string;                // Unique document ID (e.g., "doc_abc123")
  pages: Record<string, TLPage>;
  assets: Record<string, TLAsset>;
  pageStates: Record<string, TLPageState>;
}

interface TLPage {
  id: string;                // Page ID (e.g., "page_abc123")
  name: string;              // Display name (e.g., "Page 1")
  shapes: Record<string, TLShape>;
  bindings: Record<string, TLBinding>;
}
```

## Shapes

All shapes share these common properties:

```typescript
interface TLShape {
  id: TLShapeId;             // Unique shape ID (e.g., "shape_abc123")
  type: string;              // Shape type (geo, text, arrow, frame, image, note, bookmark)
  x: number;                 // X position (pixels)
  y: number;                 // Y position (pixels)
  rotation: number;          // Rotation in radians (0-2π)
  props: Record<string, any>; // Type-specific properties
}
```

### Shape Types

#### 1. Geo Shape

Used for rectangles, ellipses, diamonds, triangles, and other geometric shapes.

> **tldraw 3.x**: label text is `richText` (ProseMirror document), **not** `text`.

```typescript
interface TLGeoShape extends TLShape {
  type: 'geo';
  props: {
    w: number;               // Width (pixels)
    h: number;               // Height (pixels)
    geo: 'rectangle' | 'ellipse' | 'diamond' | 'triangle' | 'line' | 'pentagon' | 'hexagon';
    fill: 'solid' | 'pattern' | 'semi' | 'none';
    color: string;           // Color name (blue, red, green, yellow, orange, violet, etc.)
    dash: 'draw' | 'dashed' | 'dotted' | 'solid';
    size: 's' | 'm' | 'l' | 'xl';
    richText: TLRichText;    // Label text (tldraw 3.x) — use toRichText(str) helper
    align: 'start' | 'middle' | 'end';
    verticalAlign: 'start' | 'middle' | 'end';
    font: 'draw' | 'sans' | 'serif' | 'mono';
    labelColor: string;      // Label text color
  };
}

// TLRichText is a ProseMirror document:
type TLRichText = {
  type: 'doc';
  content: Array<{ type: 'paragraph'; content?: Array<{ type: 'text'; text: string }> }>;
}
```

**Example**: Create a blue rectangle with label:

```typescript
import { toRichText } from 'tldraw'

{
  id: 'shape_1',
  type: 'geo',
  x: 100,
  y: 100,
  rotation: 0,
  props: {
    w: 200,
    h: 100,
    geo: 'rectangle',
    fill: 'solid',
    color: 'blue',
    richText: toRichText('Frontend Service'),
    align: 'middle',
    verticalAlign: 'middle'
  }
}
```

#### 2. Text Shape

Standalone text box.

> **tldraw 3.x**: text content is `richText`, alignment prop is `textAlign` (not `align`).

```typescript
interface TLTextShape extends TLShape {
  type: 'text';
  props: {
    richText: TLRichText;    // Text content — use toRichText(str)
    color: string;           // Text color
    size: 's' | 'm' | 'l' | 'xl';
    textAlign: 'start' | 'middle' | 'end';  // NOTE: 'textAlign', not 'align'
    font: 'draw' | 'sans' | 'serif' | 'mono';
    w: number;               // Width
    autoSize: boolean;       // Auto-resize to fit text
    scale: number;           // Text scale (default 1)
  };
}
```

**Example**: Create a text label:

```typescript
import { toRichText } from 'tldraw'

{
  id: 'shape_2',
  type: 'text',
  x: 150,
  y: 250,
  rotation: 0,
  props: {
    richText: toRichText('Component Label'),
    color: 'black',
    size: 'm',
    textAlign: 'start',
    autoSize: true,
    w: 200,
  }
}
```

#### 3. Arrow Shape

Connector between shapes or standalone line with arrow.

> **tldraw 3.x**: `start`/`end` are plain `{ x, y }` points when not bound to shapes. Use `arrowheadStart`/`arrowheadEnd` for head style.

```typescript
interface TLArrowShape extends TLShape {
  type: 'arrow';
  props: {
    start: { x: number; y: number };  // Absolute position when unbound
    end: { x: number; y: number };
    bend: number;            // Curvature (0 = straight)
    dash: 'draw' | 'dashed' | 'dotted' | 'solid';
    size: 's' | 'm' | 'l' | 'xl';
    color: string;
    labelColor: string;
    arrowheadStart: 'none' | 'arrow' | 'triangle' | 'square' | 'dot' | 'pipe' | 'diamond';
    arrowheadEnd: 'none' | 'arrow' | 'triangle' | 'square' | 'dot' | 'pipe' | 'diamond';
    richText: TLRichText;    // Label on arrow
    font: string;
    fill: string;
  };
}
```

**Example**: Create arrow between two absolute points:

```typescript
import { toRichText } from 'tldraw'

{
  id: 'shape_arrow_1',
  type: 'arrow',
  x: 0,
  y: 0,
  rotation: 0,
  props: {
    start: { x: 300, y: 150 },
    end:   { x: 500, y: 150 },
    bend: 0,
    dash: 'solid',
    color: 'black',
    arrowheadStart: 'none',
    arrowheadEnd: 'arrow',
    richText: toRichText(''),
    font: 'sans',
    fill: 'none',
    labelColor: 'black',
  }
}
```

#### 4. Frame Shape

Container for organizing shapes (like artboards).

```typescript
interface TLFrameShape extends TLShape {
  type: 'frame';
  props: {
    w: number;
    h: number;
    name: string;
  };
}
```

#### 5. Image Shape

Embedded image asset.

```typescript
interface TLImageShape extends TLShape {
  type: 'image';
  props: {
    w: number;
    h: number;
    assetId: string;         // Reference to asset
    name: string;
  };
}
```

## Bindings

Bindings define relationships between shapes (e.g., arrows connected to shapes).

```typescript
interface TLBinding {
  id: string;                // Binding ID
  type: string;              // 'arrow' | 'frame_child'
  fromId: TLShapeId;         // Source shape
  toId: TLShapeId;           // Target shape
  props: Record<string, any>;
}
```

**Example**: Arrow binding:

```typescript
{
  id: 'binding_1',
  type: 'arrow',
  fromId: 'shape_1',
  toId: 'shape_2',
  props: {
    end: 'arrow',
    start: 'none'
  }
}
```

## Assets

Images, fonts, and other media embedded in the document.

```typescript
interface TLAsset {
  id: string;
  type: 'image' | 'video';
  typeName: string;
  src: string;               // Base64-encoded data or URL
  width: number;
  height: number;
  mimeType: string;
}
```

## Colors

Available color names in tldraw:

- `black`
- `blue`
- `green`
- `orange`
- `purple`
- `red`
- `yellow`
- `pink`
- `violet`
- `gray`

## Tool Script Usage

### create-board.js

Create a `.tldraw` file programmatically.

```bash
# With inline shapes JSON
# NOTE: richText must be a ProseMirror document; use the rt() helper in your scripts
node create-board.js \
  --name "my-diagram" \
  --title "My Diagram" \
  --config config.json

# With config file
node create-board.js \
  --name "architecture" \
  --config config.json
```

**config.json format** (simplified skill input schema — converted to `richText` at runtime):

```json
{
  "title": "System Architecture",
  "shapes": [
    {
      "type": "geo",
      "x": 100,
      "y": 100,
      "props": {
        "w": 200,
        "h": 100,
        "geo": "rectangle",
        "color": "blue",
        "text": "Frontend"
      }
    }
  ]
}
```

### deploy-server.js

Set up a self-hosted tldraw server.

```bash
# Docker deployment
node deploy-server.js --type docker --port 3000

# Node.js deployment
node deploy-server.js --type nodejs --port 3000
```

### import-board.js

Import a board to a running server.

```bash
# Import from .tldraw file
node import-board.js \
  --server http://localhost:3000 \
  --board my-diagram.tldraw \
  --name "My Diagram"

# Import from JSON
node import-board.js \
  --server http://localhost:3000 \
  --json board-data.json
```

### list-boards.js

List all boards on a server.

```bash
# JSON format (default)
node list-boards.js --server http://localhost:3000

# Table format
node list-boards.js --server http://localhost:3000 --format table

# With limit
node list-boards.js --server http://localhost:3000 --limit 10
```

## API Endpoints (Self-Hosted Server)

These endpoints are provided by a self-hosted tldraw server.

### Health Check

```
GET /health
Response: { "status": "ok", "timestamp": "2026-04-26T12:00:00Z" }
```

### List Documents

```
GET /api/documents?limit=20&offset=0
Response: [
  {
    "id": "doc_abc123",
    "name": "Board Name",
    "createdAt": "2026-04-26T12:00:00Z",
    "updatedAt": "2026-04-26T14:00:00Z"
  }
]
```

### Import Document

```
POST /api/documents/import
Body: {
  "id": "doc_abc123",
  "name": "Board Name",
  "data": { /* TLDraw document */ }
}
Response: {
  "success": true,
  "boardId": "doc_abc123",
  "viewUrl": "http://localhost:3000/room/doc_abc123"
}
```

### Get Document

```
GET /api/documents/:id
Response: { /* TLDraw document */ }
```

### Export Document

```
GET /api/documents/:id/export?format=json|svg|png
Response: Binary data or JSON
```

## Troubleshooting

### Invalid Shape ID Format

Shape IDs must follow the pattern: `shape_<alphanum>` (e.g., `shape_abc123`)

### Missing Required Props

Common props missing from shapes:
- `w` (width) for geo shapes
- `h` (height) for geo shapes
- `geo` type selector for geo shapes (rectangle, ellipse, diamond, etc.)
- `text` for labeled shapes

### Circular Bindings

Avoid creating arrow loops that point to themselves (not supported).

### Large Documents

Documents with thousands of shapes may experience performance issues. Consider splitting into multiple pages.

## Resources

- [tldraw GitHub](https://github.com/tldraw/tldraw)
- [tldraw Store Package](https://www.npmjs.com/package/@tldraw/store)
- [TypeScript Schema](https://github.com/tldraw/tldraw/tree/main/packages/tlschema)
