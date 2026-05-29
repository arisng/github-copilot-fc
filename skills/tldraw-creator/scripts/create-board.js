#!/usr/bin/env node
/**
 * create-board.js
 * Programmatically create a tldraw whiteboard with shapes, text, and connectors
 * 
 * Usage:
 *   node create-board.js --name my-diagram --title "My Diagram" --config config.json
 *   node create-board.js --shapes '[{"type":"geo","x":100,"y":100,...}]'
 */

const fs = require('fs');
const path = require('path');

// Mock implementation (requires @tldraw/store in real usage)
class TLBoard {
  constructor(name, title) {
    this.name = name;
    this.title = title;
    this.version = 15;
    this.shapes = [];
    this.bindings = [];
    this.document = {
      id: `doc_${generateId()}`,
      pages: {
        [`page_${generateId()}`]: {
          id: `page_${generateId()}`,
          name: 'Page 1',
          shapes: {},
          bindings: {}
        }
      },
      assets: {},
      pageStates: {}
    };
  }

  addShape(shapeConfig) {
    const shapeId = `shape_${generateId()}`;
    const shape = {
      id: shapeId,
      type: shapeConfig.type || 'geo',
      x: shapeConfig.x || 0,
      y: shapeConfig.y || 0,
      rotation: shapeConfig.rotation || 0,
      props: {
        w: shapeConfig.props?.w || 200,
        h: shapeConfig.props?.h || 100,
        geo: shapeConfig.props?.geo || 'rectangle',
        color: shapeConfig.props?.color || 'blue',
        text: shapeConfig.props?.text || '',
        fill: shapeConfig.props?.fill || 'solid',
        opacityForShape: shapeConfig.props?.opacityForShape || 1,
        ...shapeConfig.props
      }
    };
    
    const pageKey = Object.keys(this.document.pages)[0];
    this.document.pages[pageKey].shapes[shapeId] = shape;
    this.shapes.push(shapeId);
    return shapeId;
  }

  addArrow(fromShapeId, toShapeId, label = '') {
    const bindingId = `binding_${generateId()}`;
    const binding = {
      id: bindingId,
      type: 'arrow',
      fromId: fromShapeId,
      toId: toShapeId,
      props: { end: 'arrow' }
    };

    const pageKey = Object.keys(this.document.pages)[0];
    this.document.pages[pageKey].bindings[bindingId] = binding;
    this.bindings.push(bindingId);
    return bindingId;
  }

  export() {
    return {
      version: this.version,
      document: this.document
    };
  }

  save(filePath) {
    const json = JSON.stringify(this.export(), null, 2);
    fs.writeFileSync(filePath, json, 'utf-8');
    return filePath;
  }
}

function generateId() {
  return Math.random().toString(36).substr(2, 9);
}

function parseArgs() {
  const args = process.argv.slice(2);
  const result = {};
  
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].slice(2);
      result[key] = args[i + 1];
      i++;
    }
  }
  
  return result;
}

async function main() {
  const args = parseArgs();
  
  const name = args.name || 'untitled-board';
  const title = args.title || 'Untitled Board';
  const configPath = args.config;
  
  let shapes = [];
  if (args.shapes) {
    try {
      shapes = JSON.parse(args.shapes);
    } catch (err) {
      console.error('Failed to parse --shapes JSON:', err.message);
      process.exit(1);
    }
  } else if (configPath && fs.existsSync(configPath)) {
    try {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      shapes = config.shapes || [];
    } catch (err) {
      console.error('Failed to read config file:', err.message);
      process.exit(1);
    }
  } else if (!args.shapes && !configPath) {
    // Demo: create a simple 3-component diagram
    shapes = [
      {
        type: 'geo',
        x: 100,
        y: 100,
        props: { w: 150, h: 80, color: 'blue', text: 'Frontend' }
      },
      {
        type: 'geo',
        x: 400,
        y: 100,
        props: { w: 150, h: 80, color: 'green', text: 'Backend' }
      },
      {
        type: 'geo',
        x: 250,
        y: 300,
        props: { w: 150, h: 80, color: 'orange', text: 'Database' }
      }
    ];
  }
  
  // Create board
  const board = new TLBoard(name, title);
  const shapeIds = [];
  
  for (const shapeConfig of shapes) {
    const id = board.addShape(shapeConfig);
    shapeIds.push(id);
  }
  
  // Add sample connections (first shape -> second, second -> third)
  if (shapeIds.length >= 2) {
    board.addArrow(shapeIds[0], shapeIds[1]);
  }
  if (shapeIds.length >= 3) {
    board.addArrow(shapeIds[1], shapeIds[2]);
  }
  
  // Save to file
  const outputDir = process.cwd();
  const boardPath = path.join(outputDir, `${name}.tldraw`);
  board.save(boardPath);
  
  console.log(JSON.stringify({
    success: true,
    boardId: board.document.id,
    boardName: name,
    exportPath: boardPath,
    shapeCount: shapeIds.length,
    bindingCount: board.bindings.length,
    message: `Board created successfully: ${boardPath}`
  }, null, 2));
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
