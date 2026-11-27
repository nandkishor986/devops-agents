# Helm and Argo CD

## Helm charts
Layout: `Chart.yaml` (apiVersion v2, `version` = chart, `appVersion` = image) · `values.yaml` (safe defaults) · `values.schema.json` (types + required — catches bad values early) · `templates/` (`_helpers.tpl` for names/labels) · `templates/tests/`.
- Every workload template: resources, probes, `securityContext` (non-root, read-only root FS, drop ALL), PDB, HPA toggle, `podAntiAffinity`/topology spread, image by digest or pinned tag.
- Validate: `helm lint .` → `helm template . -f values-prod.yaml | kubeconform -strict -summary` → `helm diff upgrade` (plugin) against the cluster.
- Deploy only after approval: `helm upgrade --install <rel> . -n <ns> -f values-<env>.yaml --atomic --wait --timeout 10m`. `--atomic` rolls back on failure.
- Never `helm uninstall` without explicit approval; never `--all-namespaces` deletes.
- Troubleshoot: `helm status`, `helm history`, `helm get values/manifest`; failed hooks → `kubectl get jobs,pods -l app.kubernetes.io/instance=<rel>`; stuck `pending-upgrade` → `helm rollback <rel> <rev>` (with approval).

## Argo CD (GitOps)
- **Application**: `source` (repo, path/chart, targetRevision pinned to a tag or commit for prod), `destination` (cluster, namespace), `syncPolicy` (`automated: {prune: true, selfHeal: true}` for non-prod; manual sync for prod is common), `syncOptions` (`CreateNamespace=true`, `ServerSideApply=true`).
- **ApplicationSet**: generators (list / cluster / git directories / matrix) to stamp one app per env/cluster.
- Order with sync waves (`argocd.argoproj.io/sync-wave: "-1"` for CRDs/namespaces) and hooks (`PreSync` migrations).
- Change = Git commit, not `kubectl apply` on a managed resource (Argo will revert it). Preview: `argocd app diff <app>`; sync after approval: `argocd app sync <app>`.
- Troubleshoot: app **OutOfSync** → diff (often defaulted fields → `ignoreDifferences`); **Degraded** → the failing resource's events/logs; **Missing** CRDs → wave order; repo/auth errors → `argocd repo list`.
