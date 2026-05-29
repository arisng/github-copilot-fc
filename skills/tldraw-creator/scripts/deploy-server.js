#!/usr/bin/env node
/**
 * deploy-server.js
 * Deploy a self-hosted tldraw instance using Docker or Node.js
 * 
 * Usage:
 *   node deploy-server.js --type docker --port 3000
 *   node deploy-server.js --type nodejs --database postgresql://localhost/tldraw
 */

const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

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

async function generateDockerCompose(options) {
  const compose = `version: '3.8'
services:
  tldraw:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - .:/app
    ports:
      - "${options.port}:3000"
    environment:
      NODE_ENV: ${options.env || 'development'}
      DATABASE_URL: ${options.database || 'postgresql://tldraw:password@postgres:5432/tldraw'}
      PORT: 3000
    depends_on:
      - postgres
    command: npm start

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: tldraw
      POSTGRES_PASSWORD: password
      POSTGRES_DB: tldraw
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

volumes:
  postgres_data:
`;
  return compose;
}

async function generateNginxConfig(options) {
  const config = `upstream tldraw {
  server localhost:${options.port};
}

server {
  listen 443 ssl http2;
  server_name ${options.domain || 'tldraw.example.com'};

  ssl_certificate /etc/ssl/certs/tldraw.crt;
  ssl_certificate_key /etc/ssl/private/tldraw.key;

  # WebSocket support
  map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
  }

  location / {
    proxy_pass http://tldraw;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_buffering off;
  }
}

server {
  listen 80;
  server_name ${options.domain || 'tldraw.example.com'};
  return 301 https://$server_name$request_uri;
}
`;
  return config;
}

async function deployDocker(options) {
  console.log('🐳 Deploying tldraw with Docker...');
  
  const compose = await generateDockerCompose(options);
  const composePath = path.join(process.cwd(), 'docker-compose.yml');
  fs.writeFileSync(composePath, compose, 'utf-8');
  
  console.log(`📝 Generated docker-compose.yml at ${composePath}`);
  
  try {
    const { stdout } = await execAsync('docker-compose up -d', { cwd: process.cwd() });
    console.log('✅ Docker containers started');
    
    return {
      success: true,
      serverUrl: `http://localhost:${options.port || 3000}`,
      status: 'running',
      containerName: 'tldraw',
      composePath,
      logs: stdout,
      message: `tldraw server is running at http://localhost:${options.port || 3000}. Run 'docker-compose logs -f' to view logs.`
    };
  } catch (err) {
    console.error('❌ Docker deployment failed:', err.message);
    return {
      success: false,
      error: err.message,
      message: 'Failed to start Docker containers. Ensure Docker is installed and running.'
    };
  }
}

async function deployNodeJS(options) {
  console.log('🚀 Deploying tldraw with Node.js...');
  
  const serverScript = `const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// API endpoints would go here
app.get('/api/documents', (req, res) => {
  res.json({ documents: [] });
});

const PORT = process.env.PORT || ${options.port || 3000};
app.listen(PORT, () => {
  console.log(\`tldraw server running on http://localhost:\${PORT}\`);
});
`;

  const serverPath = path.join(process.cwd(), 'server.js');
  fs.writeFileSync(serverPath, serverScript, 'utf-8');
  
  console.log(`📝 Generated server.js at ${serverPath}`);
  
  try {
    // Check if node_modules/express exists
    const hasExpress = fs.existsSync(path.join(process.cwd(), 'node_modules', 'express'));
    
    if (!hasExpress) {
      console.log('📦 Installing dependencies...');
      await execAsync('npm install express cors @tldraw/store @tldraw/tlschema', { cwd: process.cwd() });
    }
    
    return {
      success: true,
      serverUrl: `http://localhost:${options.port || 3000}`,
      status: 'ready',
      serverPath,
      message: `tldraw server configured. Run 'node ${serverPath}' to start.`,
      nextSteps: [
        `npm install express cors @tldraw/store @tldraw/tlschema`,
        `node ${serverPath}`,
        `Visit http://localhost:${options.port || 3000}`
      ]
    };
  } catch (err) {
    console.error('❌ Node.js deployment failed:', err.message);
    return {
      success: false,
      error: err.message,
      message: 'Failed to set up Node.js server.'
    };
  }
}

async function main() {
  const args = parseArgs();
  
  const deploymentType = args.type || 'docker';
  const port = args.port || 3000;
  const database = args.database || 'postgresql://tldraw:password@localhost:5432/tldraw';
  const env = args.env || 'development';
  
  console.log('🎯 tldraw Server Deployment');
  console.log(`  Type: ${deploymentType}`);
  console.log(`  Port: ${port}`);
  console.log(`  Environment: ${env}`);
  console.log('');
  
  let result;
  
  if (deploymentType === 'docker') {
    result = await deployDocker({ port, database, env });
  } else if (deploymentType === 'nodejs') {
    result = await deployNodeJS({ port });
  } else {
    console.error('Unknown deployment type. Use --type docker or --type nodejs');
    process.exit(1);
  }
  
  console.log('');
  console.log(JSON.stringify(result, null, 2));
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
