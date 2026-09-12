# ADR-0010 — Source-id renames change marker identity; cleanup depends on fetch scope

Status: accepted
Date: 2026-09-12

## Context

A managed event names its source so reconciliation can match desired blockers
and `purge --source` can target that source's events. The marker URL is
`worksync://v1/<source_id>/<key>` (`Marker.urlString` in
`Sources/WorkSyncCore/Marker.swift`). The source id is also the user's editable
`[[source]]` name. Renaming it changes marker identity even when the occurrence
and its key are otherwise unchanged.

## Decision

The marker keeps embedding the config id. After a rename from `old-id` to
`new-id`, old markers do not match desired markers for the renamed source.
That mismatch does not exempt them from normal reconciliation.
`SyncPlanner.reconcile` (`Sources/WorkSyncCore/Planner.swift`) includes every
fetched event with a current-version marker, without requiring its source id
to remain in config. It schedules unmatched old markers for deletion and
missing desired new markers for creation.

Scope comes from `SyncPipeline.plan` (`Sources/WorkSyncCore/SyncPipeline.swift`):
existing blockers are fetched only from the currently resolved target calendars,
for the current sync window. Old-id blockers returned by that fetch are eligible
for deletion. Blockers outside the fetched window or on calendars no longer in
the target set are unseen and can remain stranded. These are planned changes;
a dry run does not apply them, and write failures can prevent convergence.

`SourceRenamePolicy.needsWarning` asks for confirmation when the old id is
already on disk; brand-new sources need none. Its recovery command is
`worksync purge --source <old-id>`. The current warning/commentary overstates
orphaning; it is not evidence that normal sync cannot delete old-id events.
`PurgeScan.claimable` filters by `marker.sourceID`; `PurgeEngine.scan` searches
all enumerated calendars within 365 days on either side of now
(`Sources/WorkSyncCore/PurgeScan.swift`). The CLI command previews counts;
`--yes` is required for deletion (`Sources/worksync/Purge.swift`).

## Consequences

- A rename can delete and recreate in-scope blockers rather than update them
  in place. It does not inherently leave every old-id blocker behind.
- Renaming while changing targets can leave the former target unscanned if no
  current source targets it. Merely rolling the window past an old blocker does
  not remove it; a later pass can delete it if it is fetched and still unmatched.
- Purge reaches calendars outside the current target set, but its bounded scan
  and possible read/write failures do not guarantee removal of every leftover.
  `worksync status` labels discovered source ids absent from config as ORPHANED;
  that label does not mean they are immune to a later normal sync.
- Replacing the embedded name with a persistent source identity would require a
  marker compatibility/migration decision. This implementation still uses the
  config string id. Editing-session handles (ADR-0005) do not change markers
  already written on calendars.
