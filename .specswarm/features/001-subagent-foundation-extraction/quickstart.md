# Quickstart: v7 `/ss:init` with spec-corpus extraction

This is what a developer sees when running `/ss:init` on a project with a rich spec corpus, post-v7.

## Scenario: First-time init on a project with `docs/STRATEGY.md` + `docs/RULES.md` + memory dir

```text
$ /ss:init

📋 SpecSwarm /ss:init v7.0.0 — initialize project guides

Step 1/7 — Snapshotting existing .specswarm/ … (nothing to back up)
Step 1.5/7 — Parsing existing guides … (none found)
Step 1.6/7 — Sufficiency check … (no existing guides — proceeding to fresh setup)
Step 2/7 — Auto-detecting tech stack from package.json …
   • Framework: React Router (v7.2.1)
   • Language:  TypeScript (5.x, strict)
   • Build:     Vite

Step 3/7 — Interactive configuration …
   Quality level: Medium  (defaulting to industry standards; tighten in Step 4.2 if your corpus says otherwise)

Step 3.0/7 — Discovering project sources …
   🔍 Dispatched source-discovery agent.
   ⟳ Working …
   ✓ Discovered 3 spec-docs, 12 memory files, 7 configs, 1247 noise.

Step 3.5/7 — Reconciling references.md from discovery …
   📄 docs/STRATEGY.md      → spec-corpus
   📄 docs/RULES.md         → spec-corpus
   📄 docs/BUDGETS.md       → spec-corpus
   🧠 ~/.claude/.../memory  → memory-dir (12 files)

Step 4.0/7 — Extracting foundation-file proposals (3 subagents in parallel) …
   🚀 Dispatched: tech-stack, quality-standards, constitution.
   ⟳ Working …
   ✓ Tech-stack:          17 proposals (12 high / 4 medium / 1 low)
   ✓ Quality-standards:   14 proposals (8 high / 6 medium / 0 low)
   ✓ Constitution:         5 principles (4 with rule blocks, 1 warn / 4 block)

Step 4.1/7 — Aggregating + verifying citations …
   • Deduped 3 cross-extractor overlaps
   • Detected 1 conflict (framework: STRATEGY says React Router v7 [DECIDED], package.json reports 7.2.1)
   • Citation verification: 35/36 verified (1 downgraded to "review required")

Step 4.2/7 — Confirming extracted proposals …
```

Then the user is presented with a short batch of `AskUserQuestion` prompts:

```text
   tech-stack.md — 12 high-confidence decisions extracted from docs/STRATEGY.md
   [1] Accept all (Recommended)
   [2] Review one by one
   [3] Skip — fill in later
```

After batch-acceptance, conflicts and ambiguous items follow:

```text
   tech-stack.md — framework: two sources disagree
   • React Router v7 (docs/STRATEGY.md:42 [DECIDED])
   • Next.js (CONTRIBUTING.md:14 — passing mention)
   [1] React Router v7 (Recommended)
   [2] Next.js
   [3] Skip — resolve manually later
   [4] Custom value
```

Roughly 5–10 prompts later, the user reaches Step 4 (foundation generation) without manual data entry:

```text
Step 4/7 — Writing .specswarm/constitution.md … (5 principles, 4 hook rule-blocks)
Step 5/7 — Writing .specswarm/tech-stack.md … (12 decisions accepted, 5 user-additions block)
Step 6/7 — Writing .specswarm/quality-standards.md … (14 budgets accepted)
Step 6.5/7 — Convention analysis … (3 conventions inferred)
Step 6.7/7 — MCP recommendations … (none for this stack)
Step 6.8/7 — Subagent seeding … (skipped — no react-typescript pattern detected)
Step 7/7 — Summary
   ✓ 4 foundation files generated
   ✓ 31 extracted proposals accepted, 2 deferred (TODO comments in files)
   ✓ Time: 1m 47s

📁 Files: .specswarm/{constitution,tech-stack,quality-standards,references}.md
🛡️  4 constitutional hooks generated under .specswarm/hooks/generated/
```

## Scenario: Thin project (just README + package.json)

```text
$ /ss:init

Step 3.0/7 — Discovering project sources …
   ✓ Discovered 0 spec-docs, 0 memory files, 3 configs, 14 noise.

(no Step 4.0 — nothing to extract from)

Step 3.5/7 — Reconciling references.md from discovery … (no candidates)
Step 4/7 — Writing .specswarm/constitution.md … (template; user fills in)
…
Step 7/7 — Summary
   ✓ 4 foundation files generated (from auto-detect + interactive defaults)
   ✓ No spec corpus found — extraction step skipped
   ✓ Time: 0m 22s
```

Substantively identical to v6.4.0 behavior; only the discovery line is new and harmless.

## Flag surface (new in v7)

- `--full-scan` — lift the default depth bounds in Step 3.0. Use this when your spec docs live outside `docs/`, `specs/`, or `documentation/`.
- `--include-user-memory` — let extractors read `user_*.md` memory files (personal-context, default-skip).

All v6.x flags (`--reset`, `--minimal`) work unchanged.

## What `--minimal` does in v7

Same as v6.4.0: skips all interactive prompts. v7 additionally skips Step 3.0 discovery and Step 4.0 extractors entirely under `--minimal` (no point dispatching subagents if no acceptance UI will run). Foundation files are generated from auto-detect defaults only.

## Re-run drift behavior

After a previous `/ss:init` and subsequent corpus edits:

```text
Step 4.2/7 — Confirming extracted proposals …

   tech-stack.md — unit_test: declared value differs from corpus
   declared: vitest
   corpus:   playwright-component (docs/STRATEGY.md:§testing-tools [DECIDED 2026-05-15])
   [1] Use corpus value (Recommended)
   [2] Keep declared value
   [3] Skip — review later
```

User picks; `.specswarm/tech-stack.md` is regenerated; `<!-- ss:user-additions -->` content survives verbatim.
