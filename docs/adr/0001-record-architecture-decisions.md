# 0001. Record architecture decisions

- Status: Accepted
- Date: 2026-11-06
- Deciders: zippy1981
- Related: [issue #1](https://github.com/zippy1981/windows-nano-baseimages/issues/1)

## Context

This repo makes choices that are hard to reverse: how tools are built, how releases are named, and which features ship. Later work, much of it done by agents, needs to know why.

## Decision

We will record each significant decision as a numbered MADR-style file in `docs/adr/`, indexed in `docs/adr/README.md`.

## Consequences

Decisions are reviewable in pull requests. Changing one means writing a new ADR that supersedes it.

## Alternatives considered

- Decisions in issue comments only: hard to find later, and not versioned with the code.
