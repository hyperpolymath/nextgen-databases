# Glyphbase Installation Guide

**Carve your data in stone** - Multiple installation options for every use case.

## Quick Start (Recommended)

### Option 1: Docker (Easiest)

```bash
# Pull the latest image
docker pull ghcr.io/hyperpolymath/glyphbase:latest

# Run Glyphbase
docker run -p 4000:4000 -v ./data:/data ghcr.io/hyperpolymath/glyphbase:latest

# Open http://localhost:4000
```

### Option 2: Docker Compose (Production-Ready)

```bash
# Clone the repository
git clone https://github.com/hyperpolymath/glyphbase
cd glyphbase

# Start with docker-compose
docker-compose up -d

# Open http://localhost:4000
```

### Option 3: From Source (Development)

**Prerequisites:**
- [Gleam](https://gleam.run) 1.7+
- [Deno](https://deno.land) 2.0+
- [Lithoglyph](https://github.com/hyperpolymath/lithoglyph) database
- Erlang/OTP 27+

```bash
# Clone the repository
git clone https://github.com/hyperpolymath/glyphbase
cd glyphbase

# Start development servers
just dev

# Or manually:
cd server && gleam run &
cd ui && deno task dev

# Open http://localhost:4000
```

## Detailed Installation Options

### 1. Docker (Single Container)

**Pros:** Easiest setup, works everywhere, no dependencies
**Cons:** Less control over configuration

```bash
# Basic run
docker run -p 4000:4000 ghcr.io/hyperpolymath/glyphbase:latest

# With persistent data
docker run -p 4000:4000 \
  -v $PWD/data:/data \
  ghcr.io/hyperpolymath/glyphbase:latest

# With custom configuration
docker run -p 4000:4000 \
  -v $PWD/data:/data \
  -e SECRET_KEY=your-secret-key \
  -e PORT=8080 \
  ghcr.io/hyperpolymath/glyphbase:latest
```

### 2. Docker Compose (Multi-Container)

**Pros:** Production-ready, includes Lithoglyph database, easy scaling
**Cons:** Requires docker-compose

```bash
# Clone repository
git clone https://github.com/hyperpolymath/glyphbase
cd glyphbase

# Start services
docker-compose up -d

# Check logs
docker-compose logs -f

# Stop services
docker-compose down

# With Lithoglyph standalone database
docker-compose --profile full up -d
```

**Configuration:**

Create `.env` file:

```env
SECRET_KEY=your-production-secret-key
PORT=4000
DATABASE_PATH=/data
```

### 3. Podman (Docker Alternative)

**Pros:** Rootless, more secure, compatible with Docker
**Cons:** Slightly different commands

```bash
# Pull image
podman pull ghcr.io/hyperpolymath/glyphbase:latest

# Run with podman
podman run -p 4000:4000 -v ./data:/data:Z ghcr.io/hyperpolymath/glyphbase:latest

# Or use justfile
just docker-build  # Uses podman
just docker-run
```

### 4. From Source (Development & Contributors)

**Pros:** Full control, latest features, contribution-ready
**Cons:** Requires multiple dependencies

#### Prerequisites

**Install Gleam:**
```bash
# Linux/macOS
curl -fsSL https://gleam.run/install.sh | sh

# Or via asdf
asdf plugin add gleam
asdf install gleam latest
```

**Install Deno:**
```bash
# Linux/macOS
curl -fsSL https://deno.land/install.sh | sh

# Or via asdf
asdf plugin add deno
asdf install deno latest
```

**Install Lithoglyph:**
```bash
# See https://github.com/hyperpolymath/lithoglyph
git clone https://github.com/hyperpolymath/lithoglyph
cd lithoglyph
# Follow lithoglyph installation instructions
```

#### Build & Run

```bash
# Clone Glyphbase
git clone https://github.com/hyperpolymath/glyphbase
cd glyphbase

# Install dependencies (automatic)
cd server && gleam deps download
cd ../ui && deno cache deno.json

# Development mode (hot reload)
just dev

# Build for production
just build

# Run tests
just test

# Format & lint
just fmt
just lint
```

#### Development Workflow

```bash
# Start UI dev server (port 3000)
just dev-ui

# Start backend server (port 4000)
just dev-server

# Run both in parallel
just dev
```

**Ports:**
- UI (dev): `http://localhost:3000`
- Server: `http://localhost:4000`
- API: `http://localhost:4000/api`

### 5. Self-Hosting on VPS

**Pros:** Full control, custom domain, professional deployment
**Cons:** Requires server management skills

#### Using Docker on VPS

```bash
# SSH into your server
ssh user@your-server.com

# Install Docker
curl -fsSL https://get.docker.com | sh

# Run Glyphbase
docker run -d --restart unless-stopped \
  -p 80:4000 \
  -v /var/lib/glyphbase:/data \
  --name glyphbase \
  ghcr.io/hyperpolymath/glyphbase:latest

# Set up reverse proxy (nginx/caddy)
# Point your domain to the server
# Configure SSL with Let's Encrypt
```

#### With Caddy (Automatic HTTPS)

**Caddyfile:**
```
glyphbase.yourdomain.com {
    reverse_proxy localhost:4000
}
```

```bash
caddy run --config Caddyfile
```

### 6. Kubernetes Deployment

**Pros:** Enterprise-scale, auto-scaling, high availability
**Cons:** Complex setup

```yaml
# glyphbase-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: glyphbase
spec:
  replicas: 3
  selector:
    matchLabels:
      app: glyphbase
  template:
    metadata:
      labels:
        app: glyphbase
    spec:
      containers:
      - name: glyphbase
        image: ghcr.io/hyperpolymath/glyphbase:latest
        ports:
        - containerPort: 4000
        env:
        - name: DATABASE_PATH
          value: /data
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: glyphbase-data
---
apiVersion: v1
kind: Service
metadata:
  name: glyphbase
spec:
  selector:
    app: glyphbase
  ports:
  - port: 80
    targetPort: 4000
  type: LoadBalancer
```

```bash
kubectl apply -f glyphbase-deployment.yaml
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP server port |
| `DATABASE_PATH` | `./data` | Lithoglyph data directory |
| `SECRET_KEY` | *(required)* | Session encryption key (production) |
| `LOG_LEVEL` | `info` | Logging level (debug, info, warn, error) |
| `MAX_UPLOAD_SIZE` | `100MB` | Maximum file upload size |

### Data Persistence

Glyphbase stores all data in the Lithoglyph database directory.

**Important:** Always mount a volume to `/data` for persistence:

```bash
docker run -v ./data:/data glyphbase  # Persists to ./data
docker run -v /var/lib/glyphbase:/data glyphbase  # Persists to /var/lib/glyphbase
```

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 4000
lsof -i :4000

# Use a different port
docker run -p 8080:4000 glyphbase
```

### Database Connection Errors

```bash
# Check Lithoglyph is running
curl http://localhost:5432/health

# Check data directory permissions
ls -la ./data
chmod 777 ./data  # or appropriate permissions
```

### Container Won't Start

```bash
# Check logs
docker logs glyphbase

# Check health
docker inspect glyphbase | grep Health
```

## Upgrading

### Docker

```bash
# Pull latest image
docker pull ghcr.io/hyperpolymath/glyphbase:latest

# Stop old container
docker stop glyphbase && docker rm glyphbase

# Start new container (data persists in volume)
docker run -p 4000:4000 -v ./data:/data ghcr.io/hyperpolymath/glyphbase:latest
```

### From Source

```bash
cd glyphbase
git pull origin main
gleam deps download
deno cache deno.json
just build
```

## Getting Help

- **Documentation:** https://glyphbase.lithoglyph.org/docs
- **Community:** https://github.com/hyperpolymath/glyphbase/discussions
- **Issues:** https://github.com/hyperpolymath/glyphbase/issues
- **Email:** support@lithoglyph.org

## Next Steps

1. **Quick Start Guide:** See [QUICKSTART.md](./QUICKSTART.md)
2. **User Guide:** See [docs/USER-GUIDE.adoc](./docs/USER-GUIDE.adoc)
3. **API Documentation:** https://docs.lithoglyph.org/api
4. **Contributing:** See [CONTRIBUTING.md](./CONTRIBUTING.md)

---

**Welcome to Glyphbase!** Carve your data in stone. 🪨
