#!/usr/bin/env node
/**
 * import-board.js
 * Import a .tldraw board file to a running self-hosted tldraw server
 * 
 * Usage:
 *   node import-board.js --server http://localhost:3000 --board my-diagram.tldraw
 *   node import-board.js --server http://localhost:3000 --json board-data.json --name "My Board"
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

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

function makeRequest(url, method, data) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const protocol = urlObj.protocol === 'https:' ? https : http;
    
    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port,
      path: urlObj.pathname + urlObj.search,
      method: method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = protocol.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          resolve({ status: res.statusCode, body: json, headers: res.headers });
        } catch (e) {
          resolve({ status: res.statusCode, body, headers: res.headers });
        }
      });
    });

    req.on('error', reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

async function importBoard(serverUrl, boardData, boardName) {
  const boardId = boardData.document?.id || `doc_${Math.random().toString(36).substr(2, 9)}`;
  
  // Check server health
  console.log('🔍 Checking server health...');
  try {
    const healthUrl = new URL('/health', serverUrl).toString();
    const health = await makeRequest(healthUrl, 'GET');
    if (health.status !== 200) {
      throw new Error(`Server health check failed: ${health.status}`);
    }
    console.log('✅ Server is healthy');
  } catch (err) {
    console.error('❌ Server health check failed:', err.message);
    return {
      success: false,
      error: err.message,
      message: `Cannot connect to server at ${serverUrl}. Ensure the server is running.`
    };
  }
  
  // Import board
  console.log(`📤 Importing board: ${boardName || boardId}...`);
  try {
    const importUrl = new URL('/api/documents/import', serverUrl).toString();
    const importData = {
      id: boardId,
      name: boardName || 'Untitled',
      data: boardData
    };
    
    const result = await makeRequest(importUrl, 'POST', importData);
    
    if (result.status >= 200 && result.status < 300) {
      const viewUrl = new URL(`/room/${boardId}`, serverUrl).toString();
      const editUrl = new URL(`/edit/${boardId}`, serverUrl).toString();
      
      console.log('✅ Board imported successfully');
      
      return {
        success: true,
        boardId,
        boardName: boardName || 'Untitled',
        viewUrl,
        editUrl,
        message: `Board imported. Open in browser: ${viewUrl}`
      };
    } else {
      return {
        success: false,
        status: result.status,
        error: result.body?.error || 'Unknown error',
        message: `Import failed with status ${result.status}`
      };
    }
  } catch (err) {
    console.error('❌ Import failed:', err.message);
    return {
      success: false,
      error: err.message,
      message: 'Failed to import board. Check server logs for details.'
    };
  }
}

async function main() {
  const args = parseArgs();
  
  const serverUrl = args.server || 'http://localhost:3000';
  const boardPath = args.board;
  const jsonPath = args.json;
  const boardName = args.name;
  
  let boardData;
  
  if (boardPath) {
    if (!fs.existsSync(boardPath)) {
      console.error(`❌ Board file not found: ${boardPath}`);
      process.exit(1);
    }
    
    console.log(`📖 Reading board file: ${boardPath}`);
    const content = fs.readFileSync(boardPath, 'utf-8');
    boardData = JSON.parse(content);
  } else if (jsonPath) {
    if (!fs.existsSync(jsonPath)) {
      console.error(`❌ JSON file not found: ${jsonPath}`);
      process.exit(1);
    }
    
    console.log(`📖 Reading JSON file: ${jsonPath}`);
    const content = fs.readFileSync(jsonPath, 'utf-8');
    boardData = JSON.parse(content);
  } else {
    // Demo: create sample board data
    console.log('📝 No board file specified, creating demo board...');
    boardData = {
      version: 15,
      document: {
        id: `doc_${Math.random().toString(36).substr(2, 9)}`,
        pages: {
          [`page_demo`]: {
            id: 'page_demo',
            name: 'Demo Page',
            shapes: {
              shape_1: {
                id: 'shape_1',
                type: 'geo',
                x: 100,
                y: 100,
                rotation: 0,
                props: { w: 150, h: 80, geo: 'rectangle', color: 'blue', text: 'Node A' }
              },
              shape_2: {
                id: 'shape_2',
                type: 'geo',
                x: 350,
                y: 100,
                rotation: 0,
                props: { w: 150, h: 80, geo: 'rectangle', color: 'green', text: 'Node B' }
              }
            },
            bindings: {}
          }
        },
        assets: {},
        pageStates: {}
      }
    };
  }
  
  console.log('');
  console.log(`🚀 Importing to: ${serverUrl}`);
  console.log('');
  
  const result = await importBoard(serverUrl, boardData, boardName);
  
  console.log('');
  console.log(JSON.stringify(result, null, 2));
  
  if (!result.success) {
    process.exit(1);
  }
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
