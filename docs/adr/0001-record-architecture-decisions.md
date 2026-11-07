# 0001. Record architecture decisions

- Status: Accepted
- Date: 2026-11-06
- Deciders: @zippy1981
- Related: [zippy1981/windows-nano-baseimages#5](https://github.com/zippy1981/windows-nano-baseimages/issues/5)

## Context

This repo makes choices that are hard to undo: where tools are installed in the images, which curl ships, how images are tagged and published, and which runners build them. Downstream images in windows-nano-demos depend on them.

## Decision

We will record each significant decision as an Architecture Decision Record in `docs/adr/`, in MADR style, numbered from `0001` with no gaps, and list it in [docs/adr/README.md](README.md).

## Consequences

The reason for a choice stays next to the code. Changing a recorded decision means writing a new ADR that supersedes the old one.

## Alternatives considered

- **Decisions only in issue comments:** they're hard to find later and aren't versioned with the code.
