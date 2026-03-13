# Lithoglyph HTTP API - Kubernetes Deployment Guide

Complete production deployment guide for Kubernetes.

## Quick Start

```bash
# 1. Build and push Docker image
docker build -t ghcr.io/hyperpolymath/lith-http-api:v1.0.0 .
docker push ghcr.io/hyperpolymath/lith-http-api:v1.0.0

# 2. Create namespace
kubectl create namespace lith-production

# 3. Create secrets
kubectl create secret generic lith-secrets \
  --namespace=lith-production \
  --from-literal=secret-key-base="$(mix phx.gen.secret)" \
  --from-literal=jwt-secret="$(openssl rand -base64 64)" \
  --from-literal=erlang-cookie="$(openssl rand -base64 32)"

# 4. Deploy with Kustomize
kubectl apply -k k8s/overlays/production/
```

## Prerequisites

### Required Tools

- **kubectl** 1.25+ - https://kubernetes.io/docs/tasks/tools/
- **kustomize** 5.0+ - https://kustomize.io/
- **Docker** 20.10+ - https://docs.docker.com/get-docker/
- **Helm** 3.12+ (for cert-manager, nginx-ingress) - https://helm.sh/

### Required Kubernetes Resources

- **Ingress Controller**: nginx-ingress
  ```bash
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace
  ```

- **Cert Manager**: For TLS certificates
  ```bash
  helm repo add jetstack https://charts.jetstack.io
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true
  ```

- **Metrics Server**: For HPA
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  ```

- **Prometheus Operator** (Optional): For metrics
  ```bash
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace
  ```

## Directory Structure

```
k8s/
├── base/                         # Base manifests
│   ├── deployment.yaml          # Main deployment
│   ├── service.yaml             # ClusterIP service
│   ├── ingress.yaml             # NGINX Ingress
│   ├── pvc.yaml                 # Persistent storage
│   ├── configmap.yaml           # Configuration
│   ├── secret.yaml.template     # Secret template (DO NOT commit real secrets!)
│   ├── rbac.yaml                # ServiceAccount, Role, RoleBinding
│   ├── hpa.yaml                 # HorizontalPodAutoscaler
│   ├── pdb.yaml                 # PodDisruptionBudget
│   ├── networkpolicy.yaml       # Network security
│   ├── servicemonitor.yaml      # Prometheus metrics
│   └── kustomization.yaml       # Kustomize config
│
└── overlays/                     # Environment-specific configs
    ├── dev/                     # Development
    ├── staging/                 # Staging
    └── production/              # Production
        ├── kustomization.yaml
        ├── deployment-patch.yaml
        └── ingress-patch.yaml
```

## Deployment Steps

### 1. Build Docker Image

```bash
# Build multi-arch image
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/hyperpolymath/lith-http-api:v1.0.0 \
  --push .
```

### 2. Configure Secrets

⚠️ **CRITICAL**: Never commit secrets to git!

```bash
# Generate secrets
SECRET_KEY_BASE=$(mix phx.gen.secret)
JWT_SECRET=$(openssl rand -base64 64)
ERLANG_COOKIE=$(openssl rand -base64 32)

# Create Kubernetes secret
kubectl create secret generic lith-secrets \
  --namespace=lith-production \
  --from-literal=secret-key-base="$SECRET_KEY_BASE" \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --from-literal=erlang-cookie="$ERLANG_COOKIE"

# Verify secret was created
kubectl get secret lith-secrets -n lith-production
```

### 3. Configure TLS Certificates

Create ClusterIssuer for Let's Encrypt:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@lith.io  # Change this!
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 4. Deploy Application

```bash
# Create namespace
kubectl create namespace lith-production

# Deploy with Kustomize
kubectl apply -k k8s/overlays/production/

# Watch deployment
kubectl rollout status deployment/prod-lith-http-api -n lith-production
```

### 5. Verify Deployment

```bash
# Check pods
kubectl get pods -n lith-production

# Check services
kubectl get svc -n lith-production

# Check ingress
kubectl get ingress -n lith-production

# Test health endpoint
kubectl port-forward -n lith-production svc/prod-lith-http-api 8080:80
curl http://localhost:8080/api/v1/health
```

## Configuration

### Environment Variables

Set in `k8s/base/configmap.yaml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 4000 | HTTP port |
| `MIX_ENV` | prod | Elixir environment |
| `CACHE_TTL_SECONDS` | 300 | Cache TTL |
| `CACHE_MAX_ENTRIES` | 1000 | Max cache entries |
| `LOG_LEVEL` | info | Log level (debug/info/warn/error) |
| `METRICS_ENABLED` | true | Enable Prometheus metrics |

### Secrets

Set via Kubernetes Secret:

| Secret | Description | Generate With |
|--------|-------------|---------------|
| `secret-key-base` | Phoenix secret | `mix phx.gen.secret` |
| `jwt-secret` | JWT signing key | `openssl rand -base64 64` |
| `erlang-cookie` | Erlang distribution | `openssl rand -base64 32` |

### Resource Limits

**Production defaults:**

- **Requests:** 1 CPU, 1Gi memory
- **Limits:** 4 CPU, 4Gi memory
- **Replicas:** 5 (min: 3, max: 10 with HPA)

Adjust in `k8s/overlays/production/deployment-patch.yaml`

### Storage

**PersistentVolumeClaim:**

- **Size:** 100Gi
- **StorageClass:** fast-ssd (adjust for your provider)
- **AccessMode:** ReadWriteOnce

Update in `k8s/base/pvc.yaml`

## Monitoring & Observability

### Prometheus Metrics

Metrics exposed at `/metrics`:

- HTTP request duration
- HTTP request count
- Cache hit/miss rates
- Spatial index operations
- Temporal index operations
- BEAM VM metrics (memory, schedulers, etc.)

Access Prometheus:
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090
```

### Grafana Dashboards

Import dashboards for:
- Phoenix application metrics
- BEAM VM metrics
- Kubernetes cluster metrics

Access Grafana:
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Visit: http://localhost:3000
# Default: admin/prom-operator
```

### Logs

View logs with kubectl:

```bash
# All pods
kubectl logs -n lith-production -l app=lith-http-api --tail=100 -f

# Specific pod
kubectl logs -n lith-production pod/prod-lith-http-api-xxxxx -f

# Previous container (if crashed)
kubectl logs -n lith-production pod/prod-lith-http-api-xxxxx --previous
```

## Scaling

### Manual Scaling

```bash
# Scale to 10 replicas
kubectl scale deployment prod-lith-http-api \
  -n lith-production --replicas=10
```

### Automatic Scaling (HPA)

Configured in `k8s/base/hpa.yaml`:

- **Min replicas:** 3
- **Max replicas:** 10
- **CPU target:** 70%
- **Memory target:** 80%

View HPA status:
```bash
kubectl get hpa -n lith-production
```

## Security

### Network Policies

Network isolation configured in `k8s/base/networkpolicy.yaml`:

- ✅ Ingress from nginx-ingress only
- ✅ Egress to DNS and HTTPS
- ✅ Pod-to-pod communication allowed
- ❌ All other traffic denied

### Pod Security

Security context configured:

- ✅ Run as non-root (UID 1000)
- ✅ Read-only root filesystem
- ✅ No privilege escalation
- ✅ Drop all capabilities
- ✅ Seccomp profile

### RBAC

Minimal permissions:

- Read endpoints (for service discovery)
- Read pods (for clustering)
- No write access

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod -n lith-production prod-lith-http-api-xxxxx

# Check events
kubectl get events -n lith-production --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n lith-production prod-lith-http-api-xxxxx
```

### Health Check Failures

```bash
# Test health endpoint directly
kubectl exec -n lith-production prod-lith-http-api-xxxxx -- \
  wget -O- http://localhost:4000/api/v1/health
```

### NIF Not Loading

```bash
# Check if liblith_nif.so exists in container
kubectl exec -n lith-production prod-lith-http-api-xxxxx -- \
  ls -la /app/lib/lith_http-*/priv/native/

# Check container logs for NIF errors
kubectl logs -n lith-production prod-lith-http-api-xxxxx | grep -i nif
```

### Certificate Issues

```bash
# Check certificate status
kubectl describe certificate lith-api-prod-tls -n lith-production

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

## Updating

### Rolling Update

```bash
# Update image tag
kubectl set image deployment/prod-lith-http-api \
  -n lith-production \
  lith-http-api=ghcr.io/hyperpolymath/lith-http-api:v1.1.0

# Watch rollout
kubectl rollout status deployment/prod-lith-http-api -n lith-production
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/prod-lith-http-api -n lith-production

# Rollback to specific revision
kubectl rollout undo deployment/prod-lith-http-api \
  -n lith-production --to-revision=2
```

## Backup & Disaster Recovery

### Backup PersistentVolume

```bash
# Create VolumeSnapshot (requires VolumeSnapshot CRD)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: lith-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: lith-production
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: lith-data
EOF
```

### Restore from Snapshot

```bash
# Create PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lith-data-restored
  namespace: lith-production
spec:
  dataSource:
    name: lith-data-snapshot-20260205-120000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF
```

## Production Checklist

Before deploying to production:

- [ ] Secrets generated and stored securely
- [ ] TLS certificates configured
- [ ] Ingress domain DNS pointing to load balancer
- [ ] Monitoring (Prometheus/Grafana) deployed
- [ ] Log aggregation configured
- [ ] Backup strategy in place
- [ ] Resource limits tested under load
- [ ] Health checks validated
- [ ] Network policies tested
- [ ] Security scan completed
- [ ] Load testing completed
- [ ] Disaster recovery plan documented

## Support

For issues or questions:
- GitHub Issues: https://github.com/hyperpolymath/lith_http/issues
- Documentation: `/docs`
- Security: security@lith.io
