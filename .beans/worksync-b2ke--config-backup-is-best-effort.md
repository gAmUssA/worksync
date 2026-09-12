---
# worksync-b2ke
title: 'A config save can proceed with no backup'
status: todo
type: bug
created_at: 2026-09-12T14:30:33Z
updated_at: 2026-09-12T14:30:33Z
---

Found by the SPEC divergence audit (2026-09-12).

SPEC §4.3 step 5 says the writer copies the existing file to `config.toml.bak`
**before** overwriting. The code treats that as best-effort:

    try? FileManager.default.removeItem(atPath: path + ".bak")
    try? FileManager.default.copyItem(atPath: path, toPath: path + ".bak")

Both are `try?`. The write proceeds whether or not either succeeded.

The auditor probed it: with backup replacement blocked by an immutable sentinel,
`save` returned `preserved`, **changed the config**, and the backup path still
held a directory rather than a backup file. So the documented safety net can be
absent exactly when a user would need it.

The round-trip self-check still protects against writing unparseable output, so
this is not corruption — it is the loss of the documented recovery path.

[ ] Decide: is the backup a prerequisite (fail the save if it cannot be made) or
      genuinely best-effort (then say so, and surface it in the outcome)?
[ ] Whichever: make code and documentation agree, and record it as an ADR
[ ] Test the blocked-backup path asserts the chosen behaviour
