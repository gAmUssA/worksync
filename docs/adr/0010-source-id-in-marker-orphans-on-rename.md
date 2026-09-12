# ADR-0010 — The source id is embedded in every marker, so renaming orphans events

Status: accepted
Date: 2026-09-12

## Context

A managed event has to name which source produced it, so a later pass can
update or delete the right blockers and so `purge --source` can target one
source's leftovers. The marker URL is `worksync://v1/<source_id>/<key>`
(`Marker.urlString` in `Sources/WorkSyncCore/Marker.swift`). The source id is
copied in verbatim.

That id is also the user's `[[source]]` name, which they can rename.

## Decision

The marker keeps embedding the config id. Rename is therefore an orphaning
operation: events written under the old id will never match the new one, so
a normal sync neither updates nor deletes them.

The only recovery is `worksync purge --source <old-id>` (`PurgeScan.claimable`
filters on `marker.sourceID`; `worksync/Purge.swift`).
`SourceRenamePolicy.needsWarning` requires a confirmation when the old id is
already on disk; brand-new sources need none. The alert quotes the purge
command (`SourceRenamePolicy.recoveryCommand`).

## Consequences

- Changing the marker to a stable identity (a UUID minted once per source)
  would make rename safe, and would be a new marker version with a migration.
  That was not chosen. Every existing event on every user's work calendar
  carries the string id.
- Any tool that writes `id =` on an existing source must warn. Skipping the
  warning is silent data loss on the work calendar — stranded Busy events
  until someone thinks to purge.
- `worksync status` reports those leftovers as ORPHANED. They are not cleaned
  automatically, including when the window rolls past them.
- Handles (ADR-0005) exist so the *editor* does not confuse ids with
  identity. They do not change what is already written on the calendar.
