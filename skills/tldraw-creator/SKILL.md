---
name: tldraw-creator
description: Programmatically create tldraw whiteboards and visualize them with a self-hosted tldraw instance. Create boards with shapes, text, and connectors, then deploy to a self-hosted server for collaborative editing and gallery management.
metadata:
  version: 0.1.0
  author: arisng
  tags:
    - visualization
    - whiteboarding
    - diagramming
    - tldraw
    - self-hosted
env: node
---

# tldraw-creator Skill

Create and manage tldraw whiteboards programmatically, deploy self-hosted instances, and build collaborative whiteboarding workflows.

## Overview

tldraw-creator enables agents to:
- **Create whiteboards programmatically** using the `@tldraw/store` API (shapes, text, connectors, frames)
- **Deploy self-hosted instances** via Docker or Node.js with PostgreSQL persistence
- **Import/export boards** as `.tldraw` JSON documents
- **Manage board galleries** and enable collaborative editing
- **Visualize diagrams** directly in whiteboards with custom shapes and layouts

## Prerequisites

- **Node.js 18+** (for programmatic board creation)
- **Docker** (optional, for self-hosted server deployment)
- **PostgreSQL 12+** (optional, for persistent document storage)
- **npm** (for installing `@tldraw` packages)

## Setup

### Install tldraw Packages

> **Note**: As of tldraw 3.x all tldraw functionality is bundled in the single `tldraw` package. The individual `@tldraw/store`, `@tldraw/tlschema`, `@tldraw/ui`, and `@tldraw/editor` sub-packages are still available but the `tldraw` meta-package is the recommended entry point.

```bash
# Recommended: single package (tldraw 3.x)
npm install tldraw react react-dom

# Optional: individual sub-packages for advanced use
npm install @tldraw/store @tldraw/tlschema
npm install pg yjs y-websocket  # For server + persistence
npm install express cors         # For API server (optional)
```

### Vite / ESM Setup

tldraw ships dual CJS/ESM code. When using Vite, add `lodash.isequalwith` to `optimizeDeps.include` to avoid a missing-default-export error at runtime:

```js
// vite.config.js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  optimizeDeps: {
    include: ['lodash.isequalwith', 'lodash.isequal'],
  },
})
```

### Environment Variables

Create `.env` file in your skill workspace root or pass as process variables:

```env
# Programmatic Board Creation
TLDRAW_EXPORT_FORMAT=json          # json | svg | png (default: json)

# Self-Hosted Server
TLDRAW_SERVER_PORT=3000
TLDRAW_DATABASE_URL=postgresql://user:password@localhost:5432/tldraw
TLDRAW_WEBSOCKET_URL=wss://tldraw.example.com
TLDRAW_NODE_ENV=development        # development | production

# Optional: Cloud Storage
TLDRAW_S3_BUCKET=my-tldraw-boards
TLDRAW_S3_REGION=us-east-1
```

## Tool Calling Pattern

### Tool: Create Board

**Purpose**: Programmatically generate a tldraw whiteboard with shapes, text, and connectors.

**Input Schema**:
```json
{
  "name": "my-board",
  "title": "Project Architecture",
  "shapes": [
    {
      "id": "shape-1",
      "type": "geo",
      "x": 100,
      "y": 100,
      "props": {
        "w": 200,
        "h": 100,
        "geo": "rectangle",
        "color": "blue",
        "richText": { "type": "doc", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Frontend" }] }] }
      }
    }
  ],
  "theme": "dark"
}
```

> **tldraw 3.x**: shape labels use `richText` (ProseMirror document), **not** `text`. Use `toRichText(str)` from the `tldraw` package to convert plain strings.

**Output Schema**:
```json
{
  "success": true,
  "boardId": "doc_abc123",
  "boardName": "my-board",
  "exportPath": "/path/to/my-board.tldraw",
  "boardJson": { "/* TLStore snapshot */" }
}
```

**Implementation**: See `scripts/create-board.js`

### Tool: Deploy Server

**Purpose**: Set up a self-hosted tldraw instance for visualization and collaboration.

**Input Schema**:
```json
{
  "deploymentType": "docker",
  "persistenceType": "postgresql",
  "databaseUrl": "postgresql://tldraw:password@localhost:5432/tldraw",
  "serverPort": 3000,
  "enableWebSocket": true
}
```

**Output Schema**:
```json
{
  "success": true,
  "serverUrl": "http://localhost:3000",
  "status": "running",
  "containerName": "tldraw-server",
  "logs": "Server started..."
}
```

**Implementation**: See `scripts/deploy-server.js`

### Tool: Import Board to Server

**Purpose**: Upload a board JSON to a running self-hosted instance and get a visualization URL.

**Input Schema**:
```json
{
  "serverUrl": "http://localhost:3000",
  "boardJson": { "/* TLStore snapshot */" },
  "boardName": "my-board"
}
```

**Output Schema**:
```json
{
  "success": true,
  "boardId": "doc_abc123",
  "viewUrl": "http://localhost:3000/room/doc_abc123",
  "editUrl": "http://localhost:3000/edit/doc_abc123"
}
```

**Implementation**: See `scripts/import-board.js`

### Tool: List Boards

**Purpose**: Get a list of all boards on a self-hosted instance (for gallery/management).

**Input Schema**:
```json
{
  "serverUrl": "http://localhost:3000",
  "limit": 20,
  "sortBy": "created_at"
}
```

**Output Schema**:
```json
{
  "success": true,
  "boards": [
    {
      "id": "doc_abc123",
      "name": "Project Architecture",
      "createdAt": "2026-04-26T12:00:00Z",
      "updatedAt": "2026-04-26T14:30:00Z",
      "url": "http://localhost:3000/room/doc_abc123"
    }
  ]
}
```

**Implementation**: See `scripts/list-boards.js`

## Usage Examples

### Example 1: Create and Deploy a Simple Diagram

**User Request**: "Create a diagram with 3 interconnected components and deploy it to a whiteboard"

**Agent Flow**:
```
1. Agent calls create-board with:
   - 3 geo shapes (rectangles)
   - 2 arrow connectors
   - Labels for each component

2. Agent calls deploy-server (if not already running)

3. Agent calls import-board-to-server with the generated board

4. Agent returns URL: http://localhost:3000/room/doc_abc123
```

### Example 2: Create and Save a Flow Diagram

**User Request**: "Build a swimlane diagram for a user onboarding flow"

**Agent Flow**:
```
1. Agent designs shapes:
   - Frames for each swimlane (user, backend, email service)
   - Text boxes for steps
   - Arrows showing flow direction

2. Agent calls create-board

3. Board is saved as JSON to workspace: /my-swimlane-flow.tldraw

4. Agent can export to PNG/SVG if needed
```

### Example 3: Build and Manage a Board Gallery

**User Request**: "Show me all my whiteboards and let me pick one to edit"

**Agent Flow**:
```
1. Agent calls list-boards on running server

2. Agent generates gallery UI with:
   - Board names and creation dates
   - Thumbnail previews
   - Links to view/edit each board

3. User selects a board → opens in tldraw viewer
```

## Skill Scripts

### `scripts/create-board.js`
Programmatically create a `.tldraw` file with shapes, bindings, and text.

**Usage**:
```bash
node scripts/create-board.js \
  --name "my-diagram" \
  --title "System Architecture" \
  --config config.json
```

**Output**: `my-diagram.tldraw` (JSON serialized TLStore snapshot)

See `references/api-reference.md` for detailed shape API.

### `scripts/deploy-server.js`
Deploy a self-hosted tldraw instance using Docker or Node.js.

**Usage**:
```bash
node scripts/deploy-server.js \
  --type docker \
  --port 3000 \
  --database postgresql://localhost/tldraw
```

**Output**: Docker container running tldraw server, accessible at `http://localhost:3000`

See `references/deployment-guide.md` for detailed setup.

### `scripts/import-board.js`
Import a board JSON into a running tldraw server.

**Usage**:
```bash
node scripts/import-board.js \
  --server http://localhost:3000 \
  --board my-diagram.tldraw \
  --name "My Diagram"
```

**Output**: Public URL to view/edit the board on the server.

### `scripts/list-boards.js`
List all boards on a running server (for gallery management).

**Usage**:
```bash
node scripts/list-boards.js \
  --server http://localhost:3000 \
  --format json
```

**Output**: JSON array of board metadata.

## Shape Types Reference

tldraw supports a rich set of shape types. See `references/shape-reference.md` for complete details.

| Type | Example | Typical Use |
|------|---------|------------|
| `geo` | Rectangle, Ellipse, Diamond, Triangle | Flowchart nodes, diagrams |
| `text` | Text box | Labels, annotations, notes |
| `arrow` | Connector with arrowhead | Flow direction, relationships |
| `frame` | Container/artboard | Grouping shapes, swimlanes |
| `image` | Embedded image | Diagrams with images, photos |
| `note` | Sticky note shape | Quick notes, reminders |
| `bookmark` | Web link preview | References to external content |

## Deployment Guide

### Quick Start: Self-Hosted with Docker

1. **Install Docker**: https://docs.docker.com/get-docker/

2. **Run setup script**:
   ```bash
   node scripts/deploy-server.js --type docker
   ```

3. **Access**: Open `http://localhost:3000` in browser

4. **Create boards and import**:
   ```bash
   node scripts/create-board.js --name my-diagram
   node scripts/import-board.js --server http://localhost:3000 --board my-diagram.tldraw
   ```

### Production Deployment

See `references/deployment-guide.md` for production considerations:
- Nginx reverse proxy with SSL/TLS
- WebSocket configuration
- PostgreSQL persistence
- Environment variable setup
- Health checks and monitoring

## API Reference

### Document Serialization Format

tldraw documents are JSON files with the `.tldraw` extension. Structure:

```json
{
  "version": 15,
  "document": {
    "id": "doc_abc123",
    "pages": {
      "page_abc123": {
        "id": "page_abc123",
        "name": "Page 1",
        "shapes": { "/* shape objects */" },
        "bindings": { "/* binding objects */" }
      }
    },
    "assets": { "/* images, videos */" },
    "pageStates": { "/* UI state */" }
  }
}
```

**Key Points**:
- Documents can have multiple pages
- Shapes are keyed by ID in a dictionary
- Bindings define connections between shapes
- Assets store embedded media (base64 encoded)

See `references/api-reference.md` for complete schema and type definitions.

## Known Breaking Changes (tldraw 3.x)

### `text` → `richText` (tldraw 3.0+)

All shape props that previously accepted a plain `string` for label text now require a **ProseMirror document object** (`richText`). This affects both `geo` shapes and `text` shapes.

| Shape type | Old prop (< 3.0) | New prop (≥ 3.0) |
|-----------|-----------------|------------------|
| `geo`     | `props.text`    | `props.richText` |
| `text`    | `props.text`    | `props.richText` |
| `arrow`   | `props.text`    | `props.richText` |

Use the `toRichText(str)` helper exported by `tldraw` to convert plain strings:

```jsx
import { toRichText } from 'tldraw'

// Single line
toRichText('Hello world')
// → { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Hello world' }] }] }

// Multi-line (one paragraph per line)
function rt(str) {
  return {
    type: 'doc',
    content: str.split('\n').map(line => ({
      type: 'paragraph',
      content: line.length ? [{ type: 'text', text: line }] : [],
    })),
  }
}
```

### `align` → `textAlign` for `text` shapes

`text` shape horizontal alignment prop was renamed:

```js
// Old (< 3.0)
{ type: 'text', props: { align: 'middle' } }

// New (≥ 3.0)
{ type: 'text', props: { textAlign: 'middle' } }
```

### Prefer `editor.createShapes()` over `loadSnapshot()`

`store.loadSnapshot()` requires exact schema sequence numbers that change with every release. Prefer the editor API for programmatic board creation — it is version-independent:

```jsx
// ✅ Reliable: works across tldraw versions
<Tldraw onMount={(editor) => {
  editor.createShapes([
    { id: createShapeId('box'), type: 'geo', x: 100, y: 100,
      props: { w: 200, h: 100, geo: 'rectangle', richText: toRichText('Hello') } }
  ])
  editor.zoomToFit()
}} />

// ⚠️  Fragile: schema versions must match installed tldraw version exactly
store.loadSnapshot({ schema: { schemaVersion: 2, sequences: { ... } }, store: { ... } })
```

### Arrow labels: always bring to front

Text labels placed next to arrows are independent shapes. Create them after arrows, then call `editor.bringToFront()` so they always render on top regardless of creation order:

```jsx
editor.createShapes(labelShapes)
editor.bringToFront(labelShapes.map(s => s.id))
```

### Layout hardening rules (required)

Use these rules for every generated board to prevent common rendering regressions:

1. **Normalize escaped line breaks** before converting to rich text.
  - Convert `\\n` to real newlines (`\n`) first.
  - Then call `toRichText(normalizedText)`.

2. **Generate KPI cards from a computed grid**, not hand-typed coordinates.
  - Use constants: `baseX`, `baseY`, `cardW`, `cardH`, `colGap`, `rowGap`.
  - Build each card rectangle from `(row, col)`.

3. **Run overlap assertions before creating shapes**.
  - Assert KPI cards do not overlap each other.
  - Assert connector labels do not overlap section rectangles.
  - Fail fast (throw) in development if any overlap is detected.

4. **Place connector labels in gutters** between sections.
  - Do not place labels inside dense content blocks.
  - Keep horizontal and vertical gutters explicitly reserved in layout constants.

5. **Bring labels to front after shape creation**.
  - Call `editor.bringToFront()` for connector labels and badges.

6. **Reserve safe margins for editor chrome**.
  - Keep important badges/cards at least `220px` away from the right edge to avoid overlap with the tldraw style panel.
  - Keep key content at least `60px` from top/bottom edges for toolbar and zoom/minimap controls.

### `.tldraw` file format vs. skill input schema

`assets/example-architecture.tldraw` in this skill uses a **simplified input schema** designed for human/agent readability — it is **not** a native tldraw store snapshot. Do not pass `.tldraw` files from this skill directly to `store.loadSnapshot()`. Instead, parse them and create shapes via `editor.createShapes()`.

A working reference implementation is in `test-server/src/App.jsx`.

## Troubleshooting

### Server Won't Start
- Check Node.js version: `node --version` (must be 18+)
- Check Docker installation: `docker --version`
- Check port availability: `lsof -i :3000` (macOS/Linux) or `netstat -an | findstr 3000` (Windows)

### Database Connection Failed
- Verify PostgreSQL is running
- Check connection string in `.env`
- Test with: `psql $DATABASE_URL -c "SELECT 1"`

### Board Import Failed
- Ensure server is running: `curl http://localhost:3000/health`
- Verify board JSON format matches schema
- Check server logs: `docker logs tldraw-server` (if using Docker)

### WebSocket Connection Refused
- Check Nginx is configured for WebSocket upgrade
- Verify `Upgrade` and `Connection` headers are proxied
- Test with: `wscat -c wss://tldraw.example.com`

## Resources

- **Official tldraw Repo**: https://github.com/tldraw/tldraw
- **Programmatic API Docs**: https://tldraw.dev/docs/introduction
- **tldraw Store Package**: https://www.npmjs.com/package/@tldraw/store
- **Yjs/y-websocket**: https://docs.yjs.dev/
- **PostgreSQL Node.js Client**: https://node-postgres.com/

## Next Steps

1. Review `references/api-reference.md` for detailed API documentation (includes tldraw 3.x `richText` schema)
2. Check `references/deployment-guide.md` for production setup
3. Examine `scripts/` for implementation examples
4. See `test-server/src/App.jsx` for a working self-hosted board using the editor API
5. See `assets/example-architecture.tldraw` for the simplified skill input schema (not a native tldraw snapshot)
6. Integrate with agent workflows using the tool-calling patterns above

---

*For questions or contributions, refer to research notes in session workspace: `/research/tldraw-agent-skill-research.md`*
