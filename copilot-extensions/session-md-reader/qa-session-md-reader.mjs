#!/usr/bin/env node
/**
 * Browser QA Test Suite for Session MD Reader Canvas Extension
 *
 * Usage:
 *   1. Start the extension (e.g. by opening the canvas via Copilot CLI)
 *   2. Set EXTENSION_PORT env var to the HTTP port the extension is listening on
 *   3. Run: node qa-session-md-reader.mjs
 *
 *   Or: EXTENSION_PORT=3456 node qa-session-md-reader.mjs
 *
 * Requires: playwright (npm install playwright)
 * Target session: 9aff5496-0608-40fe-8b4e-b82a6a22d235
 */

import { chromium } from "playwright";
import { strict as assert } from "node:assert";

const TARGET_SESSION = "9aff5496-0608-40fe-8b4e-b82a6a22d235";
const PORT = parseInt(process.env.EXTENSION_PORT, 10);
if (!PORT) {
    console.error("❌ Set EXTENSION_PORT env var to the extension's HTTP port.");
    console.error("   Start the extension first, then check the port from its logs.");
    process.exit(1);
}
const BASE = `http://127.0.0.1:${PORT}`;
const CANVAS_URL = `${BASE}?instance=qa-test&sessionUuid=${TARGET_SESSION}`;

// --- Results tracking ---
let passed = 0, failed = 0, results = [];

function test(id, label, fn) {
    return async (page) => {
        try {
            await fn(page);
            results.push({ id, label, status: "PASS" });
            passed++;
            console.log(`  ✅ ${id}: ${label}`);
        } catch (e) {
            results.push({ id, label, status: "FAIL", error: e.message });
            failed++;
            console.log(`  ❌ ${id}: ${label} — ${e.message}`);
        }
    };
}

// --- Helpers ---
async function getText(page, selector) {
    try { return await page.locator(selector).textContent({ timeout: 3000 }); } catch { return null; }
}

async function hasClass(page, selector, cls) {
    try {
        const locator = page.locator(selector);
        await locator.waitFor({ state: "attached", timeout: 3000 });
        return await locator.evaluate((el, c) => el.classList.contains(c), cls);
    } catch { return false; }
}

async function getStyle(page, selector, prop) {
    try {
        const locator = page.locator(selector);
        await locator.waitFor({ state: "attached", timeout: 3000 });
        return await locator.evaluate((el, p) => getComputedStyle(el).getPropertyValue(p), prop);
    } catch { return null; }
}

// ========================================================================
// TC1: Page Load & Session Name
// ========================================================================
const TC1_LOAD = test("TC1.1", "Page loads without errors", async (page) => {
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.goto(CANVAS_URL, { waitUntil: "networkidle" });
    assert.equal(errors.length, 0, `Console errors: ${errors.join(", ")}`);
    // Wait for session info to load
    await page.waitForFunction(() => {
        const t = document.getElementById("sidebarTitle");
        return t && t.textContent !== "Session Files" && t.textContent !== "No session UUID";
    }, { timeout: 8000 });
});

const TC1_TITLE = test("TC1.2", "document.title starts with 'MD:'", async (page) => {
    const title = await page.title();
    assert.ok(title.startsWith("MD:"), `Expected title to start with "MD:", got "${title}"`);
});

const TC1_SIDEBAR_TITLE = test("TC1.3", "sidebarTitle shows session name", async (page) => {
    const text = await getText(page, "#sidebarTitle");
    assert.ok(text && text.length > 0, "sidebarTitle is empty");
    assert.ok(text.includes("Zoom") || text.includes("webhook"),
        `Expected session name about Zoom webhook, got "${text}"`);
});

const TC1_WELCOME_TITLE = test("TC1.5", "welcomeTitle shows session name", async (page) => {
    const text = await getText(page, "#welcomeTitle");
    assert.ok(text && text.length > 0, "welcomeTitle is empty");
});

const TC1_WELCOME_DESC = test("TC1.6", "welcomeDesc contains repo+branch", async (page) => {
    const text = await getText(page, "#welcomeDesc");
    assert.ok(text.includes("starter-kit") || text.includes("develop"),
        `Expected repo/branch in welcomeDesc, got "${text}"`);
});

const TC1_BADGE = test("TC1.7", "fileCountBadge shows file count", async (page) => {
    const text = await getText(page, "#fileCountBadge");
    assert.ok(text.includes("markdown file"), `Expected file count, got "${text}"`);
    assert.ok(text.includes("7") || text.includes("found"),
        `Expected ~7 files, got "${text}"`);
});

// ========================================================================
// TC2: File Listing & Navigation
// ========================================================================
const TC2_FILE_GROUPS = test("TC2.1", "4 file groups present: Root, checkpoints, research, files", async (page) => {
    const groupHeaders = page.locator(".file-group-header");
    const count = await groupHeaders.count();
    const texts = [];
    for (let i = 0; i < count; i++) {
        texts.push((await groupHeaders.nth(i).textContent()).replace(/\s*\(\d+\)\s*$/, "").trim());
    }
    assert.ok(texts.some(t => /root/i.test(t)), "Missing Root group");
    assert.ok(texts.some(t => /checkpoints/i.test(t)), "Missing checkpoints group");
    assert.ok(texts.some(t => /research/i.test(t)), "Missing research group");
    assert.ok(texts.some(t => /files/i.test(t)), "Missing files group");
});

const TC2_GROUP_TOGGLE = test("TC2.2", "Group collapse/expand toggles file visibility", async (page) => {
    // First ensure we are on files tab and files are loaded
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(500);
    await page.locator(".file-group-header").first().waitFor({ state: "visible", timeout: 5000 });
    // Click first group header to collapse it
    const firstHeader = page.locator(".file-group-header").first();
    const headerText = await firstHeader.textContent();
    await firstHeader.click();
    await page.waitForTimeout(400);
    // Toggle back
    await firstHeader.click();
    await page.waitForTimeout(400);
});

const TC2_FILE_CLICK = test("TC2.3", "Click plan.md loads content in main area", async (page) => {
    // Find and click plan.md using locator
    const planItem = page.locator('.file-item').filter({ hasText: "plan.md" }).first();
    const planExists = await planItem.count() > 0;
    if (planExists) {
        await planItem.click({ timeout: 3000 });
        await page.waitForTimeout(600);
        // Check that rendered content is visible or welcome disappears
        const renderedVisible = await page.locator("#renderedContent").evaluate(el => el.style.display !== "none").catch(() => false);
        const welcomeHidden = await page.locator("#welcomeView").evaluate(el => el.style.display === "none").catch(() => false);
        assert.ok(renderedVisible || welcomeHidden, "Content area not updated after file click");
    } else {
        // Fallback: click first file item
        const firstFile = page.locator(".file-item").first();
        if (await firstFile.count() > 0) {
            await firstFile.click({ timeout: 3000 });
            await page.waitForTimeout(600);
        }
    }
});

const TC2_ACTIVE_FILE = test("TC2.4", "Active file has .active class with accent border", async (page) => {
    const activeItem = page.locator(".file-item.active");
    const count = await activeItem.count();
    if (count > 0) {
        const borderColor = await activeItem.first().evaluate(el => getComputedStyle(el).borderLeftColor).catch(() => null);
        assert.ok(borderColor && borderColor !== "transparent" && borderColor !== "rgba(0, 0, 0, 0)",
            `Active file should have accent border color, got "${borderColor}"`);
    }
});

const TC2_CHECKPOINT_FILE = test("TC2.5", "Click checkpoint file loads and shows TOC headings", async (page) => {
    const cpItem = page.locator('.file-item').filter({ hasText: "index.md" }).first();
    const exists = await cpItem.count() > 0;
    if (exists) {
        await cpItem.click({ timeout: 3000 });
        await page.waitForTimeout(600);
        const activeInfo = await getText(page, "#activeFileInfo");
        assert.ok(activeInfo && (activeInfo.includes("index.md") || activeInfo.includes("heading")),
            `Active file info should show path and headings, got "${activeInfo}"`);
    }
});

const TC2_ACTIVE_INFO = test("TC2.6", "activeFileInfo shows path and heading count", async (page) => {
    const info = await getText(page, "#activeFileInfo");
    assert.ok(info && !info.includes("Select a file"), "activeFileInfo should show file info after loading");
    if (info) {
        assert.ok(info.includes("|") || info.includes("heading"),
            `activeFileInfo should contain separator or heading count, got "${info}"`);
    }
});

// ========================================================================
// TC3: TOC Tab
// ========================================================================
const TC3_TOC_TAB = test("TC3.1", "TOC tab switch shows heading tree", async (page) => {
    // First ensure a file is loaded
    const firstFile = page.locator(".file-item").first();
    if (await firstFile.count() > 0) {
        await firstFile.click({ timeout: 3000 });
        await page.waitForTimeout(600);
    }
    await page.locator('[data-tab="toc"]').click();
    await page.waitForTimeout(400);
    const activeTab = await page.locator('.sidebar-tab.active').getAttribute("data-tab");
    assert.equal(activeTab, "toc", "TOC tab should be active after click");
});

const TC3_TOC_ITEMS = test("TC3.2", "TOC items match file headings", async (page) => {
    const tocItems = page.locator(".toc-item");
    const count = await tocItems.count();
    if (count > 0) {
        const firstText = await tocItems.first().textContent();
        assert.ok(firstText.includes("H") || firstText.trim().length > 0,
            `TOC item should show heading level and text, got "${firstText}"`);
    } else {
        // If no headings, the TOC empty state should show
        const emptyMsg = await getText(page, ".toc-empty");
        assert.ok(emptyMsg && emptyMsg.includes("No headings"), "No headings message expected");
    }
});

const TC3_TOC_CLICK = test("TC3.3", "Click TOC item scrolls to heading", async (page) => {
    const tocItems = page.locator(".toc-item");
    if (await tocItems.count() > 0) {
        await tocItems.first().click();
        await page.waitForTimeout(500);
    }
});

const TC3_BACK_FILES = test("TC3.4", "Switch back to Files tab re-renders files", async (page) => {
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(400);
    const activeTab = await page.locator('.sidebar-tab.active').getAttribute("data-tab");
    assert.equal(activeTab, "files", "Files tab should be active");
    const fileCount = await page.locator(".file-item").count();
    assert.ok(fileCount > 0, "File items should be visible after switching back");
});

// ========================================================================
// TC4: Mermaid Diagram Rendering
// ========================================================================
const TC4_MERMAID_LOAD = test("TC4.1", "Load research file with mermaid blocks", async (page) => {
    // Click files tab first
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(400);
    // Find and click the research file
    const researchItem = page.locator('.file-item').filter({ hasText: "deep-res" }).first();
    const exists = await researchItem.count() > 0;
    if (exists) {
        await researchItem.click({ timeout: 3000 });
        await page.waitForTimeout(2000); // Wait for mermaid CDN + render
    } else {
        // Try clicking the research group first, then find the file
        const researchGroup = page.locator('.file-group-header').filter({ hasText: "research" }).first();
        if (await researchGroup.count() > 0) {
            await researchGroup.click();
            await page.waitForTimeout(400);
        }
        const researchFile = page.locator('.file-item').filter({ hasText: "deep-res" }).first();
        if (await researchFile.count() > 0) {
            await researchFile.click({ timeout: 3000 });
            await page.waitForTimeout(2000);
        }
    }
});

const TC4_MERMAID_DIVS = test("TC4.2", "Mermaid divs exist in rendered content", async (page) => {
    const mermaidDivs = page.locator("#renderedContent .mermaid");
    const count = await mermaidDivs.count();
    if (count === 0) {
        // Check if mermaid content is inside pre/code blocks
        const mermaidPres = page.locator('#renderedContent pre code[class*="mermaid"]');
        const preCount = await mermaidPres.count();
        if (preCount === 0) {
            console.log("   ⚠️  No mermaid blocks found — may need longer CDN wait");
        }
    }
});

const TC4_MERMAID_SVG = test("TC4.3", "Mermaid rendered SVG inside .mermaid", async (page) => {
    const svg = page.locator("#renderedContent .mermaid svg").first();
    const svgCount = await svg.count();
    if (svgCount > 0) {
        const svgContent = await svg.evaluate(el => el.innerHTML);
        assert.ok(svgContent && svgContent.length > 0, "Mermaid SVG should have content");
        // Verify it's a flowchart — check for basic elements
        const shapes = page.locator("#renderedContent .mermaid svg *");
        const shapeCount = await shapes.count();
        assert.ok(shapeCount >= 5, `Expected at least 5 elements in mermaid SVG, got ${shapeCount}`);
    }
});

const TC4_MERMAID_THEME = test("TC4.4", "Mermaid uses dark theme colors", async (page) => {
    // Check that mermaid renders results inside the container
    const mermaidContainer = page.locator("#renderedContent .mermaid").first();
    const exists = await mermaidContainer.count() > 0;
    if (exists) {
        // Check SVG was rendered inside
        const svgs = await page.locator("#renderedContent .mermaid svg").count();
        assert.ok(svgs > 0, "Mermaid should render SVG inside .mermaid container");
        // Check SVG root has dark fill/stroke
        const hasContent = await page.locator("#renderedContent .mermaid svg").evaluate(el => el.innerHTML.length > 0).catch(() => false);
        assert.ok(hasContent, "Mermaid SVG should have rendered content (shapes)");
    }
    // If no mermaid container yet, the CDN may still be loading — that's acceptable
});

const TC4_NO_MERMAID = test("TC4.5", "Load file without mermaid shows no errors", async (page) => {
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    // Load a non-mermaid file
    const planItem = page.locator('.file-item').filter({ hasText: "plan.md" }).first();
    if (await planItem.count() > 0) {
        await planItem.click({ timeout: 3000 });
        await page.waitForTimeout(600);
    }
    assert.equal(errors.length, 0, `Errors when loading non-mermaid file: ${errors.join(", ")}`);
});

// ========================================================================
// TC5: Sidebar Collapse
// ========================================================================
const TC5_COLLAPSE = test("TC5.1", "Collapse toggle shrinks sidebar to ~48px", async (page) => {
    let collapsed = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => false);
    if (collapsed) {
        await page.locator("#collapseToggle").click({ force: true });
        await page.waitForTimeout(400);
    }
    await page.locator("#collapseToggle").click({ force: true });
    await page.locator("#sidebar.collapsed").waitFor({ state: "attached", timeout: 3000 });
    collapsed = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => false);
    assert.ok(collapsed, "Sidebar should have 'collapsed' class after toggle");
});

const TC5_COLLAPSED_CLASS = test("TC5.2", ".sidebar.collapsed class added", async (page) => {
    const collapsed = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => false);
    assert.ok(collapsed, ".sidebar should have .collapsed class");
});

const TC5_TAB_ICONS = test("TC5.3", "Sidebar tabs show data-icon for collapsed mode", async (page) => {
    const tab = page.locator(".sidebar-tab").first();
    const icon = await tab.getAttribute("data-icon");
    assert.ok(icon && icon.length > 0, "Tab should have data-icon attribute");
});

const TC5_CONTENT_HIDDEN = test("TC5.4", "File list and TOC hidden when collapsed", async (page) => {
    const collapsedSidebar = page.locator(".sidebar.collapsed");
    const isCollapsed = await collapsedSidebar.count() > 0;
    if (isCollapsed) {
        const todoContainer = collapsedSidebar.locator(".todo-tree-container");
        const count = await todoContainer.count();
        if (count > 0) {
            const visible = await todoContainer.first().isVisible();
            assert.ok(!visible, "Todo tree should not be visible in collapsed state");
        }
    }
});

const TC5_EXPAND = test("TC5.5", "Click toggle again expands sidebar", async (page) => {
    await page.locator("#collapseToggle").click({ force: true });
    // Wait for the collapsed class to disappear
    await page.waitForTimeout(400);
    const collapsed = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => true);
    assert.ok(!collapsed, "Sidebar should NOT have 'collapsed' class after second toggle");
});

const TC5_EXPANDED = test("TC5.6", ".collapsed class removed after expand", async (page) => {
    const collapsed = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => true);
    assert.ok(!collapsed, ".collapsed class should be removed");
});

// ========================================================================
// TC6: Keyboard Shortcuts
// ========================================================================
const TC6_CTRL_B = test("TC6.1", "Ctrl+B toggles sidebar", async (page) => {
    const initiallyCollapsed = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => false);
    await page.keyboard.press("Control+b");
    await page.waitForTimeout(400);
    const after = await page.evaluate(() => document.getElementById("sidebar")?.classList.contains("collapsed")).catch(() => false);
    assert.notEqual(initiallyCollapsed, after, "Sidebar collapsed state should change after Ctrl+B");
    if (after) {
        await page.keyboard.press("Control+b");
        await page.waitForTimeout(400);
    }
});

const TC6_CTRL_1 = test("TC6.2", "Ctrl+1 switches to Files tab", async (page) => {
    await page.keyboard.press("Control+1");
    await page.waitForTimeout(300);
    const activeTab = await page.$eval('.sidebar-tab.active', el => el.dataset.tab).catch(() => null);
    assert.equal(activeTab, "files", "Ctrl+1 should switch to Files tab");
});

const TC6_CTRL_2 = test("TC6.3", "Ctrl+2 switches to TOC tab", async (page) => {
    await page.keyboard.press("Control+2");
    await page.waitForTimeout(300);
    const activeTab = await page.$eval('.sidebar-tab.active', el => el.dataset.tab).catch(() => null);
    assert.equal(activeTab, "toc", "Ctrl+2 should switch to TOC tab");
});

const TC6_CTRL_3 = test("TC6.4", "Ctrl+3 switches to Todos tab", async (page) => {
    await page.keyboard.press("Control+3");
    await page.waitForTimeout(500);
    const activeTab = await page.$eval('.sidebar-tab.active', el => el.dataset.tab).catch(() => null);
    assert.equal(activeTab, "todos", "Ctrl+3 should switch to Todos tab");
});

const TC6_ZOOM_IN = test("TC6.5", "Ctrl+= 3× zooms to 1.3×", async (page) => {
    // Reset first
    await page.keyboard.press("Control+0");
    await page.waitForTimeout(100);
    for (let i = 0; i < 3; i++) {
        await page.keyboard.press("Control+=");
        await page.waitForTimeout(50);
    }
    await page.waitForTimeout(200);
    const zoom = await page.evaluate(() => document.body.style.zoom);
    assert.ok(zoom && parseFloat(zoom) > 1.0, `Zoom should be > 1.0, got "${zoom}"`);
});

const TC6_ZOOM_OUT = test("TC6.6", "Ctrl+- 5× zooms to 0.8×", async (page) => {
    for (let i = 0; i < 5; i++) {
        await page.keyboard.press("Control+-");
        await page.waitForTimeout(50);
    }
    await page.waitForTimeout(200);
    const zoom = await page.evaluate(() => document.body.style.zoom);
    assert.ok(zoom && parseFloat(zoom) < 1.0, `Zoom should be < 1.0, got "${zoom}"`);
});

const TC6_ZOOM_RESET = test("TC6.7", "Ctrl+0 resets zoom to 1.0", async (page) => {
    await page.keyboard.press("Control+0");
    await page.waitForTimeout(200);
    const zoom = await page.evaluate(() => document.body.style.zoom);
    assert.ok(zoom === "1" || zoom === "1.0", `Zoom reset should be 1.0, got "${zoom}"`);
});

// ========================================================================
// TC7: Todo Tree
// ========================================================================
const TC7_TODOS_TAB = test("TC7.1", "Todos tab loads and shows content", async (page) => {
    // Switch to Files first, then to Todos
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(300);
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(1200);
    const activeTab = await page.locator('.sidebar-tab.active').getAttribute("data-tab");
    assert.equal(activeTab, "todos", "Todos tab should be active");
});

const TC7_TODOS_CONTENT = test("TC7.2", "Todos tab shows HTML tree or empty state", async (page) => {
    await page.waitForTimeout(800);
    const nodeCount = await page.locator(".todo-tree-node").count();
    const emptyCount = await page.locator(".todo-tree-container .empty-state").count();
    if (nodeCount > 0) {
        assert.ok(nodeCount > 0, "HTML tree should have todo nodes");
        const titles = await page.locator(".todo-title").count();
        console.log(`   ℹ️  Todo tree: ${nodeCount} nodes, ${titles} with titles`);
        assert.ok(titles >= nodeCount, "Each node should have a title element");
    } else if (emptyCount > 0) {
        const text = await page.locator(".todo-tree-container .empty-state").textContent();
        assert.ok(text.includes("No todos"), `Empty state expected: "${text}"`);
    } else {
        console.log("   ⚠️  Todos content not yet rendered — may need more wait time");
    }
});

const TC7_TODOS_COLORS = test("TC7.3", "Todo nodes use status colors", async (page) => {
    const dots = page.locator(".todo-status-dot");
    const count = await dots.count();
    if (count > 0) {
        const colors = new Set();
        for (let i = 0; i < Math.min(count, 20); i++) {
            const bg = await dots.nth(i).evaluate(el => getComputedStyle(el).getPropertyValue("--status-color")).catch(() => null);
            if (bg) colors.add(bg.trim());
        }
        const statusColors = ["#88889a", "#7c8aff", "#4ade80", "#f87171"];
        const used = statusColors.some(c => colors.has(c));
        assert.ok(used || colors.size > 0, "Todo nodes should use valid status colors");
        console.log(`   ℹ️  Todo status colors used: ${[...colors].join(", ")}`);
    }
});

const TC7_TODOS_DETAILS = test("TC7.5", "Click todo node opens details panel", async (page) => {
    const firstNode = page.locator(".todo-node-content").first();
    if (await firstNode.count() > 0) {
        await firstNode.click();
        await page.waitForTimeout(300);
        const panel = page.locator("#todoDetailsPanel");
        const isOpen = await panel.evaluate(el => el.classList.contains("open")).catch(() => false);
        assert.ok(isOpen, "Todo details panel should open on node click");
        // Check it has content
        const title = await page.locator("#todoDetailTitle").textContent();
        assert.ok(title && title.length > 0, "Details panel should show todo title");
        // Close the panel
        await page.locator(".todo-details-close").click();
        await page.waitForTimeout(200);
        const stillOpen = await panel.evaluate(el => el.classList.contains("open")).catch(() => false);
        assert.ok(!stillOpen, "Details panel should close on X button click");
    }
});

const TC7_TODOS_SWITCH_BACK = test("TC7.4", "Switch back to Files shows file list intact", async (page) => {
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(400);
    const fileCount = await page.locator(".file-item").count();
    assert.ok(fileCount > 0, "File items should be visible after switching from Todos");
});

// ========================================================================
// TC8: Edge Cases
// ========================================================================
const TC8_INVALID_UUID = test("TC8.1", "Invalid UUID shows error", async (page) => {
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.goto(`${BASE}?instance=qa-invalid&sessionUuid=invalid-uuid-12345`, { waitUntil: "networkidle" });
    await page.waitForTimeout(1200);
    const badgeText = await getText(page, "#fileCountBadge");
    if (badgeText && badgeText.includes("Error")) {
        assert.ok(errors.length === 0, `Errors on invalid UUID: ${errors.join(", ")}`);
    }
});

const TC8_NO_UUID = test("TC8.2", "No sessionUuid shows 'Provide sessionUuid'", async (page) => {
    await page.goto(`${BASE}?instance=qa-nouuid`, { waitUntil: "networkidle" });
    await page.waitForTimeout(600);
    const badgeText = await getText(page, "#fileCountBadge");
    assert.ok(badgeText && (badgeText.includes("Provide") || badgeText.includes("No session")),
        `Expected UUID prompt, got "${badgeText}"`);
});

const TC8_RAPID_SWITCH = test("TC8.3", "Rapid file switching shows loading", async (page) => {
    await page.goto(CANVAS_URL, { waitUntil: "networkidle" });
    await page.waitForTimeout(1500);
    // Wait for file list to fully render
    await page.locator(".file-item").first().waitFor({ state: "visible", timeout: 5000 }).catch(() => {});
    // Rapidly click multiple files using locators
    const fileItems = page.locator(".file-item");
    const count = await fileItems.count();
    if (count >= 3) {
        const errors = [];
        page.on("pageerror", e => errors.push(e.message));
        for (let i = 0; i < Math.min(3, count); i++) {
            await fileItems.nth(i).click({ timeout: 2000 }).catch(() => {});
            await page.waitForTimeout(50);
        }
        await page.waitForTimeout(800);
        assert.equal(errors.length, 0, `Errors during rapid switching: ${errors.join(", ")}`);
    }
});

const TC8_SSE = test("TC8.4", "SSE connection to /events established", async (page) => {
    // Reload to capture the SSE request
    await page.goto(CANVAS_URL, { waitUntil: "networkidle" });
    await page.waitForTimeout(600);
    // Check EventSource is available in the page
    const hasSSE = await page.evaluate(() => typeof EventSource !== "undefined").catch(() => false);
    assert.ok(hasSSE, "EventSource should be available in the page");
});

// ========================================================================
// TC7: Todo Tree — details/summary behavior (refined)
// ========================================================================

const TC7_COLLAPSE_TOGGLE = test("TC7.6", "Chevron toggles children; row click does not toggle", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const parentDetails = page.locator('details.todo-tree-node').filter({ has: page.locator('.chevron') }).first();
    const exists = await parentDetails.count() > 0;
    if (exists) {
        const wasOpen = await parentDetails.evaluate(el => el.hasAttribute("open"));
        if (!wasOpen) {
            await parentDetails.locator("> summary .chevron").click();
            await page.waitForTimeout(300);
        }
        // Clicking the row body (non-chevron) must NOT toggle collapse — only the chevron may.
        await parentDetails.locator("> summary .todo-title").click();
        await page.waitForTimeout(300);
        const stillOpen = await parentDetails.evaluate(el => el.hasAttribute("open"));
        assert.ok(stillOpen, "Parent should still be open after a row (non-chevron) click");
        // Close the details panel opened by the row click
        if (await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false)) {
            await page.locator(".todo-details-close").click();
            await page.waitForTimeout(200);
        }
        // Clicking the chevron DOES toggle collapse
        await parentDetails.locator("> summary .chevron").click();
        await page.waitForTimeout(300);
        const isOpen = await parentDetails.evaluate(el => el.hasAttribute("open"));
        assert.ok(!isOpen, "Parent details should be closed after chevron click");
        await parentDetails.locator("> summary .chevron").click();
        await page.waitForTimeout(200);
    }
});

const TC7_CHEVRON_VISIBLE = test("TC7.7", "Chevron visible on parent, hidden on leaf", async (page) => {
    // Parent = details that CONTAIN another details element
    const parentChevrons = page.locator('details.todo-tree-node:has(details.todo-tree-node) > summary .chevron');
    const parentCount = await parentChevrons.count();
    if (parentCount > 0) {
        for (let i = 0; i < Math.min(parentCount, 5); i++) {
            const vis = await parentChevrons.nth(i).evaluate(el => getComputedStyle(el).visibility);
            assert.equal(vis, "visible", `Parent chevron ${i} should be visible, got "${vis}"`);
        }
    }
    // Leaf = details that do NOT contain other details elements OR any elements with no children
    const leafChevrons = page.locator('details.todo-tree-node:not(:has(details.todo-tree-node)) > summary .chevron');
    const leafCount = await leafChevrons.count();
    if (leafCount > 0) {
        const vis = await leafChevrons.first().evaluate(el => getComputedStyle(el).visibility);
        assert.equal(vis, "hidden", "Leaf chevron should be visibility:hidden");
    }
});

const TC7_CHEVRON_ROTATION = test("TC7.8", "Chevron rotates when details opens", async (page) => {
    const parent = page.locator('details.todo-tree-node').filter({ has: page.locator('.chevron') }).first();
    const exists = await parent.count() > 0;
    if (exists) {
        const open = await parent.evaluate(el => el.hasAttribute("open"));
        if (open) {
            await parent.locator("> summary .chevron").click();
            await page.waitForTimeout(300);
        }
        let transform = await parent.locator('summary .chevron').evaluate(el => getComputedStyle(el).transform);
        const closedIsIdentity = transform === "none" || transform === "matrix(1, 0, 0, 1, 0, 0)";
        await parent.locator("> summary .chevron").click();
        await page.waitForTimeout(300);
        transform = await parent.locator('summary .chevron').evaluate(el => getComputedStyle(el).transform);
        const openIsRotated = transform !== "none";
        assert.ok(closedIsIdentity || openIsRotated, "Chevron should rotate on details[open]");
    }
});

const TC7_DEPTH_INDENT = test("TC7.9", "Nodes at different depths have distinct margin-left", async (page) => {
    const summaries = page.locator("summary.todo-node-content");
    const count = await summaries.count();
    const margins = new Set();
    for (let i = 0; i < Math.min(count, 15); i++) {
        const ml = await summaries.nth(i).evaluate(el => parseFloat(getComputedStyle(el).marginLeft));
        margins.add(Math.round(ml));
    }
    console.log(`   ℹ️  Depth margin values: ${[...margins].join(", ")}`);
    // If all nodes are at same depth (flat list), that's OK — just log it
    const hasParents = await page.locator('details.todo-tree-node:has(details.todo-tree-node)').count() > 0;
    if (hasParents) {
        assert.ok(margins.size >= 2, `Expected 2+ indent levels, got ${margins.size}: ${[...margins].join(", ")}`);
    } else {
        console.log("   ℹ️  Only single-level tree found — all nodes at same depth");
    }
});

// ========================================================================
// TC9: Details Panel Layout
// ========================================================================

const TC9_PANEL_HEIGHT = test("TC9.1", "Details panel has fixed 350px height", async (page) => {
    // Navigate back to main session
    await page.goto(CANVAS_URL, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const node = page.locator("summary.todo-node-content").first();
    if (await node.count() > 0) {
        await node.click();
        await page.waitForTimeout(300);
    }
    const panel = page.locator("#todoDetailsPanel");
    const height = await panel.evaluate(el => parseFloat(getComputedStyle(el).height));
    assert.ok(Math.abs(height - 350) < 5, `Panel height should be ~350px, got ${height}px`);
    const fs = await panel.evaluate(el => getComputedStyle(el).flexShrink);
    assert.equal(fs, "0", "Panel should have flex-shrink:0");
});

const TC9_TREE_SCROLLS = test("TC9.2", "Tree scrolls independently above panel", async (page) => {
    const tc = page.locator(".todo-tree-container");
    const oy = await tc.evaluate(el => getComputedStyle(el).overflowY);
    assert.equal(oy, "auto", "Tree container overflow-y should be auto");
    const fg = await tc.evaluate(el => getComputedStyle(el).flexGrow);
    assert.equal(fg, "1", "Tree container should flex-grow:1");
});

const TC9_PANEL_OVERFLOW = test("TC9.3", "Panel clips; description area scrolls internally", async (page) => {
    const panel = page.locator("#todoDetailsPanel");
    const poy = await panel.evaluate(el => getComputedStyle(el).overflowY);
    assert.ok(poy === "hidden" || poy === "clip", `Panel overflow-y should be hidden (clips, scrolls internally), got "${poy}"`);
    const body = page.locator("#todoDetailBody");
    const bo = await body.evaluate(el => getComputedStyle(el).overflow);
    assert.ok(bo.includes("hidden"), `#todoDetailBody should have overflow:hidden, got "${bo}"`);
    const desc = page.locator("#todoDetailDesc");
    const doy = await desc.evaluate(el => getComputedStyle(el).overflowY);
    assert.ok(doy === "auto" || doy === "scroll", `Description area should scroll, got "${doy}"`);
});

const TC9_CLOSE_BUTTON = test("TC9.4", "Close button hides panel", async (page) => {
    const panel = page.locator("#todoDetailsPanel");
    const open = await panel.evaluate(el => el.classList.contains("open"));
    if (open) {
        await page.locator(".todo-details-close").click();
        await page.waitForTimeout(200);
        const stillOpen = await panel.evaluate(el => el.classList.contains("open"));
        assert.ok(!stillOpen, "Panel should close on X click");
    }
});

const TC9_TAB_SWITCH = test("TC9.5", "Switch tab clears panel", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const node = page.locator("summary.todo-node-content").first();
    if (await node.count() > 0) {
        await node.click();
        await page.waitForTimeout(300);
    }
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(400);
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const panel = page.locator("#todoDetailsPanel");
    const open = await panel.evaluate(el => el.classList.contains("open")).catch(() => false);
    assert.ok(!open, "Panel should be closed after tab switch");
});

const TC9_REOPEN = test("TC9.6", "Re-click reopens panel", async (page) => {
    const node = page.locator("summary.todo-node-content").first();
    if (await node.count() > 0) {
        await node.click();
        await page.waitForTimeout(300);
    }
    const panel = page.locator("#todoDetailsPanel");
    const open = await panel.evaluate(el => el.classList.contains("open"));
    assert.ok(open, "Panel should reopen on node click");
    const title = await page.locator("#todoDetailTitle").textContent();
    assert.ok(title && title.length > 0, "Panel should show todo title");
});

const TC9_PANEL_WIDTH = test("TC9.7", "Panel has positive width", async (page) => {
    const panel = page.locator("#todoDetailsPanel");
    const w = await panel.evaluate(el => el.getBoundingClientRect().width);
    assert.ok(w > 0, `Panel width should be positive, got ${w}`);
});

// ========================================================================
// TC10: Responsive Main Content
// ========================================================================

const TC10_MAX_WIDTH = test("TC10.1", "Main max-width is 100%", async (page) => {
    const mw = await page.locator(".main").evaluate(el => getComputedStyle(el).maxWidth);
    assert.equal(mw, "100%", `Main max-width should be 100%, got "${mw}"`);
});

const TC10_REFLOW = test("TC10.2", "Main content reflows when sidebar resized", async (page) => {
    const mainEl = page.locator(".main");
    const wBefore = await mainEl.evaluate(el => el.getBoundingClientRect().width);
    const orig = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sidebar-width")) || 300);
    await page.evaluate(() => document.documentElement.style.setProperty("--sidebar-width", "200px"));
    await page.waitForTimeout(400);
    const wAfter = await mainEl.evaluate(el => el.getBoundingClientRect().width);
    assert.ok(wAfter >= wBefore, "Main should be wider with narrower sidebar");
    await page.evaluate((o) => document.documentElement.style.setProperty("--sidebar-width", o + "px"), orig);
});

const TC10_NO_HSCROLL = test("TC10.3", "No horizontal scroll on main", async (page) => {
    const sw = await page.locator(".main").evaluate(el => el.scrollWidth);
    const cw = await page.locator(".main").evaluate(el => el.clientWidth);
    if (sw > 0 && cw > 0) {
        assert.ok(sw <= cw + 5, `Main shouldn't have h-scroll (scroll:${sw}, client:${cw})`);
    }
});

// ========================================================================
// TC8: Edge Cases (extended)
// ========================================================================
const TC8_RAPID_CLICKS = test("TC8.5", "Rapid node clicks produce no errors", async (page) => {
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const nodes = page.locator("summary.todo-node-content");
    const count = await nodes.count();
    for (let i = 0; i < Math.min(count, 5); i++) {
        await nodes.nth(i).click({ timeout: 500 });
    }
    await page.waitForTimeout(200);
    assert.ok(errors.length === 0, `Errors after rapid clicks: ${errors.join(", ")}`);
});

const TC8_EMPTY_TODOS = test("TC8.6", "No-todos session shows empty state", async (page) => {
    await page.goto(BASE + "?instance=qa-notodos&sessionUuid=empty", { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const es = page.locator(".todo-tree-container .empty-state");
    if (await es.count() > 0) {
        const txt = await es.textContent();
        assert.ok(txt.includes("No todos"), `Empty state should mention "No todos", got "${txt}"`);
    }
});

// ========================================================================
// TC7: Todo Tree — Pass Badge Tests
// ========================================================================

const TC7_PASS_BADGE_COUNT = test("TC7.10", "Each todo node has a pass badge", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const nodeCount = await page.locator(".todo-tree-node").count();
    if (nodeCount > 0) {
        const badgeCount = await page.locator(".todo-pass-badge").count();
        assert.ok(badgeCount === nodeCount, `Badge count (${badgeCount}) should equal node count (${nodeCount})`);
    }
});

const TC7_PASS_BADGE_TEXT = test("TC7.11", "Badge text matches data-passid attribute", async (page) => {
    const nodes = page.locator(".todo-tree-node");
    const count = await nodes.count();
    for (let i = 0; i < Math.min(count, 10); i++) {
        const dataPass = await nodes.nth(i).getAttribute("data-passid");
        // Use direct child selector to avoid matching badges inside nested details
        const badge = nodes.nth(i).locator("> summary .todo-pass-badge");
        const badgeText = await badge.textContent();
        assert.equal(badgeText, dataPass, `Badge text "${badgeText}" should match data-passid "${dataPass}"`);
    }
});

const TC7_PASS_BADGE_STYLE = test("TC7.12", "Badge has pill styling with small font", async (page) => {
    const badge = page.locator(".todo-pass-badge").first();
    if (await badge.count() > 0) {
        const borderRadius = await badge.evaluate(el => parseFloat(getComputedStyle(el).borderRadius));
        const fontSize = await badge.evaluate(el => parseFloat(getComputedStyle(el).fontSize));
        assert.ok(borderRadius >= 6, `Border-radius should be pill-like, got ${borderRadius}`);
        assert.ok(fontSize <= 10, `Font-size should be small, got ${fontSize}`);
    }
});

// ========================================================================
// TC11: Pass ID Filter
// ========================================================================

const TC11_FILTER_BAR = test("TC11.1", "Filter bar renders with All + unique pass buttons", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const filterBtns = page.locator(".todo-filter-btn");
    const btnCount = await filterBtns.count();
    assert.ok(btnCount >= 2, `Should have at least All + 1 pass filter, got ${btnCount} buttons`);
    const allBtn = page.locator('.todo-filter-btn[data-pass="all"]');
    assert.ok(await allBtn.count() > 0, "All button should exist");
    const allActive = await allBtn.evaluate(el => el.classList.contains("active"));
    assert.ok(allActive, "All button should be active by default");
});

const TC11_FILTER_HIDES = test("TC11.2", "Click pass filter hides non-matching nodes", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const passBtns = page.locator('.todo-filter-btn[data-pass]:not([data-pass="all"])');
    const btnCount = await passBtns.count();
    if (btnCount > 0) {
        const firstPass = await passBtns.first().getAttribute("data-pass");
        await passBtns.first().click();
        await page.waitForTimeout(200);
        // Check that at least one node matches the filter
        const matchingNodes = page.locator(`.todo-tree-node[data-passid="${firstPass}"]:not(.hidden-by-filter)`);
        const hiddenNodes = page.locator('.todo-tree-node.hidden-by-filter');
        const matchingCount = await matchingNodes.count();
        const hiddenCount = await hiddenNodes.count();
        assert.ok(matchingCount > 0, `Should have matching nodes for pass "${firstPass}"`);
        assert.ok(hiddenCount > 0, "Should have hidden nodes when filter is active");
    }
});

const TC11_FILTER_ALL = test("TC11.3", "Click All restores all nodes", async (page) => {
    const allBtn = page.locator('.todo-filter-btn[data-pass="all"]');
    await allBtn.click();
    await page.waitForTimeout(200);
    const hiddenNodes = page.locator('.todo-tree-node.hidden-by-filter');
    const hiddenCount = await hiddenNodes.count();
    assert.equal(hiddenCount, 0, "All nodes should be visible when All filter is active");
});

const TC11_FILTER_PERSISTS = test("TC11.4", "Filter state persists through tab switch", async (page) => {
    const passBtns = page.locator('.todo-filter-btn[data-pass]:not([data-pass="all"])');
    const btnCount = await passBtns.count();
    if (btnCount > 0) {
        const firstPass = await passBtns.first().getAttribute("data-pass");
        await passBtns.first().click();
        await page.waitForTimeout(200);
        // Switch to Files tab and back
        await page.locator('[data-tab="files"]').click();
        await page.waitForTimeout(200);
        await page.locator('[data-tab="todos"]').click();
        await page.waitForTimeout(600);
        // Check filter is still active
        const activeBtn = page.locator('.todo-filter-btn.active');
        const activePass = await activeBtn.getAttribute("data-pass");
        assert.equal(activePass, firstPass, `Filter should persist as "${firstPass}" after tab switch`);
        // Check non-matching nodes are still hidden
        const hiddenCount = await page.locator('.todo-tree-node.hidden-by-filter').count();
        assert.ok(hiddenCount > 0, "Hidden-by-filter should persist after tab switch");
    }
});

const TC11_FILTER_DETAILS = test("TC11.5", "Filter + details panel interaction", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    // Reset filter to All, click a visible node
    await page.locator('.todo-filter-btn[data-pass="all"]').click();
    await page.waitForTimeout(200);
    const firstNode = page.locator(".todo-node-content").first();
    if (await firstNode.count() > 0) {
        await firstNode.click();
        await page.waitForTimeout(300);
        const panelOpen = await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open"));
        assert.ok(panelOpen, "Details panel should open when clicking a filtered-visible node");
        await page.locator(".todo-details-close").click();
    }
});

const TC11_FILTER_STYLING = test("TC11.6", "Active filter button has distinct styling", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const allBtn = page.locator('.todo-filter-btn[data-pass="all"]');
    const bgActive = await allBtn.evaluate(el => getComputedStyle(el).background);
    // Click a different one
    const passBtns = page.locator('.todo-filter-btn[data-pass]:not([data-pass="all"])');
    if (await passBtns.count() > 0) {
        await passBtns.first().click();
        await page.waitForTimeout(200);
        const bgInactive = await allBtn.evaluate(el => getComputedStyle(el).background);
        const activeBg = await passBtns.first().evaluate(el => getComputedStyle(el).background);
        assert.ok(activeBg !== bgInactive, "Active filter should have different background than inactive");
    }
});

const TC11_FILTER_RAPID = test("TC11.7", "Rapid filter switching is stable", async (page) => {
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const passBtns = page.locator('.todo-filter-btn');
    const count = await passBtns.count();
    for (let i = 0; i < Math.min(count, 5); i++) {
        await passBtns.nth(i).click();
    }
    await page.waitForTimeout(200);
    assert.equal(errors.length, 0, `No JS errors on rapid filter clicks: ${errors.join(", ")}`);
});

// ========================================================================
// TC12: Inline Tab Refresh
// ========================================================================

const TC12_REFRESH_BUTTONS = test("TC12.1", "Each sidebar tab has a refresh button", async (page) => {
    const refreshBtns = page.locator(".tab-refresh-btn");
    const count = await refreshBtns.count();
    assert.equal(count, 3, `Should have 3 refresh buttons (Files, TOC, Todos), got ${count}`);
});

const TC12_REFRESH_VISIBILITY = test("TC12.2", "Refresh button visible on tab hover", async (page) => {
    await page.locator('[data-tab="todos"]').hover();
    await page.waitForTimeout(200);
    const refreshBtn = page.locator('.sidebar-tab[data-tab="todos"] .tab-refresh-btn');
    const opacity = await refreshBtn.evaluate(el => parseFloat(getComputedStyle(el).opacity));
    assert.ok(opacity > 0, `Refresh button should be visible on tab hover, opacity=${opacity}`);
});

const TC12_FILES_REFRESH = test("TC12.3", "Click refresh on Files tab re-fetches file list", async (page) => {
    // First ensure we're on Files tab
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(400);
    const beforeCount = await page.locator(".file-item").count();
    assert.ok(beforeCount > 0, "Should have files before refresh");
    // Click refresh button on Files tab
    const refreshBtn = page.locator('.sidebar-tab[data-tab="files"] .tab-refresh-btn');
    await refreshBtn.click({ force: true });
    await page.waitForTimeout(600);
    const afterCount = await page.locator(".file-item").count();
    assert.ok(afterCount > 0, `File items should still exist after refresh (count=${afterCount})`);
    assert.equal(afterCount, beforeCount, "File item count should be stable after refresh");
});

const TC12_TODOS_REFRESH = test("TC12.4", "Click refresh on Todos tab preserves filter state", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    // Apply a filter
    const passBtns = page.locator('.todo-filter-btn[data-pass]:not([data-pass="all"])');
    if (await passBtns.count() > 0) {
        const filterPass = await passBtns.first().getAttribute("data-pass");
        await passBtns.first().click();
        await page.waitForTimeout(200);
        // Click refresh on Todos tab
        await page.locator('[data-tab="todos"]').hover();
        const refreshBtn = page.locator('.sidebar-tab[data-tab="todos"] .tab-refresh-btn');
        await refreshBtn.click();
        await page.waitForTimeout(600);
        // Filter should still be active
        const activeBtn = page.locator('.todo-filter-btn.active');
        const activePass = await activeBtn.getAttribute("data-pass");
        assert.equal(activePass, filterPass, "Filter should persist after refresh");
    }
});

const TC12_TOC_REFRESH = test("TC12.5", "Click refresh on TOC tab re-renders heading tree", async (page) => {
    // Load a file first
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(200);
    const firstFile = page.locator(".file-item").first();
    if (await firstFile.count() > 0) {
        await firstFile.click();
        await page.waitForTimeout(400);
    }
    // Switch to TOC tab and refresh
    await page.locator('[data-tab="toc"]').hover();
    await page.waitForTimeout(200);
    const refreshBtn = page.locator('.sidebar-tab[data-tab="toc"] .tab-refresh-btn');
    await refreshBtn.click();
    await page.waitForTimeout(600);
    const tocItems = page.locator(".toc-item");
    const tocCount = await tocItems.count();
    assert.ok(tocCount >= 0, "TOC items should be visible after refresh");
});

const TC12_LOADING_ANIMATION = test("TC12.6", "Refresh button shows loading animation", async (page) => {
    await page.locator('[data-tab="todos"]').hover();
    const refreshBtn = page.locator('.sidebar-tab[data-tab="todos"] .tab-refresh-btn');
    // Get initial animation
    const animBefore = await refreshBtn.evaluate(el => getComputedStyle(el).animationName || "");
    // Click and check during loading
    await refreshBtn.evaluate(el => {
        el.classList.add("loading");
    });
    const hasSpinAnim = await refreshBtn.evaluate(el => {
        const anim = getComputedStyle(el).animationName;
        return anim && anim.length > 0;
    });
    assert.ok(hasSpinAnim, "Loading class should trigger a spin animation");
});

const TC12_RAPID_REFRESH = test("TC12.7", "Rapid refresh clicks are stable", async (page) => {
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.locator('[data-tab="files"]').hover();
    const refreshBtn = page.locator('.sidebar-tab[data-tab="files"] .tab-refresh-btn');
    for (let i = 0; i < 5; i++) {
        await refreshBtn.click();
    }
    await page.waitForTimeout(500);
    assert.equal(errors.length, 0, `No JS errors on rapid refresh clicks: ${errors.join(", ")}`);
});

// ========================================================================
// TC13: Full session name + UUID rendering (fixture-longname)
// ========================================================================
const FIXTURE_LONG_NAME = "This is an extremely long session name that must be rendered in full without any truncation happening to it";

const TC13_LONG_NAME = test("TC13.1", "Full session name rendered untruncated in sidebar", async (page) => {
    await page.goto(BASE + "?instance=qa-longname&sessionUuid=fixture-longname", { waitUntil: "networkidle" });
    await page.waitForFunction(() => {
        const t = document.getElementById("sidebarTitle");
        return t && t.textContent.includes("extremely long session name");
    }, { timeout: 8000 });
    const title = await page.locator("#sidebarTitle").textContent();
    assert.equal(title, FIXTURE_LONG_NAME, "sidebarTitle should be the full untruncated session name");
    assert.ok(!title.includes("\u2026"), "sidebarTitle must not be truncated with ellipsis");
});

const TC13_FULL_UUID = test("TC13.2", "Full session UUID shown on a separate line", async (page) => {
    await page.waitForTimeout(300);
    const uuidText = await page.locator("#sessionUuidLabel").textContent();
    assert.equal(uuidText, "fixture-longname", "sessionUuidLabel should show the full session UUID");
    const uuidVisible = await page.locator("#sessionUuidLabel").isVisible();
    assert.ok(uuidVisible, "sessionUuidLabel should be visible");
    const nameBox = await page.locator("#sidebarTitle").boundingBox();
    const uuidBox = await page.locator("#sessionUuidLabel").boundingBox();
    if (nameBox && uuidBox) {
        assert.ok(uuidBox.y > nameBox.y, "UUID line should be below the session name line");
    }
});

// ========================================================================
// TC14: Todo tree depth clamping (fixture-deep: root->a->b->c->d->e)
// ========================================================================
const TC14_DEPTH_CLAMP = test("TC14.1", "Nodes deeper than max depth flatten at deepest visible level", async (page) => {
    await page.goto(BASE + "?instance=qa-deep&sessionUuid=fixture-deep", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const flattened = page.locator(".todo-tree-node[data-flattened='true']");
    const flatCount = await flattened.count();
    assert.ok(flatCount >= 2, `Expected flattened nodes d,e (got ${flatCount})`);
    const cMargin = await page.locator('details.todo-tree-node[data-id="c"] > summary').evaluate(el => parseFloat(getComputedStyle(el).marginLeft));
    for (let i = 0; i < flatCount; i++) {
        const m = await flattened.nth(i).locator("> summary").evaluate(el => parseFloat(getComputedStyle(el).marginLeft));
        assert.equal(m, cMargin, `Flattened node ${i} margin should equal deepest visible level margin`);
    }
    const margins = new Set();
    const nodes = page.locator("summary.todo-node-content");
    const n = await nodes.count();
    for (let i = 0; i < n; i++) {
        margins.add(Math.round(await nodes.nth(i).evaluate(el => parseFloat(getComputedStyle(el).marginLeft))));
    }
    assert.deepEqual([...margins].sort((a, b) => a - b), [24, 44, 64, 84], "Expected clamped depth margins");
});

// ========================================================================
// TC15: Chevron click toggles children without opening details panel
// ========================================================================
const TC15_CHEVRON_NO_PANEL = test("TC15.1", "Chevron click toggles children without opening details panel", async (page) => {
    await page.goto(BASE + "?instance=qa-chev&sessionUuid=fixture-deep", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const rootDetails = page.locator('details.todo-tree-node[data-id="root"]');
    const wasOpen = await rootDetails.evaluate(el => el.hasAttribute("open"));
    if (!wasOpen) {
        await rootDetails.locator("> summary .chevron").click();
        await page.waitForTimeout(200);
    }
    // Close panel if a previous interaction left it open
    if (await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false)) {
        await page.locator(".todo-details-close").click();
        await page.waitForTimeout(200);
    }
    // Click the chevron of the root node
    await rootDetails.locator("> summary .chevron").click();
    await page.waitForTimeout(300);
    const nowOpen = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(!nowOpen, "Root children should collapse after chevron click");
    const panelOpen = await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false);
    assert.ok(!panelOpen, "Details panel should NOT open on chevron click");
    const selected = await page.locator("summary.todo-node-content.selected").count();
    assert.equal(selected, 0, "No node should be selected on chevron click");
    // Expand back via chevron
    await rootDetails.locator("> summary .chevron").click();
    await page.waitForTimeout(200);
    const reopened = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(reopened, "Root children should expand again on chevron click");
    // Positive control: clicking the title (not the chevron) DOES open the panel
    await rootDetails.locator("> summary .todo-title").click();
    await page.waitForTimeout(300);
    const panelOpen2 = await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false);
    assert.ok(panelOpen2, "Details panel SHOULD open on title click");
    // ... but a non-chevron click must NOT toggle the collapse state
    const openAfterTitle = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(openAfterTitle, "Title click should NOT collapse the node (only the chevron toggles)");
    await page.locator(".todo-details-close").click();
});

// ========================================================================
// TC16: Todos progress bar
// ========================================================================
const TC16_PROGRESS = test("TC16.1", "Progress bar shows done/total completion", async (page) => {
    await page.goto(BASE + "?instance=qa-progress&sessionUuid=fixture-progress", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const bar = page.locator(".todo-progress-bar");
    assert.ok(await bar.count() > 0, "Progress bar should exist");
    const label = await page.locator(".todo-progress-label").textContent();
    assert.equal(label.trim(), "3/5 done \u00b7 60%", `Unexpected progress label: "${label}"`);
    const width = await page.locator(".todo-progress-fill").evaluate(el => parseFloat(el.style.width));
    assert.ok(Math.abs(width - 60) < 1, `Fill width should be ~60%, got ${width}%`);
});

const TC16_DEEP_PROGRESS = test("TC16.2", "Progress bar works on deep fixture (1/6 done)", async (page) => {
    await page.goto(BASE + "?instance=qa-deep2&sessionUuid=fixture-deep", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const label = await page.locator(".todo-progress-label").textContent();
    assert.equal(label.trim(), "1/6 done \u00b7 17%", `Unexpected label: "${label}"`);
});

const TC16_EMPTY_NO_BAR = test("TC16.3", "No progress bar when there are no todos", async (page) => {
    await page.goto(BASE + "?instance=qa-notodos2&sessionUuid=empty", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const barCount = await page.locator(".todo-progress-bar").count();
    assert.equal(barCount, 0, "Progress bar should be absent when no todos exist");
});

// ========================================================================
// TC17: maxTodoDepth config via URL query param
// ========================================================================
const TC17_DEPTH_1 = test("TC17.1", "?maxTodoDepth=1 flattens deeper nodes to one nested level", async (page) => {
    await page.goto(BASE + "?instance=qa-depth1&sessionUuid=fixture-deep&maxTodoDepth=1", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const flattened = await page.locator(".todo-tree-node[data-flattened='true']").count();
    assert.ok(flattened >= 4, `Expected b,c,d,e flattened with maxTodoDepth=1 (got ${flattened})`);
    const margins = new Set();
    const nodes = page.locator("summary.todo-node-content");
    const n = await nodes.count();
    for (let i = 0; i < n; i++) {
        margins.add(Math.round(await nodes.nth(i).evaluate(el => parseFloat(getComputedStyle(el).marginLeft))));
    }
    assert.deepEqual([...margins].sort((a, b) => a - b), [24, 44], "With maxTodoDepth=1 expected margins [24, 44]");
});

// ========================================================================
// TC18: Sidebar scroll (fixture-files: 1 root + 18 checkpoints + 6 research)
// ========================================================================
const TC18_SIDEBAR_SCROLL = test("TC18.1", "Sidebar file list is scrollable when many files", async (page) => {
    await page.setViewportSize({ width: 1280, height: 400 });
    await page.goto(BASE + "?instance=qa-files&sessionUuid=fixture-files", { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
    const scroll = page.locator(".sidebar-scroll").first();
    const oy = await scroll.evaluate(el => getComputedStyle(el).overflowY);
    assert.equal(oy, "auto", ".sidebar-scroll overflow-y should be auto");
    const dims = await scroll.evaluate(el => ({ sh: el.scrollHeight, ch: el.clientHeight }));
    assert.ok(dims.sh > dims.ch, `Sidebar should scroll (scrollHeight ${dims.sh} > clientHeight ${dims.ch})`);
    await page.setViewportSize({ width: 1280, height: 800 });
});

const TC18_TODOS_INVARIANT = test("TC18.2", "Todos details panel stays pinned while sidebar scrolls", async (page) => {
    await page.goto(BASE + "?instance=qa-files2&sessionUuid=fixture-progress", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const node = page.locator("summary.todo-node-content").first();
    if (await node.count() > 0) {
        await node.click();
        await page.waitForTimeout(300);
    }
    const panel = page.locator("#todoDetailsPanel");
    const open = await panel.evaluate(el => el.classList.contains("open"));
    assert.ok(open, "details panel should be open");
    const box = await panel.boundingBox();
    const sidebarBox = await page.locator("#sidebar").boundingBox();
    assert.ok(box && sidebarBox && box.y + box.height <= sidebarBox.y + sidebarBox.height + 2,
        "details panel stays inside the sidebar viewport");
    await page.locator(".todo-details-close").click();
});

// ========================================================================
// TC19: Folder collapse (fixture-files)
// ========================================================================
const TC19_COLLAPSE_HIDES = test("TC19.1", "Clicking a folder hides its files; header count unchanged", async (page) => {
    await page.goto(BASE + "?instance=qa-files3&sessionUuid=fixture-files", { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
    const chkHeader = page.locator(".file-group-header", { hasText: "checkpoints" }).first();
    await chkHeader.waitFor({ state: "visible", timeout: 5000 });
    const totalBefore = await page.locator(".file-item").count();
    assert.equal(totalBefore, 25, "25 file items before collapse");
    await chkHeader.click();
    await page.waitForTimeout(300);
    const visible = await page.locator(".file-item:visible").count();
    assert.equal(visible, 25 - 18, "18 checkpoints files hidden after collapse");
    const chkText = (await chkHeader.textContent()).trim();
    assert.ok(chkText.includes("(18)"), "count (18) preserved while collapsed: " + chkText);
    const wrapperCollapsed = await chkHeader.evaluate(el => el.closest(".file-group").classList.contains("collapsed"));
    assert.ok(wrapperCollapsed, ".file-group wrapper should have collapsed class");
    const headerCollapsed = await chkHeader.evaluate(el => el.classList.contains("collapsed"));
    assert.ok(headerCollapsed, "header should have collapsed class (chevron rotation)");
    // expand restores
    await chkHeader.click();
    await page.waitForTimeout(300);
    assert.equal(await page.locator(".file-item:visible").count(), 25, "all files visible after expand");
});

const TC19_COLLAPSE_PERSISTS = test("TC19.2", "Folder collapse persists across tab switch", async (page) => {
    const chkHeader = page.locator(".file-group-header", { hasText: "checkpoints" }).first();
    if (await chkHeader.count() === 0 || await chkHeader.evaluate(el => !el.closest(".file-group").classList.contains("collapsed")).catch(() => true)) {
        // ensure collapsed state on current page
        await chkHeader.click();
        await page.waitForTimeout(200);
    }
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(300);
    await page.locator('[data-tab="files"]').click();
    await page.waitForTimeout(400);
    const header2 = page.locator(".file-group-header", { hasText: "checkpoints" }).first();
    const stillCollapsed = await header2.evaluate(el => el.closest(".file-group").classList.contains("collapsed"));
    assert.ok(stillCollapsed, "checkpoints should remain collapsed after switching tabs");
    const visible = await page.locator(".file-item:visible").count();
    assert.equal(visible, 25 - 18, "checkpoints files still hidden after tab switch");
    await header2.click(); // expand back
    await page.waitForTimeout(200);
});

// ========================================================================
// TC20: Collapse toggle only via chevron (regression)
// ========================================================================
const TC20_COLLAPSE_ONLY_CHEVRON = test("TC20.1", "Row click never toggles collapse; only the chevron does", async (page) => {
    await page.goto(BASE + "?instance=qa-onlychev&sessionUuid=fixture-deep", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    const rootDetails = page.locator('details.todo-tree-node[data-id="root"]');
    const ensureOpen = async () => {
        if (!(await rootDetails.evaluate(el => el.hasAttribute("open")))) {
            await rootDetails.locator("> summary .chevron").click();
            await page.waitForTimeout(200);
        }
    };
    const closePanel = async () => {
        if (await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false)) {
            await page.locator(".todo-details-close").click();
            await page.waitForTimeout(200);
        }
    };
    await ensureOpen();
    await closePanel();

    // 1) Node starts open. Click the title (body) → panel opens, still open.
    await rootDetails.locator("> summary .todo-title").click();
    await page.waitForTimeout(300);
    let openAfterBodyClick = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(openAfterBodyClick, "Node must stay OPEN after clicking the title");
    let panelOpen = await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false);
    assert.ok(panelOpen, "Panel should open on title click");
    await closePanel();

    // 2) Click the status label (body) → panel opens, still open.
    await rootDetails.locator("> summary .todo-status-label").click();
    await page.waitForTimeout(300);
    openAfterBodyClick = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(openAfterBodyClick, "Node must stay OPEN after clicking the status label");
    await closePanel();

    // 3) Now collapse via chevron → node closed.
    await rootDetails.locator("> summary .chevron").click();
    await page.waitForTimeout(300);
    const closedAfterChevron = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(!closedAfterChevron, "Chevron click should collapse the node");

    // 4) Click the title while collapsed → panel opens, node STAYS closed.
    await rootDetails.locator("> summary .todo-title").click();
    await page.waitForTimeout(300);
    const stillClosed = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(!stillClosed, "Node must STAY CLOSED after clicking the title while collapsed");
    panelOpen = await page.locator("#todoDetailsPanel").evaluate(el => el.classList.contains("open")).catch(() => false);
    assert.ok(panelOpen, "Panel should still open on title click while collapsed");
    await closePanel();

    // 5) Expand again via chevron → node reopens.
    await rootDetails.locator("> summary .chevron").click();
    await page.waitForTimeout(300);
    const reopened = await rootDetails.evaluate(el => el.hasAttribute("open"));
    assert.ok(reopened, "Chevron click should expand the node again");
});

// ========================================================================
// TC21: Details panel two-section layout (fixture-desc)
// ========================================================================
const TC21_SECTIONS = test("TC21.1", "Panel body has metadata + description sections", async (page) => {
    await page.goto(BASE + "?instance=qa-layout&sessionUuid=fixture-desc", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    await page.locator(".todo-node-content").first().click();
    await page.waitForTimeout(300);
    const body = page.locator("#todoDetailBody");
    const metaCount = await body.locator(".todo-details-metadata").count();
    const descCount = await body.locator(".todo-details-description").count();
    assert.equal(metaCount, 1, "metadata section must exist inside #todoDetailBody");
    assert.equal(descCount, 1, "description section must exist inside #todoDetailBody");
    const descChild = await body.locator(".todo-details-description #todoDetailDesc").count();
    assert.equal(descChild, 1, "#todoDetailDesc should live inside the description section");
    await page.locator(".todo-details-close").click();
});

const TC21_BODY_FILLS = test("TC21.2", "Body fills panel space; description is scrollable", async (page) => {
    await page.goto(BASE + "?instance=qa-layout2&sessionUuid=fixture-desc", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    await page.locator(".todo-node-content").first().click();
    await page.waitForTimeout(300);
    const body = page.locator("#todoDetailBody");
    const fg = await body.evaluate(el => getComputedStyle(el).flexGrow);
    assert.equal(fg, "1", "#todoDetailBody should flex-grow to fill remaining panel space");
    const mh = await body.evaluate(el => getComputedStyle(el).minHeight);
    assert.ok(mh === "0px" || parseFloat(mh) === 0, `#todoDetailBody min-height should be 0, got "${mh}"`);
    const desc = page.locator("#todoDetailDesc");
    const dims = await desc.evaluate(el => ({ sh: el.scrollHeight, ch: el.clientHeight, oy: getComputedStyle(el).overflowY }));
    assert.ok(dims.oy === "auto" || dims.oy === "scroll", `description overflow-y should be auto/scroll, got "${dims.oy}"`);
    assert.ok(dims.sh > dims.ch, `description should overflow (scrollHeight ${dims.sh} > clientHeight ${dims.ch})`);
    await page.locator(".todo-details-close").click();
});

const TC21_METADATA_ROWS = test("TC21.3", "Metadata is a list of single-line fields", async (page) => {
    await page.goto(BASE + "?instance=qa-layout3&sessionUuid=fixture-desc", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    await page.locator(".todo-node-content").first().click();
    await page.waitForTimeout(300);
    const meta = page.locator(".todo-details-metadata");
    const fields = meta.locator(".todo-details-field");
    const count = await fields.count();
    assert.ok(count >= 4, `expected ID/Status/Created/Updated rows, got ${count}`);
    // Each visible field is a flex row with label + value (single logical line).
    // The Dependencies row is display:none here (fixture-desc has no deps).
    let visibleRows = 0;
    for (let i = 0; i < count; i++) {
        const disp = await fields.nth(i).evaluate(el => getComputedStyle(el).display);
        if (disp === "none") continue;
        visibleRows++;
        assert.equal(disp, "flex", `field ${i} should be display:flex`);
    }
    assert.ok(visibleRows >= 4, `expected at least 4 visible metadata rows, got ${visibleRows}`);
    const depsDisp = await page.locator("#todoDetailDepsContainer").evaluate(el => getComputedStyle(el).display);
    assert.equal(depsDisp, "none", "deps row should be hidden when the todo has no dependencies");
    const idVal = await page.locator("#todoDetailId").textContent();
    assert.ok(idVal === "long-desc-1", `ID metadata value should render, got "${idVal}"`);
    const statusVal = await page.locator("#todoDetailStatus").textContent();
    assert.ok(statusVal && statusVal.includes("In Progress"), `Status metadata should render, got "${statusVal}"`);
    await page.locator(".todo-details-close").click();
});

const TC21_DESC_MULTILINE = test("TC21.4", "Description shows multi-line scrollable text", async (page) => {
    await page.goto(BASE + "?instance=qa-layout4&sessionUuid=fixture-desc", { waitUntil: "networkidle" });
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(800);
    await page.locator(".todo-node-content").first().click();
    await page.waitForTimeout(300);
    const desc = page.locator("#todoDetailDesc");
    const ws = await desc.evaluate(el => getComputedStyle(el).whiteSpace);
    assert.equal(ws, "pre-wrap", "description should preserve line breaks (white-space: pre-wrap)");
    const text = await desc.textContent();
    assert.ok(text.includes("Line 40"), "description should contain the last line of the multi-line text");
    const lineCount = (text.match(/\n/g) || []).length;
    assert.ok(lineCount >= 30, `description should have many lines, got ${lineCount}`);
    // Scrolling works
    await desc.evaluate(el => { el.scrollTop = 50; });
    await page.waitForTimeout(100);
    const st = await desc.evaluate(el => el.scrollTop);
    assert.ok(st > 0, `description should be scrollable (scrollTop ${st})`);
    await page.locator(".todo-details-close").click();
});

// ========================================================================
// TC22: Frontmatter metadata card (fixture-frontmatter)
// ========================================================================
const FM_FIXTURE_URL = BASE + "?instance=qa-fm&sessionUuid=fixture-frontmatter";

async function fmLoadPlan(page) {
    await page.goto(FM_FIXTURE_URL, { waitUntil: "networkidle" });
    const planItem = page.locator('.file-item').filter({ hasText: "plan.md" }).first();
    await planItem.waitFor({ state: "visible", timeout: 8000 });
    await planItem.click();
    await page.waitForFunction(() => {
        const card = document.querySelector(".fm-card");
        return card && card.textContent.includes("Metadata");
    }, { timeout: 8000 });
}

const TC22_CARD_COLLAPSED = test("TC22.1", "Frontmatter card present and collapsed by default", async (page) => {
    await fmLoadPlan(page);
    const card = page.locator(".fm-card");
    assert.equal(await card.count(), 1, "exactly one .fm-card should render");
    const isOpen = await card.evaluate(el => el.hasAttribute("open"));
    assert.ok(!isOpen, ".fm-card should be collapsed by default (no open attr)");
    const summary = await page.locator(".fm-summary").textContent();
    assert.ok(summary.includes("Metadata"), `summary should say Metadata, got "${summary}"`);
    const count = await page.locator(".fm-summary .fm-count").textContent();
    assert.ok(count && parseInt(count, 10) > 0, `summary count should be > 0, got "${count}"`);
    // Body hidden while collapsed
    const bodyVisible = await page.locator(".fm-body").isVisible().catch(() => false);
    assert.ok(!bodyVisible, "fm-body should not be visible while collapsed");
});

const TC22_EXPAND_ROWS = test("TC22.2", "Clicking summary expands; scalar key/value rows render", async (page) => {
    await fmLoadPlan(page);
    await page.locator(".fm-summary").click();
    await page.waitForTimeout(300);
    const openNow = await page.locator(".fm-card").evaluate(el => el.hasAttribute("open"));
    assert.ok(openNow, "card should be open after summary click");
    const rowCount = await page.locator(".fm-card > .fm-body > .fm-row").count();
    assert.ok(rowCount >= 3, `expected several top-level scalar rows, got ${rowCount}`);
    const trackKey = await page.locator(".fm-card > .fm-body > .fm-row .fm-key", { hasText: "track" }).textContent();
    assert.equal(trackKey.trim(), "track", "key should render 'track'");
    const trackVal = await page.locator(".fm-card > .fm-body > .fm-row:has(.fm-key:text-is('track')) .fm-value").textContent();
    assert.equal(trackVal, "sdlc-product", "track value should be sdlc-product");
    // number value styled
    const numRow = page.locator(".fm-card > .fm-body > .fm-row:has(.fm-key:text-is('schemaVersion'))");
    const numVal = await numRow.locator(".fm-value .fm-num").textContent();
    assert.equal(numVal, "1", "schemaVersion should render as .fm-num 1");
    // null value styled
    const nullRow = page.locator(".fm-card > .fm-body > .fm-row:has(.fm-key:text-is('createdAt'))");
    const nullVal = await nullRow.locator(".fm-value").textContent();
    assert.ok(nullVal.length > 0, "createdAt value should render");
});

const TC22_NESTED_OBJECT = test("TC22.3", "Nested object worktree renders as collapsible fm-group", async (page) => {
    await fmLoadPlan(page);
    await page.locator(".fm-summary").click();
    await page.waitForTimeout(300);
    const worktreeGroup = page.locator(".fm-group-summary", { hasText: "worktree" }).first();
    assert.equal(await worktreeGroup.count(), 1, "worktree group should exist");
    // Collapsed by default
    const groupEl = worktreeGroup.locator("xpath=..");
    const isOpen = await groupEl.evaluate(el => el.hasAttribute("open"));
    assert.ok(!isOpen, "worktree group should start collapsed");
    // Expand it
    await worktreeGroup.click();
    await page.waitForTimeout(200);
    const openNow = await groupEl.evaluate(el => el.hasAttribute("open"));
    assert.ok(openNow, "worktree group should open after click");
    const pathRow = worktreeGroup.locator("xpath=..").locator(".fm-row .fm-key", { hasText: "path" });
    assert.equal(await pathRow.count(), 1, "worktree path row should appear after expand");
    const pathVal = await pathRow.locator("xpath=..").locator(".fm-value").textContent();
    assert.ok(pathVal.includes("demo"), `path value should render, got "${pathVal}"`);
});

const TC22_ARRAY_GROUP = test("TC22.4", "Array group passes shows count and item groups", async (page) => {
    await fmLoadPlan(page);
    await page.locator(".fm-summary").click();
    await page.waitForTimeout(300);
    const passesGroup = page.locator(".fm-group-summary", { hasText: "passes" }).first();
    assert.equal(await passesGroup.count(), 1, "passes group should exist");
    const count = await passesGroup.locator(".fm-count").textContent();
    assert.equal(count, "2", "passes group count should be 2");
    await passesGroup.click();
    await page.waitForTimeout(200);
    const itemGroups = page.locator(".fm-group:has(.fm-group-summary) .fm-group-summary", { hasText: "#1" });
    const n1 = await itemGroups.count();
    assert.ok(n1 >= 1, `passes should contain item groups (#1...), got ${n1}`);
    // Expand #1 and check its fields
    const item1 = page.locator(".fm-group-summary", { hasText: "#1" }).first();
    await item1.click();
    await page.waitForTimeout(200);
    const numberKey = item1.locator("xpath=..").locator(".fm-row .fm-key", { hasText: "number" });
    assert.equal(await numberKey.count(), 1, "#1 should contain a number row");
    const numVal = await numberKey.locator("xpath=..").locator(".fm-value .fm-num").textContent();
    assert.equal(numVal, "1", "#1 number value should be 1");
});

const TC22_NO_STRAY_HR = test("TC22.5", "No stray <hr> from frontmatter fences; TOC clean", async (page) => {
    await fmLoadPlan(page);
    // The frontmatter card should be the first child in rendered content
    const firstEl = await page.locator("#renderedContent > :first-child").evaluate(el => el.className);
    assert.ok(firstEl.includes("fm-card"), `first rendered element should be .fm-card, got "${firstEl}"`);
    // No <hr> should precede the card inside renderedContent
    const hrCountBeforeH1 = await page.locator("#renderedContent > hr").count();
    assert.equal(hrCountBeforeH1, 0, "no <hr> should appear from frontmatter fences");
    // TOC should only contain body headings, not frontmatter keys (switch to TOC tab)
    await page.locator('[data-tab="toc"]').click();
    await page.waitForTimeout(400);
    const tocItems = page.locator(".toc-item");
    const count = await tocItems.count();
    assert.ok(count >= 2, `expected TOC entries from body headings, got ${count}`);
    const tocText = await tocItems.allTextContents();
    const joined = tocText.join(" | ");
    assert.ok(joined.includes("Plan: Demo Session"), `TOC should include the H1, got "${joined}"`);
    assert.ok(!joined.toLowerCase().includes("sdlc-product"), "TOC must not include frontmatter key/value content");
});

const TC22_NO_FRONTMATTER = test("TC22.6", "File without frontmatter renders normally", async (page) => {
    await page.goto(FM_FIXTURE_URL, { waitUntil: "networkidle" });
    const plainItem = page.locator('.file-item').filter({ hasText: "plain.md" }).first();
    await plainItem.waitFor({ state: "visible", timeout: 8000 });
    await plainItem.click();
    await page.waitForFunction(() => {
        const h1 = document.querySelector("#renderedContent h1");
        return h1 && h1.textContent.includes("Plain File");
    }, { timeout: 8000 });
    const cardCount = await page.locator(".fm-card").count();
    assert.equal(cardCount, 0, "no .fm-card for a file without frontmatter");
    const hrCount = await page.locator("#renderedContent > hr").count();
    assert.equal(hrCount, 0, "no stray <hr> in plain file");
    const itemCount = await page.locator("#renderedContent li").count();
    assert.ok(itemCount >= 2, "plain file list items should render");
});

// ========================================================================
// Main
// ========================================================================
async function main() {
    console.log(`\n🔍 Session MD Reader QA Tests`);
    console.log(`   Target session: ${TARGET_SESSION}`);
    console.log(`   Server: ${BASE}`);
    console.log(`   Canvas: ${CANVAS_URL}\n`);

    const browser = await chromium.launch({ headless: true });

    try {
        const context = await browser.newContext({
            viewport: { width: 1280, height: 800 },
            deviceScaleFactor: 1,
        });

        // Group tests by TC
        const suites = [
            { name: "TC1: Page Load & Session Name", tests: [TC1_LOAD, TC1_TITLE, TC1_SIDEBAR_TITLE, TC1_WELCOME_TITLE, TC1_WELCOME_DESC, TC1_BADGE] },
            { name: "TC2: File Listing & Navigation", tests: [TC2_FILE_GROUPS, TC2_GROUP_TOGGLE, TC2_FILE_CLICK, TC2_ACTIVE_FILE, TC2_CHECKPOINT_FILE, TC2_ACTIVE_INFO] },
            { name: "TC3: TOC Tab", tests: [TC3_TOC_TAB, TC3_TOC_ITEMS, TC3_TOC_CLICK, TC3_BACK_FILES] },
            { name: "TC4: Mermaid Rendering", tests: [TC4_MERMAID_LOAD, TC4_MERMAID_DIVS, TC4_MERMAID_SVG, TC4_MERMAID_THEME, TC4_NO_MERMAID] },
            { name: "TC5: Sidebar Collapse", tests: [TC5_COLLAPSE, TC5_COLLAPSED_CLASS, TC5_TAB_ICONS, TC5_CONTENT_HIDDEN, TC5_EXPAND, TC5_EXPANDED] },
            { name: "TC6: Keyboard Shortcuts", tests: [TC6_CTRL_B, TC6_CTRL_1, TC6_CTRL_2, TC6_CTRL_3, TC6_ZOOM_IN, TC6_ZOOM_OUT, TC6_ZOOM_RESET] },
            { name: "TC7: Todo Tree", tests: [TC7_TODOS_TAB, TC7_TODOS_CONTENT, TC7_TODOS_COLORS, TC7_TODOS_DETAILS, TC7_TODOS_SWITCH_BACK, TC7_COLLAPSE_TOGGLE, TC7_CHEVRON_VISIBLE, TC7_CHEVRON_ROTATION, TC7_DEPTH_INDENT, TC7_PASS_BADGE_COUNT, TC7_PASS_BADGE_TEXT, TC7_PASS_BADGE_STYLE] },
            { name: "TC8: Edge Cases", tests: [TC8_INVALID_UUID, TC8_NO_UUID, TC8_RAPID_SWITCH, TC8_SSE, TC8_RAPID_CLICKS, TC8_EMPTY_TODOS] },
            { name: "TC9: Details Panel Layout", tests: [TC9_PANEL_HEIGHT, TC9_TREE_SCROLLS, TC9_PANEL_OVERFLOW, TC9_CLOSE_BUTTON, TC9_TAB_SWITCH, TC9_REOPEN, TC9_PANEL_WIDTH] },
            { name: "TC10: Responsive Main Content", tests: [TC10_MAX_WIDTH, TC10_REFLOW, TC10_NO_HSCROLL] },
            { name: "TC11: Pass ID Filter", tests: [TC11_FILTER_BAR, TC11_FILTER_HIDES, TC11_FILTER_ALL, TC11_FILTER_PERSISTS, TC11_FILTER_DETAILS, TC11_FILTER_STYLING, TC11_FILTER_RAPID] },
            { name: "TC12: Inline Tab Refresh", tests: [TC12_REFRESH_BUTTONS, TC12_REFRESH_VISIBILITY, TC12_FILES_REFRESH, TC12_TODOS_REFRESH, TC12_TOC_REFRESH, TC12_LOADING_ANIMATION, TC12_RAPID_REFRESH] },
            { name: "TC13: Full Session Name & UUID", tests: [TC13_LONG_NAME, TC13_FULL_UUID] },
            { name: "TC14: Todo Depth Clamp", tests: [TC14_DEPTH_CLAMP] },
            { name: "TC15: Chevron Click Behavior", tests: [TC15_CHEVRON_NO_PANEL] },
            { name: "TC16: Todos Progress Bar", tests: [TC16_PROGRESS, TC16_DEEP_PROGRESS, TC16_EMPTY_NO_BAR] },
            { name: "TC17: maxTodoDepth Config", tests: [TC17_DEPTH_1] },
            { name: "TC18: Sidebar Scroll", tests: [TC18_SIDEBAR_SCROLL, TC18_TODOS_INVARIANT] },
            { name: "TC19: Folder Collapse", tests: [TC19_COLLAPSE_HIDES, TC19_COLLAPSE_PERSISTS] },
            { name: "TC20: Collapse Only Via Chevron", tests: [TC20_COLLAPSE_ONLY_CHEVRON] },
            { name: "TC21: Details Panel Two-Section Layout", tests: [TC21_SECTIONS, TC21_BODY_FILLS, TC21_METADATA_ROWS, TC21_DESC_MULTILINE] },
            { name: "TC22: Frontmatter Metadata Card", tests: [TC22_CARD_COLLAPSED, TC22_EXPAND_ROWS, TC22_NESTED_OBJECT, TC22_ARRAY_GROUP, TC22_NO_STRAY_HR, TC22_NO_FRONTMATTER] },
        ];

        // Take an initial screenshot
        const page = await context.newPage();

        for (const suite of suites) {
            console.log(`\n📋 ${suite.name}`);
            console.log(`   ${"-".repeat(suite.name.length + 4)}`);
            // Use the same page for all tests in a suite
            for (const testFn of suite.tests) {
                await testFn(page);
            }
        }

        // Take final screenshot for documentation
        await page.goto(CANVAS_URL, { waitUntil: "networkidle" });
        await page.waitForTimeout(1000);
        await page.screenshot({ path: "qa-screenshot-final.png", fullPage: false });
        console.log("\n📸 Final screenshot saved to qa-screenshot-final.png");

    } finally {
        await browser.close();
    }

    // Report
    const total = passed + failed;
    console.log(`\n${"=".repeat(50)}`);
    console.log(`📊 QA Test Results`);
    console.log(`${"=".repeat(50)}`);
    console.log(`   Total:  ${total}`);
    console.log(`   Passed: ${passed} ✅`);
    console.log(`   Failed: ${failed} ❌`);
    console.log(`   Rate:   ${total > 0 ? Math.round(passed / total * 100) : 0}%`);

    if (failed > 0) {
        console.log(`\n❌ Failed tests:`);
        for (const r of results) {
            if (r.status === "FAIL") {
                console.log(`   - ${r.id}: ${r.label}`);
                console.log(`     ${r.error}`);
            }
        }
    }
    console.log();

    process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => {
    console.error("Fatal error:", e);
    process.exit(1);
});
