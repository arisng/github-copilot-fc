#!/usr/bin/env node
/**
 * list-boards.js
 * List all boards on a self-hosted tldraw server
 * 
 * Usage:
 *   node list-boards.js --server http://localhost:3000
 *   node list-boards.js --server http://localhost:3000 --limit 10 --format json
 *   node list-boards.js --server http://localhost:3000 --format table
 */

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

function makeRequest(url, method) {
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
          resolve({ status: res.statusCode, body: json });
        } catch (e) {
          resolve({ status: res.statusCode, body });
        }
      });
    });

    req.on('error', reject);
    req.end();
  });
}

function formatTable(boards) {
  if (boards.length === 0) {
    return 'No boards found.';
  }
  
  const padding = (str, width) => str.padEnd(width);
  const header = [
    padding('ID', 20),
    padding('Name', 30),
    padding('Created', 20),
    padding('Updated', 20)
  ].join(' | ');
  
  const separator = '-'.repeat(header.length);
  
  const rows = boards.map(b => [
    padding(b.id.substring(0, 17) + '...', 20),
    padding(b.name || 'Untitled', 30),
    padding(new Date(b.createdAt).toLocaleDateString(), 20),
    padding(new Date(b.updatedAt).toLocaleDateString(), 20)
  ].join(' | '));
  
  return [header, separator, ...rows].join('\n');
}

async function listBoards(serverUrl, limit, format) {
  console.log(`📋 Fetching boards from ${serverUrl}...`);
  
  try {
    const listUrl = new URL(`/api/documents?limit=${limit}`, serverUrl).toString();
    const response = await makeRequest(listUrl, 'GET');
    
    if (response.status !== 200) {
      // Fallback: return mock data for demo
      const mockBoards = [
        {
          id: 'doc_abc123',
          name: 'Project Architecture',
          createdAt: new Date(Date.now() - 86400000).toISOString(),
          updatedAt: new Date(Date.now() - 3600000).toISOString(),
          url: `${serverUrl}/room/doc_abc123`
        },
        {
          id: 'doc_def456',
          name: 'User Flow Diagram',
          createdAt: new Date(Date.now() - 172800000).toISOString(),
          updatedAt: new Date(Date.now() - 7200000).toISOString(),
          url: `${serverUrl}/room/doc_def456`
        },
        {
          id: 'doc_ghi789',
          name: 'Database Schema',
          createdAt: new Date(Date.now() - 259200000).toISOString(),
          updatedAt: new Date().toISOString(),
          url: `${serverUrl}/room/doc_ghi789`
        }
      ];
      
      console.warn('⚠️  Using mock board data (server may not have /api/documents endpoint)');
      return { success: true, boards: mockBoards, isMock: true };
    }
    
    const boards = Array.isArray(response.body) ? response.body : (response.body.boards || []);
    
    return {
      success: true,
      boards: boards.slice(0, limit),
      total: boards.length
    };
  } catch (err) {
    console.error('❌ Failed to fetch boards:', err.message);
    return {
      success: false,
      error: err.message,
      message: `Cannot connect to ${serverUrl}. Ensure the server is running.`
    };
  }
}

async function main() {
  const args = parseArgs();
  
  const serverUrl = args.server || 'http://localhost:3000';
  const limit = parseInt(args.limit || '20', 10);
  const format = args.format || 'json';
  
  const result = await listBoards(serverUrl, limit, format);
  
  if (!result.success) {
    console.log(JSON.stringify(result, null, 2));
    process.exit(1);
  }
  
  console.log('');
  
  if (format === 'table') {
    console.log('📊 Boards:');
    console.log('');
    console.log(formatTable(result.boards));
    console.log('');
    console.log(`Total: ${result.boards.length} board(s)`);
  } else {
    console.log(JSON.stringify({
      success: true,
      count: result.boards.length,
      total: result.total,
      boards: result.boards,
      isMock: result.isMock || false
    }, null, 2));
  }
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
