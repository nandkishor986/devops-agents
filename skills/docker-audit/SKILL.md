---
name: docker-audit
description: Security + efficiency audit of a Dockerfile/image/container with the docker-expert agent.
disable-model-invocation: true
argument-hint: "[Dockerfile path] [image:tag] [fix]"
---
Delegate to the `docker-engineer` subagent: task=review (or implement if `$ARGUMENTS` contains "fix"), target=`$ARGUMENTS` (default `./Dockerfile`). Show the user from its AgentReport: status, findings table (sev | id | file:line | issue | fix), files_changed, `next`.
