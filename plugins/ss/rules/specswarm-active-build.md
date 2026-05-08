---
description: Guard against overlapping builds when a SpecSwarm build is active
globs:
  - .specswarm/build-loop.state
---

# Active Build Guard

When `.specswarm/build-loop.state` exists, a SpecSwarm build is in progress.

## Rules

1. **Do NOT start a new `/ss:build`** while a build is active — check the state file first
2. **Do NOT create new feature branches** during an active build — it will cause git conflicts
3. **Use `/ss:status`** to check build progress before starting new work
4. **If the build appears stuck**, use `/ss:rollback` to clean up before retrying
