# AI game development workflow

This repository contains an original reference (`OriginGame.html`) and a separate Godot development/test framework (`engine/sandbox/runtime/`) and a reserved bank-game layer (`game/`). Preserve the original unless the user requests changes. This is a runnable foundation, not a completed port.

## Working loop

1. Use the project Skill `.agents/skills/aigameengine-dev/SKILL.md` and direct scripts by default; the game MCP adapter is optional and not auto-registered. Read `README.md`, `project/tasks.json`, `project/acceptance.json` and the affected scene/scripts. Run `python engine/run.py project`; select the requested task and define a concrete observable result before editing.
2. Use the pinned Godot engine in `.tools/` (or `GODOT_BIN`). Prefer small changes to the relevant gameplay component.
3. Import changed assets with `python engine/run.py lab import`. Run `python engine/run.py qa --headless` for logic and input changes.
4. For any model, material, texture, lighting, camera or UI change, run rendered `python engine/run.py qa`. Read the actual PNGs using the assistant's image-viewing tool, not just state JSON. Headless success is not visual evidence.
5. Investigate failures using `report.json`, `engine.log`, scenario failure JSON and `trace.jsonl`. Fix the cause, then rerun affected checks. Preserve evidence from failed runs.
6. Summarize what changed, test results and unverified limitations. Do not claim the original game has been ported or that aesthetic quality has been automatically proven.

## Test integrity

- `reset`, fixture placement, inspection cameras and `asset` are development setup actions. User flow evidence must come from `act`/`click`, through the normal game input handlers. Never call gameplay callbacks directly to make an interaction test pass.
- Keep tests independent and use isolated session saves. Freeze between commands; advance bounded 60 Hz steps. Input commands release their held keys/buttons automatically.
- Never promote a baseline merely to turn a failure green. Inspect actual and baseline images, explain intentional changes, and explicitly run `engine/run.py visual --reviewer ...` only after review. An AI fixture review is not the user's final art approval.
- Baseline masks require a documented genuinely dynamic region. Do not hide important controls, geometry, or material defects.
- Do not lower assertions, change expected gameplay rules, or remove failing tests without a reason grounded in the requested change.
- Engine, renderer and GPU changes produce `needs_review`, not a pass. Keep capture resolutions, framing and world state fixed.
- The optional MCP adapter and CLI expose the same bridge. No remote service or API key is needed. Do not change global client configuration unless requested.
- The bridge requires a debug build and explicit local session directory. Preserve release gating and bounded commands. Do not add arbitrary code-evaluation commands.
- Transport must depend only on `engine/godot/testing/game_adapter.gd`, never bank-specific fields. Prove interface changes against both the lab and the independent probe world.
- Preserve complete adapter-owned state: clocks, queued commands, RNG (64-bit values encoded as strings), NPC cooldown/origins, animation and UI. Reject invalid snapshots before any mutation. Do not describe engine contact caches or external side effects as restored.
- Dynamic visual changes need sequence evidence. Observe actual frames/contact sheets; use manual AnimationPlayer advancement so waiting for PNG rendering does not move simulation forward.
- `engine/run.py visual --accept-visual-changes --reason ...` only acknowledges reviewed visual changes. It cannot override failed executable checks. Selected promotions preserve unselected baselines.
- Keep `project/tasks.json` current. Completed tasks need evidence references. Manual acceptance is never inferred from pixel equality or test exit codes; review must be scoped and tied to the exact report/evidence hashes.

## Entry points

- Asset work: read `docs/assets.md`. Use `engine/run.py assets` / the asset MCP tools; preserve source snapshots, explicit units/texture roles and revision references. Do not infer readiness from a queued job or aesthetic approval from a valid footprint.
- Run `python engine/run.py asset_qa` after asset pipeline changes, inspect actual contact sheets, and use real `act` input in `assembly:<scene_id>` to verify gameplay. Default release export excludes the experimental asset library and generated rooms.

- `python engine/run.py lab start` / `call` / `replay`: agent-driven observation and play.
- `python engine/run.py qa`: scenario regression + visual evidence + HTML/JSON report.
- `python -m unittest discover -s engine/tests -p "test_*.py" -v`: test the test machinery, including negative regression cases and MCP gameplay.
- `python engine/run.py lab play`: normal manual play, without automation.
- `engine/tools/build.ps1`: release Windows EXE; `engine/run.py smoke_release` verifies startup and disabled bridge.
- `python engine/run.py project --report <report.json> [--review <review.json>]`: evaluate named acceptance criteria; missing checks remain `not_run`.
- `python engine/run.py sequence <name.sequence.json> --speed 0.25`: create contact sheet, lossless WebP slow motion and frame-by-frame HTML viewer.

The demo NPC is a small patrol/chase/attack state machine with ray-tested visibility, not production navigation. Expand it with real pathfinding and fixture coverage when porting the bank. Current visual assets are test fixtures, not final art direction.

## Layer boundaries

- Maintain tools in `engine/`, game-specific content in `game/`. Shared Godot source lives in `engine/godot`; after edits run `python engine/run.py sync` then `python engine/run.py lab import`. Do not hand-edit deployed addons.
- `workspace.json` selects the project and owns paths. `sandbox` is runnable; `bank` is reserved until PORT-002 creates its real project. Never silently substitute lab for bank.
- New evidence is written to `logs/`; historical `artifacts/` is preserved. Keep each session's trace, captures and state together. Keep durable acceptance evidence in `project/evidence`.
- Source snapshots and catalogue JSON are working data, not caches. SQLite indexes and imported data are rebuildable. Real player saves remain under Godot user data; tests use isolated session saves.
- `tools/` and `tests/` contain only compatibility forwarders. The game MCP code remains optional; do not register it by default. Preserve unrelated client integrations.
