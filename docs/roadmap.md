# `zilliz` / `zz` CLI Roadmap

> Last updated: 2026-05-12

## Vision

A single binary that gives both humans and AI agents a fast, scriptable way to operate Zilliz Cloud and Milvus end-to-end — from cluster provisioning to vector search to local development — without leaving the terminal. The CLI should be the shortest path from "I have an API key" to "I have a working vector workload", and the TUI should be a usable daily console for ops and exploration.

## Current Focus

Items targeted at the current cycle. Several are blocked on upstream API work; the CLI follows as soon as the contract lands.

- [ ] **Global Cluster support** ([#16], P0) — wait for the REST API to expose the Global Cluster shape, then add coverage across `cluster`, `collection`, and metrics paths. Owner: TBD. Blocked on server-side API.
- [ ] **Integrated diagnostics** ([#3]) — a `zilliz diagnose` (working name) flow that bundles cluster health, recent alerts, common error signatures, and connectivity probes into one shareable report, to cut down support back-and-forth.
- [ ] **Experience optimization** - Fluency of use and problem fixes, including command-line prompts, error messages, documentation, etc.
- [x] **Self-update + new-version notifier** ([#12], [#13]) — `zilliz upgrade` and stderr nudge on startup. Shipped in `1.4.1`.
- [x] **Lakebase** — `on-demand-cluster` and `external-collection`. Shipped in `1.4.0`.

## Near-term Goals

Planned but not started. Order is rough.

- **Metrics dashboard in TUI** ([#8]) — interactive ratatui screen with Cluster/Collection tabs and multi-metric line charts, reusing the Braille renderer shipped in `1.3.1`. Owner: TBD.
- **Skill / plugin installation** ([#15]) — first-class commands for installing the AI-agent skills the CLI already generates (`examples/generate_plugin.rs`), so users don't manually place artifacts under Claude Code / other agent runtimes.


## Later

Direction is set, details are still open.

- **TUI expansion beyond metrics** — once #8 lands, evaluate moving cluster lifecycle, context switching, and history browsing into the TUI as full screens (today the TUI is a single welcome screen).
- **Milvus database operations** ([#5]) — extend data-plane coverage so the CLI can drive a Milvus endpoint directly (not only the Zilliz-Cloud-mediated path), including admin / index / segment-level commands.

## Exploring / Considering

Under investigation, no commitment yet.

- A non-interactive **structured error contract** for AI agents: every error path returns a stable JSON error code under `-o json` so agent runtimes can branch reliably. Partially present today (`{"code":..,"message":..}`); the open question is whether to also enumerate codes in a published catalogue.
- **Workspace / profile support**: today the CLI keys context off a single `[default]` section in `~/.zilliz/config`. Multi-profile (think `--profile prod`) would help users juggling dev/uat/cn/prod, but it overlaps with `ZILLIZ_CONFIG_DIR` and isn't an obvious win yet.
- **Streaming output** for long list operations and import jobs, instead of buffering until completion.

## Won't Do

To save discussion cycles.

- **Hardcoding command surface for new resources.** New CRUD resources go through `control-plane.json` / `data-plane.json` (see `CLAUDE.md` "Model-driven CLI"). Adding bespoke handwritten subcommands per resource is rejected unless the operation genuinely needs custom logic (e.g. `cluster create` interactive flow, `milvus standalone`).
- **A separate config format** (TOML / YAML). `~/.zilliz/credentials` and `~/.zilliz/config` stay INI for compatibility with the older `zilliz-cli` and to keep file layout drop-in interchangeable.
- **Forking `zilliz` vs `zz` behavior.** Both binaries delegate into `lib.rs` and stay byte-identical; the alias exists for typing speed only.

---

## How to influence this list

- File or upvote issues at <https://github.com/zilliztech/zilliz-cli/issues>.
- An item moves out of this file when it ships under a tagged release.

[#3]: https://github.com/zilliztech/zilliz-cli/issues/3
[#5]: https://github.com/zilliztech/zilliz-cli/issues/5
[#8]: https://github.com/zilliztech/zilliz-cli/issues/8
[#12]: https://github.com/zilliztech/zilliz-cli/issues/12
[#13]: https://github.com/zilliztech/zilliz-cli/issues/13
[#14]: https://github.com/zilliztech/zilliz-cli/issues/14
[#15]: https://github.com/zilliztech/zilliz-cli/issues/15
[#16]: https://github.com/zilliztech/zilliz-cli/issues/16
