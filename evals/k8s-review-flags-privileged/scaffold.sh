#!/usr/bin/env bash
mkdir -p k8s && cat > k8s/deploy.yaml <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: web
          image: nginx:latest
          securityContext: { privileged: true }
Y
