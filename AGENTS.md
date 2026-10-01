# Repository guidance

## Long-running work

- Do not monitor or poll CI runs.
- Do not repeatedly inspect or wait on very long-running commands or processes. If a required operation is still running after its initial bounded wait, report that it remains pending and return control; continue only with independent work.
