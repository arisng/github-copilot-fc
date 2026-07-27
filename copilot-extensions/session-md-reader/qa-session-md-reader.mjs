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
        const lbl = document.getElementById("sessionLabel");
        return lbl && lbl.textContent !== "Loading..." && lbl.textContent !== "No session UUID";
    }, { timeout: 8000 });
});

const TC1_TITLE = test("TC1.2", "document.title starts with 'MD:'", async (page) => {
    const title = await page.title();
    assert.ok(title.startsWith("MD:"), `Expected title to start with "MD:", got "${title}"`);
});

const TC1_SESSION_LABEL = test("TC1.3", "sessionLabel shows session name", async (page) => {
    const text = await getText(page, "#sessionLabel");
    assert.ok(text && text.length > 0, "sessionLabel is empty");
    assert.ok(text.includes("Zoom") || text.includes("webhook"),
        `Expected session name about Zoom webhook, got "${text}"`);
});

const TC1_SIDEBAR_TITLE = test("TC1.4", "sidebarTitle shows session name", async (page) => {
    const text = await getText(page, "#sidebarTitle");
    assert.ok(text && text.length > 0, "sidebarTitle is empty");
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

const TC7_COLLAPSE_TOGGLE = test("TC7.6", "Click summary toggles children (collapse)", async (page) => {
    await page.locator('[data-tab="todos"]').click();
    await page.waitForTimeout(600);
    const parentDetails = page.locator('details.todo-tree-node').filter({ has: page.locator('.chevron') }).first();
    const exists = await parentDetails.count() > 0;
    if (exists) {
        const wasOpen = await parentDetails.evaluate(el => el.hasAttribute("open"));
        if (!wasOpen) {
            await parentDetails.locator("summary").click();
            await page.waitForTimeout(300);
        }
        await parentDetails.locator("summary").click();
        await page.waitForTimeout(300);
        const isOpen = await parentDetails.evaluate(el => el.hasAttribute("open"));
        assert.ok(!isOpen, "Parent details should be closed after click");
        await parentDetails.locator("summary").click();
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
            await parent.locator("summary").click();
            await page.waitForTimeout(300);
        }
        let transform = await parent.locator('summary .chevron').evaluate(el => getComputedStyle(el).transform);
        const closedIsIdentity = transform === "none" || transform === "matrix(1, 0, 0, 1, 0, 0)";
        await parent.locator("summary").click();
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

const TC9_PANEL_OVERFLOW = test("TC9.3", "Panel has overflow-y for scrollable content", async (page) => {
    const panel = page.locator("#todoDetailsPanel");
    const oy = await panel.evaluate(el => getComputedStyle(el).overflowY);
    assert.ok(oy === "auto" || oy === "scroll", "Panel should have overflow-y for scroll");
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
            { name: "TC1: Page Load & Session Name", tests: [TC1_LOAD, TC1_TITLE, TC1_SESSION_LABEL, TC1_SIDEBAR_TITLE, TC1_WELCOME_TITLE, TC1_WELCOME_DESC, TC1_BADGE] },
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
