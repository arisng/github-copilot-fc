# Deployment Guide: tldraw Self-Hosted Server

Complete guide for deploying a self-hosted tldraw instance for production and development.

## Prerequisites

- **Docker** (for containerized deployment): https://docs.docker.com/get-docker/
- **Node.js 18+** (for Node.js deployment or as base image)
- **PostgreSQL 12+** (optional, for persistent storage)
- **Nginx** (optional, for reverse proxy and SSL/TLS)
- **Git** (for cloning the tldraw repository)

## Quick Start: Docker

### 1. Generate Configuration

```bash
node deploy-server.js --type docker --port 3000
```

This creates `docker-compose.yml` with:
- tldraw web service (Node.js 18 Alpine)
- PostgreSQL database
- Volume management

### 2. Start Containers

```bash
docker-compose up -d
```

### 3. Verify Deployment

```bash
curl http://localhost:3000/health
# Response: {"status":"ok","timestamp":"2026-04-26T12:00:00Z"}
```

### 4. Access tldraw

Open browser: `http://localhost:3000`

## Production Deployment: Docker + Nginx + PostgreSQL

### Architecture

```
Client Browser
  ↓ (HTTPS)
Nginx Reverse Proxy (port 443)
  ↓ (HTTP + WebSocket)
tldraw Server (port 3000, internal)
  ↓
PostgreSQL Database (port 5432, internal)
```

### 1. Setup PostgreSQL

```bash
# Create database and user
psql -U postgres
CREATE DATABASE tldraw;
CREATE USER tldraw_user WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE tldraw TO tldraw_user;
\q
```

### 2. Docker Compose Configuration

**docker-compose.prod.yml**:

```yaml
version: '3.8'
services:
  tldraw:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - .:/app
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://tldraw_user:secure_password@postgres:5432/tldraw
      PORT: 3000
      CORS_ALLOWED_ORIGINS: https://tldraw.example.com
    depends_on:
      - postgres
    restart: always
    command: npm start

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: tldraw
      POSTGRES_USER: tldraw_user
      POSTGRES_PASSWORD: secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: always

volumes:
  postgres_data:
```

### 3. Nginx Configuration for SSL/TLS

**nginx.conf**:

```nginx
upstream tldraw_backend {
  server localhost:3000 fail_timeout=0;
}

# Redirect HTTP to HTTPS
server {
  listen 80;
  server_name tldraw.example.com;
  return 301 https://$server_name$request_uri;
}

# HTTPS with WebSocket support
server {
  listen 443 ssl http2;
  server_name tldraw.example.com;

  # SSL Certificates (use Let's Encrypt)
  ssl_certificate /etc/letsencrypt/live/tldraw.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/tldraw.example.com/privkey.pem;

  # SSL Configuration
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;
  ssl_prefer_server_ciphers on;
  ssl_session_cache shared:SSL:10m;
  ssl_session_timeout 10m;

  # Security Headers
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;

  # Map for WebSocket upgrade
  map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
  }

  # Main location block
  location / {
    proxy_pass http://tldraw_backend;
    proxy_http_version 1.1;

    # WebSocket support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    # Standard proxy headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # Disable buffering for streaming
    proxy_buffering off;
  }

  # Static assets caching
  location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
    proxy_pass http://tldraw_backend;
    proxy_cache_valid 1d;
    add_header Cache-Control "public, immutable";
  }
}
```

### 4. SSL Certificate with Let's Encrypt

```bash
# Install Certbot
sudo apt-get install certbot python3-certbot-nginx

# Generate certificate
sudo certbot certonly --standalone -d tldraw.example.com

# Verify certificate
sudo ls -la /etc/letsencrypt/live/tldraw.example.com/
```

### 5. Start Production Deployment

```bash
docker-compose -f docker-compose.prod.yml up -d
sudo systemctl restart nginx
```

### 6. Monitor Deployment

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f tldraw

# Check Nginx
sudo journalctl -u nginx -f
```

## Environment Variables

Configure via `.env` file or Docker compose:

```env
# Node Environment
NODE_ENV=production

# Server
PORT=3000
TLDRAW_SERVER_PORT=3000

# Database
DATABASE_URL=postgresql://user:password@host:5432/database
TLDRAW_DATABASE_URL=postgresql://user:password@host:5432/database

# CORS
CORS_ALLOWED_ORIGINS=https://tldraw.example.com,https://app.example.com

# WebSocket
TLDRAW_WEBSOCKET_URL=wss://tldraw.example.com
WEBSOCKET_SERVER_PORT=3001

# Optional: Cloud Storage
S3_BUCKET=tldraw-boards
S3_REGION=us-east-1
S3_ACCESS_KEY=xxxxx
S3_SECRET_KEY=xxxxx

# Optional: Authentication
JWT_SECRET=your-secret-key
AUTH_ENABLED=true

# Optional: Monitoring
SENTRY_DSN=https://xxxxx@sentry.io/xxxxx
LOG_LEVEL=info
```

## Database Initialization

### Schema Setup

```sql
-- Documents table
CREATE TABLE IF NOT EXISTS tldraw_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  data JSONB NOT NULL,
  created_by UUID,
  updated_by UUID,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Operations log (for CRDT sync)
CREATE TABLE IF NOT EXISTS tldraw_operations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES tldraw_documents(id) ON DELETE CASCADE,
  operation JSONB NOT NULL,
  sequence INT NOT NULL,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_tldraw_documents_created_by ON tldraw_documents(created_by);
CREATE INDEX idx_tldraw_operations_document_id ON tldraw_operations(document_id);
CREATE INDEX idx_tldraw_documents_created_at ON tldraw_documents(created_at DESC);
```

### Run Migrations

```bash
# Connect to PostgreSQL
psql postgresql://tldraw_user:password@localhost:5432/tldraw < schema.sql

# Verify tables
psql postgresql://tldraw_user:password@localhost:5432/tldraw -c "\dt"
```

## Scaling & Performance

### Load Balancing

For multiple server instances:

```nginx
upstream tldraw_backend {
  server tldraw1:3000;
  server tldraw2:3000;
  server tldraw3:3000;
  keepalive 32;
}
```

### Database Optimization

```sql
-- Add indexes for common queries
CREATE INDEX idx_documents_user_created ON tldraw_documents(created_by, created_at DESC);
CREATE INDEX idx_documents_search ON tldraw_documents USING GIN (data jsonb_path_ops);

-- Set connection pool
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
```

### Redis Caching (Optional)

For session caching and real-time collaboration:

```yaml
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    restart: always
    volumes:
      - redis_data:/data

volumes:
  redis_data:
```

## Monitoring & Health Checks

### Docker Health Check

```yaml
  tldraw:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### Logging

```bash
# View application logs
docker-compose logs -f tldraw

# View specific container
docker logs tldraw_tldraw_1 --follow --tail 100
```

### Metrics & Monitoring

Setup Prometheus + Grafana:

```yaml
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker-compose logs tldraw

# Common issues:
# 1. Port already in use: lsof -i :3000
# 2. Database connection: psql $DATABASE_URL -c "SELECT 1"
# 3. Node version mismatch: node --version (must be 18+)
```

### WebSocket Connection Failed

```bash
# Test WebSocket endpoint
wscat -c wss://tldraw.example.com

# Check Nginx configuration
sudo nginx -t
sudo systemctl reload nginx

# Verify proxy headers
curl -i -H "Upgrade: websocket" -H "Connection: Upgrade" https://tldraw.example.com/ws
```

### Database Connection Refused

```bash
# Check PostgreSQL is running
docker-compose ps postgres

# Check connection string
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL -c "SELECT 1"

# Check firewall
sudo ufw status
```

### SSL Certificate Issues

```bash
# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/tldraw.example.com/fullchain.pem -noout -dates

# Renew certificate
sudo certbot renew --dry-run
sudo certbot renew

# Auto-renewal with cron
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet") | crontab -
```

## Backup & Restore

### Database Backup

```bash
# Backup PostgreSQL
docker-compose exec postgres pg_dump -U tldraw_user tldraw > backup.sql

# Backup volumes
docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz /data
```

### Restore from Backup

```bash
# Restore database
psql postgresql://tldraw_user:password@localhost:5432/tldraw < backup.sql

# Restore volumes
docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine tar xzf /backup/postgres_backup.tar.gz -C /
```

## Security Checklist

- [ ] Enable SSL/TLS with valid certificate
- [ ] Set strong database password
- [ ] Enable CORS restrictions
- [ ] Configure firewall rules
- [ ] Use strong JWT secrets (if enabled)
- [ ] Enable PostgreSQL user authentication
- [ ] Disable Docker socket access
- [ ] Keep containers updated (`docker pull`, `docker-compose pull`)
- [ ] Monitor logs for suspicious activity
- [ ] Set up automated backups

## Resources

- [tldraw Self-Hosting Guide](https://github.com/tldraw/tldraw/tree/main/apps/selfhosted)
- [Docker Documentation](https://docs.docker.com/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Let's Encrypt](https://letsencrypt.org/)
