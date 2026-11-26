---
type: regex
pattern: "curl"
match: not_contains
target: { source: file, path: Dockerfile }
---
