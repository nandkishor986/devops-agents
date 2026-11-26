---
type: regex
pattern: "USER (root|0)"
match: not_contains
target: { source: file, path: Dockerfile }
weight: 2
---
