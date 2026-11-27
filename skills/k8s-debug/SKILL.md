---
name: k8s-debug
description: Troubleshoot a Kubernetes workload/namespace with the kubernetes-expert agent.
disable-model-invocation: true
argument-hint: "<namespace> [pod|deployment] [symptom]"
---
Delegate to the `kubernetes-expert` subagent: task=troubleshoot, scope=`$ARGUMENTS`. Do not run kubectl yourself. Show the user from its AgentReport: root_cause (one line), evidence-backed findings table, files_changed, then `needs_approval` commands in a code block, then `next`.
