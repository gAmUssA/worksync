---
# worksync-7uh2
title: Comment-preserving config writer
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T04:39:43Z
parent: worksync-o7n2
---

SPEC §4.3. Comment-preserving config writer (TOMLKit/toml++ strips comments AND reorders keys — re-serialization is banned):
- [x] Field-by-field diff of previous vs new config
- [x] Scalar edits rewrite only that line's value, preserving trailing # comments
- [x] [[source]] blocks as movable/insertable/deletable text chunks matched by id; final order follows new config
- [x] Round-trip self-check through the normal loader; refuse to write on failure
- [x] config.toml.bak before overwrite; full-serialization fallback only for brand-new files or failed self-check
- [x] Tests on the comment-dense §4 fixture: single-field edit preserves every comment; per-source isolation; add/remove/reorder; no-op edit -> byte-identical


## Summary of Changes
TomlDocument keeps the file as text and rewrites only the lines that change, preserving indentation and same-line comments (comment detection respects quoting so a template of "Busy #1" is not truncated). Sources matched by id, reordering moves real blocks. Every write is reparsed and compared before touching disk, with full-serialization fallback and a .bak. 20 tests, including one that caught a hole in another: 'every comment survives' only counted whole comment lines and missed a dropped trailing comment.
