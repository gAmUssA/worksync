---
# worksync-o7n2
title: 'M6: Config editor window'
status: todo
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T00:33:43Z
blocked_by:
    - worksync-5lsv
---

SPEC §14 M6. Config editor window (SPEC §11.1): validate-and-surface on Open config, the config writer with backup and round-trip self-check (SPEC §4.3), the comment-preserving line editor, the general/target forms, and the source list with add/remove/drag-reorder and the id-rename warning.

## Acceptance
- [ ] Editing a value in Preferences updates exactly that value in config.toml, leaves every other line byte-identical, preserves all comments (SPEC §15)
- [ ] A save with no edits leaves the file byte-identical
- [ ] Reordering sources in Preferences changes their order in config.toml
- [ ] Renaming an existing source id prompts a warning first (orphaning + purge recovery explained)
- [ ] Preferences refuses to open on unparseable config, pointing at "Open config"
