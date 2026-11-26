---
type: regex
pattern: "8081"
match: not_contains
target: { source: file, path: Dockerfile }
---
