# Architecture Decision Records

Each file records one decision: what was decided, why, and what it costs.

## Why these exist

`SPEC.md` was written to kick development off. It did that job, and it is still
useful as a description of intent — but it was written before the code, and the
implementation made decisions the spec never captured. Two of its claims were
found to be false about the shipped app, and had been for a while.

An accepted ADR records a decision already made and is never retroactively
edited to match a later decision. A proposed ADR is a draft for a decision still
under discussion; it must distinguish proposed behavior from implemented facts.
When a decision changes, a new ADR supersedes the old one and the old one stays, marked superseded. That is the
property `SPEC.md` cannot have: a document continuously edited to match the code
cannot tell you why anything is the way it is.

## Format

    # ADR-NNNN — Title

    Status: accepted | superseded by ADR-NNNN | proposed
    Date: YYYY-MM-DD

    ## Context
    What was true that forced a decision.

    ## Decision
    What was chosen, stated plainly.

    ## Consequences
    What this costs, what it rules out, and what has to stay true for it to
    keep working. Include the bad parts.

## Conventions

- One decision per file. If it needs "and", it is two ADRs.
- Use past tense for historical events in Context. Decision and Consequences
  use present tense for the choice in force at the recorded date and its costs.
  Label unimplemented choices as proposed, and expected outcomes as expectations.
- Verify factual Context, Decision, and Consequences against code and existing
  audit findings. A claim inherited from SPEC can inherit its errors; citing
  that document is not implementation evidence. Separate observed behavior,
  design intent, and unverified runtime assumptions.
- Cite implementation code so a reader can check the recorded behavior.
- Never edit an accepted ADR to match changed code. Supersede it. Correcting a
  factual error in a backfill is different from changing the decision; preserve
  that correction in review and commit history.
- Numbered sequentially, never reused.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-record-decisions-in-adrs.md) | Record architecture decisions in ADRs, not in SPEC.md | accepted |
| [0002](0002-config-writer-edits-line-wise.md) | The config writer edits text line-wise instead of reserializing | accepted |
| [0003](0003-blocker-title-cannot-contain-source-title.md) | Render blocker titles from templates without source-event metadata | accepted |
| [0004](0004-marker-lives-in-notes.md) | The marker lives in notes, with the URL as a supplementary copy | accepted |
| [0005](0005-source-id-is-data-identity-is-a-handle.md) | A source id is editable data; identity is a `SourceHandle` | accepted |
| [0006](0006-filter-row-identity-is-a-uuid.md) | Filter row identity is a UUID minted when the form opens | accepted |
| [0007](0007-drafts-are-per-handle.md) | Draft state is stored per (field, source handle), not as a single owner | accepted |
| [0008](0008-drag-validated-against-rendered-order.md) | Validate move callbacks against captured rendered source order | accepted |
| [0009](0009-source-order-is-load-bearing.md) | Source order is load-bearing | accepted |
| [0010](0010-source-id-in-marker-orphans-on-rename.md) | Source-id renames change marker identity; cleanup depends on fetch scope | accepted |
| [0011](0011-cask-sha256-from-published-asset.md) | The Homebrew cask sha256 is taken from the published asset, never a local build | accepted |
