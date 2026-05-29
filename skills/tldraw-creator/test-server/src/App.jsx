import 'tldraw/tldraw.css'
import { Tldraw, createShapeId, toRichText } from 'tldraw'

function normalizeText(str) {
  // Convert escaped line breaks ("\\n") into actual newlines.
  return str.replace(/\\n/g, '\n')
}

function rt(str) {
  return toRichText(normalizeText(str))
}

function geo(
  id,
  x,
  y,
  w,
  h,
  text,
  color = 'grey',
  fill = 'semi',
  size = 's',
  align = 'start',
  verticalAlign = 'start'
) {
  return {
    id: createShapeId(id),
    type: 'geo',
    x,
    y,
    props: {
      w,
      h,
      geo: 'rectangle',
      fill,
      color,
      dash: 'solid',
      size,
      richText: rt(text),
      align,
      verticalAlign,
      font: 'sans',
      labelColor: 'black',
    },
  }
}

function textShape(id, x, y, text, size = 's', color = 'black', width = 300, align = 'start') {
  return {
    id: createShapeId(id),
    type: 'text',
    x,
    y,
    props: {
      richText: rt(text),
      color,
      size,
      font: 'sans',
      textAlign: align,
      autoSize: true,
      w: width,
    },
  }
}

function arrow(id, x1, y1, x2, y2, label = '', dash = 'solid') {
  return {
    id: createShapeId(id),
    type: 'arrow',
    x: 0,
    y: 0,
    props: {
      dash,
      size: 'm',
      fill: 'none',
      color: 'black',
      labelColor: 'black',
      bend: 0,
      start: { x: x1, y: y1 },
      end: { x: x2, y: y2 },
      arrowheadStart: 'none',
      arrowheadEnd: 'arrow',
      text: label,
      font: 'sans',
    },
  }
}

function rectOverlaps(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

function assertNoOverlaps(rects, groupName) {
  for (let i = 0; i < rects.length; i++) {
    for (let j = i + 1; j < rects.length; j++) {
      if (rectOverlaps(rects[i], rects[j])) {
        throw new Error(`${groupName} overlap: ${rects[i].id} vs ${rects[j].id}`)
      }
    }
  }
}

function buildExecutiveReportBoard(editor) {
  const layout = {
    topY: 130,
    topH: 330,
    bottomY: 500,
    bottomH: 360,
    leftX: 30,
    leftW: 360,
    gap: 80,
  }
  layout.midX = layout.leftX + layout.leftW + layout.gap
  layout.midW = 340
  layout.rightX = layout.midX + layout.midW + layout.gap
  layout.rightW = 410
  layout.bottomRightX = layout.midX
  layout.bottomRightW = layout.rightX + layout.rightW - layout.midX

  const sectionRects = [
    { id: 'sec-delivered', x: layout.leftX, y: layout.topY, w: layout.leftW, h: layout.topH },
    { id: 'sec-inflight', x: layout.midX, y: layout.topY, w: layout.midW, h: layout.topH },
    { id: 'sec-risks', x: layout.rightX, y: layout.topY, w: layout.rightW, h: layout.topH },
    { id: 'sec-themes', x: layout.leftX, y: layout.bottomY, w: layout.leftW, h: layout.bottomH },
    { id: 'sec-actions', x: layout.bottomRightX, y: layout.bottomY, w: layout.bottomRightW, h: layout.bottomH },
  ]

  const kpiGrid = {
    x: 520,
    y: 18,
    cols: 3,
    cardW: 170,
    cardH: 42,
    colGap: 20,
    rowGap: 12,
  }
  const kpiRects = [
    { id: 'kpi1', col: 0, row: 0 },
    { id: 'kpi2', col: 1, row: 0 },
    { id: 'kpi3', col: 2, row: 0 },
    { id: 'kpi4', col: 0, row: 1 },
    { id: 'kpi5', col: 1, row: 1 },
    { id: 'kpi6', col: 2, row: 1 },
  ].map(item => ({
    id: item.id,
    x: kpiGrid.x + item.col * (kpiGrid.cardW + kpiGrid.colGap),
    y: kpiGrid.y + item.row * (kpiGrid.cardH + kpiGrid.rowGap),
    w: kpiGrid.cardW,
    h: kpiGrid.cardH,
  }))
  assertNoOverlaps(kpiRects, 'KPI boxes')

  const flowLabels = [
    { id: 'flow-label-1', x: layout.leftX + layout.leftW + 12, y: 272, w: 56, h: 32 },
    { id: 'flow-label-2', x: layout.midX + layout.midW + 12, y: 272, w: 56, h: 32 },
    { id: 'flow-label-3', x: layout.midX + 280, y: layout.topY + layout.topH + 8, w: 64, h: 32 },
  ]
  for (const label of flowLabels) {
    for (const sec of sectionRects) {
      if (rectOverlaps(label, sec)) {
        throw new Error(`Flow label overlap: ${label.id} inside ${sec.id}`)
      }
    }
  }

  const shapes = [
    textShape('title', 40, 20, 'Executive Progress Whiteboard', 'xl', 'black', 700, 'start'),
    textShape('subtitle', 40, 56, 'Source: 260427-executive-report.md | Window: Apr 21-27, 2026', 's', 'grey', 760, 'start'),

    geo('kpi1', kpiRects[0].x, kpiRects[0].y, kpiRects[0].w, kpiRects[0].h, '9 Archived', 'green', 'solid', 's', 'middle', 'middle'),
    geo('kpi2', kpiRects[1].x, kpiRects[1].y, kpiRects[1].w, kpiRects[1].h, '8 Zoom-focused', 'blue', 'solid', 's', 'middle', 'middle'),
    geo('kpi3', kpiRects[2].x, kpiRects[2].y, kpiRects[2].w, kpiRects[2].h, '1 Superseded', 'grey', 'solid', 's', 'middle', 'middle'),
    geo('kpi4', kpiRects[3].x, kpiRects[3].y, kpiRects[3].w, kpiRects[3].h, '6 Issues', 'violet', 'solid', 's', 'middle', 'middle'),
    geo('kpi5', kpiRects[4].x, kpiRects[4].y, kpiRects[4].w, kpiRects[4].h, '2 High Risks', 'red', 'solid', 's', 'middle', 'middle'),
    geo('kpi6', kpiRects[5].x, kpiRects[5].y, kpiRects[5].w, kpiRects[5].h, '7 Actions', 'orange', 'solid', 's', 'middle', 'middle'),

    geo('sec-delivered', layout.leftX, layout.topY, layout.leftW, layout.topH, 'Delivered This Week\\n(9 Changes)', 'green', 'semi', 'm'),
    geo('sec-inflight', layout.midX, layout.topY, layout.midW, layout.topH, 'In-Flight Work\\n(2 Streams)', 'yellow', 'semi', 'm'),
    geo('sec-risks', layout.rightX, layout.topY, layout.rightW, layout.topH, 'Risks and Blockers\\n(P0/P1 Focus)', 'red', 'semi', 'm'),
    geo('sec-themes', layout.leftX, layout.bottomY, layout.leftW, layout.bottomH, 'Cross-Cutting Themes', 'violet', 'semi', 'm'),
    geo('sec-actions', layout.bottomRightX, layout.bottomY, layout.bottomRightW, layout.bottomH, 'Recommended Next Actions', 'blue', 'semi', 'm'),

    textShape('d1', layout.leftX + 18, layout.topY + 52, '1. Admin dashboard domain discovery', 's', 'black', layout.leftW - 36),
    textShape('d2', layout.leftX + 18, layout.topY + 82, '2. Session provisioning hardening', 's', 'black', layout.leftW - 36),
    textShape('d3', layout.leftX + 18, layout.topY + 112, '3. Feature flag batch management', 's', 'black', layout.leftW - 36),
    textShape('d4', layout.leftX + 18, layout.topY + 142, '4. Tenant Admin-Managed Zoom OAuth', 's', 'black', layout.leftW - 36),
    textShape('d5', layout.leftX + 18, layout.topY + 172, '5. Admin dashboard OAuth UI', 's', 'black', layout.leftW - 36),
    textShape('d6', layout.leftX + 18, layout.topY + 202, '6. Marketplace publishing guide', 's', 'black', layout.leftW - 36),
    textShape('d7', layout.leftX + 18, layout.topY + 232, '7. User OAuth Lifeline UI', 's', 'black', layout.leftW - 36),
    textShape('d8', layout.leftX + 18, layout.topY + 262, '8. Non-tenant install guardrails', 's', 'black', layout.leftW - 36),
    textShape('d9', layout.leftX + 18, layout.topY + 292, '9. Mode-aware webhook secret routing', 's', 'black', layout.leftW - 36),

    textShape('if1', layout.midX + 18, layout.topY + 62, 'Zoom OAuth callback state edge cases\\n7 cases catalogued (6 not implemented)', 's', 'black', layout.midW - 36),
    textShape('if2', layout.midX + 18, layout.topY + 152, 'Beta readiness consultation (The Professor)\\n5 architecture + 2 security decisions open', 's', 'black', layout.midW - 36),

    textShape('r1', layout.rightX + 18, layout.topY + 62, 'P0: Beta readiness consultation not actioned', 's', 'red', layout.rightW - 36),
    textShape('r2', layout.rightX + 18, layout.topY + 112, 'P0: Webhook HMAC validation unclear', 's', 'red', layout.rightW - 36),
    textShape('r3', layout.rightX + 18, layout.topY + 162, 'P1: Full solution test run not green', 's', 'orange', layout.rightW - 36),
    textShape('r4', layout.rightX + 18, layout.topY + 212, 'P1: Activity module still stubbed', 's', 'orange', layout.rightW - 36),
    textShape('r5', layout.rightX + 18, layout.topY + 262, 'P3: JWT in query string (SignalR)', 's', 'yellow', layout.rightW - 36),

    textShape('t1', layout.leftX + 18, layout.bottomY + 62, 'T1. Zoom dominated delivery surface (8/11)', 's', 'black', layout.leftW - 36),
    textShape('t2', layout.leftX + 18, layout.bottomY + 112, 'T2. Spec-test-evidence discipline improving', 's', 'black', layout.leftW - 36),
    textShape('t3', layout.leftX + 18, layout.bottomY + 162, 'T3. Enum naming cleanup still costly', 's', 'black', layout.leftW - 36),
    textShape('t4', layout.leftX + 18, layout.bottomY + 212, 'T4. Beta readiness conversation unresolved', 's', 'black', layout.leftW - 36),
    textShape('t5', layout.leftX + 18, layout.bottomY + 262, 'T5. SQL infra instability resolved', 's', 'black', layout.leftW - 36),

    textShape('a1', layout.bottomRightX + 18, layout.bottomY + 62, 'P0. Record decisions for all consultation questions', 's', 'black', layout.bottomRightW - 36),
    textShape('a2', layout.bottomRightX + 18, layout.bottomY + 102, 'P0. Verify webhook HMAC validation in endpoint and handler pipeline', 's', 'black', layout.bottomRightW - 36),
    textShape('a3', layout.bottomRightX + 18, layout.bottomY + 142, 'P1. Bring dotnet test src/FSH.Framework.slnx to green baseline', 's', 'black', layout.bottomRightW - 36),
    textShape('a4', layout.bottomRightX + 18, layout.bottomY + 182, 'P1. Decide Activity module posture: ship, gate, or remove', 's', 'black', layout.bottomRightW - 36),
    textShape('a5', layout.bottomRightX + 18, layout.bottomY + 222, 'P2. Implement OAuth callback edge-case contracts and matrix', 's', 'black', layout.bottomRightW - 36),
    textShape('a6', layout.bottomRightX + 18, layout.bottomY + 262, 'P2. Mitigate SignalR JWT query-string exposure', 's', 'black', layout.bottomRightW - 36),
    textShape('a7', layout.bottomRightX + 18, layout.bottomY + 302, 'P3. Convert ad-hoc OAuth checks to durable E2E automation', 's', 'black', layout.bottomRightW - 36),

    geo('flow-label-1-pill', flowLabels[0].x, flowLabels[0].y, flowLabels[0].w, flowLabels[0].h, 'step 1', 'grey', 'solid', 's', 'middle', 'middle'),
    geo('flow-label-2-pill', flowLabels[1].x, flowLabels[1].y, flowLabels[1].w, flowLabels[1].h, 'step 2', 'grey', 'solid', 's', 'middle', 'middle'),
    geo('flow-label-3-pill', flowLabels[2].x, flowLabels[2].y, flowLabels[2].w, flowLabels[2].h, 'step 3', 'grey', 'solid', 's', 'middle', 'middle'),
  ]

  const arrows = [
    arrow('flow1', layout.leftX + layout.leftW, 288, layout.midX, 288),
    arrow('flow2', layout.midX + layout.midW, 288, layout.rightX, 288),
    arrow('flow3', layout.rightX + 20, layout.topY + layout.topH, layout.midX + 320, layout.bottomY),
  ]

  editor.createShapes(shapes)
  editor.createShapes(arrows)

  const topTextIds = ['flow-label-1-pill', 'flow-label-2-pill', 'flow-label-3-pill'].map(createShapeId)
  editor.bringToFront(topTextIds)
}

export default function App() {
  function handleMount(editor) {
    buildExecutiveReportBoard(editor)
    editor.zoomToFit({ animation: { duration: 400 } })
  }

  return (
    <div style={{ position: 'fixed', inset: 0 }}>
      <Tldraw onMount={handleMount} />
    </div>
  )
}
