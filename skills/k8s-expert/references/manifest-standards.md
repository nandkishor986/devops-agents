# Manifest standards (load only when writing/reviewing YAML)

## Golden Deployment (copy, then trim what doesn't apply)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels: &labels
    app.kubernetes.io/name: api
    app.kubernetes.io/part-of: shop
    app.kubernetes.io/managed-by: kustomize
spec:
  replicas: 2
  revisionHistoryLimit: 5
  strategy: { type: RollingUpdate, rollingUpdate: { maxUnavailable: 0, maxSurge: 25% } }
  selector: { matchLabels: { app.kubernetes.io/name: api } }
  template:
    metadata:
      labels: *labels
    spec:
      serviceAccountName: api
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        fsGroup: 10001
        seccompProfile: { type: RuntimeDefault }
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: { matchLabels: { app.kubernetes.io/name: api } }
      terminationGracePeriodSeconds: 30
      containers:
        - name: api
          image: myacr.azurecr.io/api:1.4.2   # or @sha256:... for prod
          ports: [{ name: http, containerPort: 8080 }]
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits:   { memory: 256Mi }          # CPU limit optional (throttling); memory limit mandatory
          startupProbe:   { httpGet: { path: /healthz, port: http }, failureThreshold: 30, periodSeconds: 2 }
          readinessProbe: { httpGet: { path: /ready,   port: http }, periodSeconds: 5, timeoutSeconds: 2 }
          livenessProbe:  { httpGet: { path: /healthz, port: http }, periodSeconds: 10, timeoutSeconds: 3, failureThreshold: 3 }
          lifecycle: { preStop: { sleep: { seconds: 5 } } }   # k8s ≥1.30; else exec sleep
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          volumeMounts: [{ name: tmp, mountPath: /tmp }]
          envFrom: [{ configMapRef: { name: api-config } }]
      volumes: [{ name: tmp, emptyDir: { sizeLimit: 64Mi } }]
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: api }
spec: { minAvailable: 1, selector: { matchLabels: { app.kubernetes.io/name: api } } }
```

## NetworkPolicy baseline (per namespace)
default-deny ingress + egress, then allow: DNS egress to kube-system:53 UDP/TCP, ingress from ingress-controller namespace on app port, explicit egress to dependencies.

## Secrets on AKS
Secrets Store CSI driver + Azure Key Vault provider with workload identity (`SecretProviderClass`), or External Secrets Operator. Never commit `kind: Secret` with data — K8S-SEC-004.

## Kustomize layout
```
k8s/base/{deployment,service,pdb,networkpolicy,kustomization}.yaml
k8s/overlays/{dev,prod}/kustomization.yaml   # images:, replicas:, patches:
```
Render to review: `kustomize build k8s/overlays/prod | kubeconform -strict -summary -kubernetes-version 1.30.0 -`

## Helm review quick list
values.yaml has resources/probes/securityContext toggles with safe defaults; templates use `include "x.labels"`; `helm template . -f values-prod.yaml | kube-linter lint -`; chart and appVersion pinned; no `lookup` of secrets in templates.

## API deprecations
Check against the target version: `kubent` or `pluto detect-files -d k8s/`; flag K8S-COR-002.
