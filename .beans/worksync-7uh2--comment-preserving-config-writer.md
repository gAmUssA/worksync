---
# worksync-7uh2
title: Comment-preserving config writer
status: todo
type: feature
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:35:51Z
parent: worksync-o7n2
---

SPEC §4.3. Comment-preserving config writer (TOMLKit/toml++ strips comments AND reorders keys — re-serialization is banned):
- [ ] Field-by-field diff of previous vs new config
- [ ] Scalar edits rewrite only that line's value, preserving trailing # comments
- [ ] [[source]] blocks as movable/insertable/deletable text chunks matched by id; final order follows new config
- [ ] Round-trip self-check through the normal loader; refuse to write on failure
- [ ] config.toml.bak before overwrite; full-serialization fallback only for brand-new files or failed self-check
- [ ] Tests on the comment-dense §4 fixture: single-field edit preserves every comment; per-source isolation; add/remove/reorder; no-op edit -> byte-identical
