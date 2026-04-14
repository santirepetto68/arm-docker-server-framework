# AGENT.md

This repository packages a maintainable Docker-based workflow for running **Steam-distributed dedicated game servers on Ubuntu ARM hosts**, currently validated first with **ARK: Survival Evolved** under emulation.

The immediate goal is to keep the ARK setup stable and operable. The next goal is to **generalize the project into a reusable framework for multiple Steam games**, while preserving per-game clarity, mod support where applicable, and clean operational workflows.

## Current status

### Proven working
- Host bootstrap on Ubuntu ARM installs the emulation/runtime prerequisites needed for Steam-based x86/x86_64 Linux server binaries.
- SteamCMD installation flow works for ARK app `376030`.
- ARK dedicated server can start successfully in the runtime container.
- Server reaches the state where **RCON responds**.
- Server was successfully joinable once the user removed the join password during testing.

### Important lessons already learned
- The installer/runtime split matters. Steam install and runtime are separate concerns.
- File ownership on `/mnt/server` matters. Installer-created files may be root-owned, while runtime may run as a non-root user.
- Startup must **not depend forever on RCON**. RCON can be delayed and sometimes behaves differently under emulation.
- Shutdown must **not require RCON**. There must always be a signal-based fallback.
- Discovery in server browsers is less reliable than actual reachability. The browser list is not the source of truth.
- For Epic compatibility in ARK, crossplay-specific launch options matter.

## Product direction

The repository should evolve from a one-off ARK stack into a **small framework** for Steam dedicated servers with:
- a shared runtime/install foundation
- per-game configuration modules
- per-game compose overlays or profiles
- explicit support for game-specific ports, launch syntax, configs, mods, health checks, and backups

This should remain pragmatic. Do **not** over-engineer it into a giant platform prematurely.

## High-level architecture target

Keep a layered structure:

1. **Host bootstrap layer**
   - prepares Ubuntu ARM host
   - installs emulation/runtime prerequisites
   - is idempotent and safe to rerun

2. **Shared container orchestration layer**
   - generic install service
   - generic runtime service conventions
   - volume layout, environment loading, backups, logging

3. **Per-game module layer**
   - game metadata
   - Steam app id
   - install/update strategy
   - startup command construction
   - config sync rules
   - port model
   - mod handling
   - health/readiness logic

4. **Per-instance data layer**
   - persistent server files
   - generated configs and saves
   - backups
   - instance-specific env values

## Design principles

- Prefer **simple, explicit shell and compose** over clever abstractions.
- Keep **per-game differences visible**. Do not hide everything behind one unreadable mega-script.
- Shared logic should only be extracted when at least **two games clearly benefit**.
- Favor **idempotent scripts**.
- Favor **operability** over elegance.
- Treat **joinability** as more important than browser listing.
- Treat **Docker logs + game logs + health checks** as first-class diagnostics.
- Preserve a path for **mods**, **clusters**, and **multiple instances**.

## Current repository structure

```text
.
├── docker-compose.yml
├── .env.example
├── README.md
├── config/
│   ├── Game.ini
│   └── GameUserSettings.ini
├── scripts/
│   ├── bootstrap-ubuntu-arm-host.sh
│   ├── install.sh
│   ├── start.sh
│   ├── backup.sh
│   └── common.sh
├── data/
└── backups/
```

## Repository rules for Codex

When modifying this repo, follow these rules.

### 1. Preserve backward compatibility unless explicitly changing contract
Do not casually rename environment variables, paths, or files already used by the repo. If renaming is needed, support both the old and new form during transition and document the deprecation.

### 2. Keep shell scripts production-readable
- Use `set -euo pipefail` unless there is a strong reason not to.
- Quote variables correctly.
- Prefer small helper functions over dense one-liners.
- Log meaningful milestones.
- Never assume RCON exists or is healthy.

### 3. Health model
Health/readiness must reflect reality:
- install completion is not runtime health
- bound UDP sockets are not full readiness
- browser visibility is not the same as joinability
- RCON is useful but should not be the single hard dependency unless the game truly requires it

### 4. Ownership and permissions
Every change that affects `/mnt/server` or other mounted data must consider UID/GID consistency between install and runtime containers.

### 5. Favor additive refactors
When moving toward multi-game support:
- first extract shared helpers
- then introduce per-game metadata/config files
- only then consider major compose restructuring

### 6. Mod support must remain explicit
Do not claim generic mod support unless the target game's mod/install model is actually implemented.

## Known ARK-specific operational facts

- Steam app id: `376030`
- Main gameplay port: `7777/udp`
- Raw/peer port: `7778/udp`
- Query port: `27015/udp`
- RCON port: `27020/tcp`
- RCON may come up late under emulation.
- Crossplay/Epic support requires explicit launch handling.
- Passworded join testing can complicate diagnosis; use no password while validating visibility/joinability.

## Technical debt to address next

### Priority 1: stabilize the ARK implementation
- Ensure `start.sh` uses bounded readiness waits.
- Ensure `start.sh` has signal-based shutdown fallback if RCON is unavailable.
- Ensure file ownership is consistently repaired or controlled between install/runtime.
- Make logging and health output clearer.
- Make direct-join validation part of the README troubleshooting flow.

### Priority 2: clean configuration contracts
- Normalize env var naming. For example, avoid multiple competing variables for additional args.
- Ensure `.env.example`, compose, and scripts all agree on variable names.
- Document which variables are generic versus ARK-specific.

### Priority 3: introduce multi-game structure
Move toward a layout like:

```text
games/
  arkse/
    game.env.example
    install.sh
    start.sh
    config/
  valheim/
    ...
  sevendaystodie/
    ...
shared/
  scripts/
  compose/
```

Alternative acceptable approach:

```text
games/
  arkse.sh
  valheim.sh
  ...
config/
  arkse/
  valheim/
```

The exact structure can be chosen by Codex, but it must keep per-game logic discoverable.

## Recommended roadmap for multi-game support

### Phase 1: harden ARK
- finalize stable ARK install/start/stop flow
- improve logging and docs
- ensure Epic crossplay behavior is documented

### Phase 2: define a generic game contract
Create a simple metadata contract per game, such as:
- game id / slug
- Steam app id
- install image/runtime image
- server binary path
- install entrypoint logic
- startup URI/CLI builder
- exposed ports
- readiness strategy
- shutdown strategy
- mod support model

Do not make this overly abstract. A Bash-sourced metadata file is fine.

### Phase 3: add second supported game
Choose a second Steam-based game that is operationally simpler than ARK. The point is to validate the architecture with a contrasting example.

Good candidates:
- a Linux dedicated server with simpler startup and logging
- minimal or no mod complexity initially

### Phase 4: shared templates and profiles
Add compose profiles or per-game compose files so users can run:
- one game / one instance
- one game / multiple instances
- multiple different games on the same ARM host

### Phase 5: instance management
Only if needed, introduce reusable instance directories and helpers for:
- instance-specific env files
- backups
- scheduled updates
- mod sync

## Operational requirements

Any Codex changes should preserve or improve these workflows:

### Install/update
- one explicit install/update command
- understandable install logs
- validation toggle support where applicable

### Start/stop
- reliable foreground process management
- no infinite waits on readiness
- graceful stop when possible, hard stop fallback when not

### Backup
- backups should not silently fail
- document what is backed up

### Troubleshooting
README should cover:
- permissions/ownership issues
- container restart loops
- missing logs
- ports and firewall expectations
- browser visibility vs direct join
- RCON-specific issues

## Coding guidance for future Codex work

When implementing features, Codex should:
- prefer targeted changes over broad rewrites
- explain assumptions in code comments where the runtime behavior is non-obvious
- update docs when changing behavior
- keep scripts debuggable with straightforward logging
- avoid adding hidden magic or dynamic code generation unless it clearly pays off

## What not to do

- Do not turn this into Kubernetes.
- Do not introduce a database.
- Do not build a web panel unless explicitly requested.
- Do not over-generalize before a second game exists.
- Do not require RCON for basic lifecycle management.
- Do not silently swallow critical failures.

## Immediate next tasks Codex can work on

1. Reconcile `.env.example`, `docker-compose.yml`, and `scripts/start.sh` so env names are consistent.
2. Improve `start.sh` readiness and shutdown behavior.
3. Add a documented no-password test mode for joinability validation.
4. Add README troubleshooting for Epic visibility/joinability.
5. Introduce a first draft of a per-game metadata structure without breaking ARK.

## Definition of done for changes

A change is not done unless:
- scripts remain readable
- docs reflect the new behavior
- current ARK flow still works
- failure behavior is clearer than before
- the path toward multi-game support becomes better, not murkier

