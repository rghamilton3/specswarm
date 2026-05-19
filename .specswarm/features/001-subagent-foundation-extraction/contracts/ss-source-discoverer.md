# Contract: ss-source-discoverer

## Role

Map the project's documentation and configuration surface so the main `/ss:init` flow knows what to extract from. This subagent runs once, before any extraction.

## Dispatch

From `/ss:init` Step 3.0, as a single foreground `Agent` call:

```
Agent({
  description: "Discover and classify SpecSwarm sources",
  subagent_type: "general-purpose",
  prompt: <the prompt body below, with project-specific paths interpolated>
})
```

## Inputs

- Repo root (`pwd` at `/ss:init` invocation)
- `--full-scan` flag state (boolean)
- Canonical Claude Code memory path: `$HOME/.claude/projects/$(pwd | tr / -)/memory/`

## Process

1. From repo root, list files respecting `.gitignore`. Skip `node_modules`, `.git`, `dist`, `build`, `vendor`, lockfiles, files > 1 MB.
2. Default scan roots (no `--full-scan`): `docs/`, `specs/`, `documentation/`, `.specswarm/specs/`, repo root depth-1 `*.md`/`*.mdx`, standard config files at repo root. With `--full-scan`: respect `.gitignore` and size cap, no depth limit.
3. For markdown files: read first 50 + last 20 lines to classify and to draft a one-sentence summary.
4. For configs: extract version/dependency hints (don't dump full files).
5. Check the canonical memory dir. List files if present.
6. Stem-filtered sibling-repo scan one level up (matches existing Step 3.5 logic).
7. Cap total classified entries at 200; aggregate the remainder into a single `noise-rollup` line.

## Categories (each file goes in exactly one)

- `spec-doc`: markdown describing decisions, requirements, architecture, rules
- `documentation`: README/CONTRIBUTING/CHANGELOG (general; not decisions)
- `config`: build/tooling configuration (extract values)
- `memory`: Claude Code memory file (`feedback_`/`project_`/`reference_`/`user_`)
- `reference-codebase`: external repo referenced by docs
- `source-code`: implementation (note language + count only; aggregate at the top-level subdir)
- `noise`: lockfiles, snapshots, auto-generated, irrelevant

## Output

Write to `.specswarm/.discovery.tmp` in the TSV format defined in [data-model.md §Format 1](../data-model.md). Then report a brief acknowledgment to the parent (one line): `Discovered <N> spec-docs, <M> memory files, <K> configs, <noise-count> noise.`

## Constraints

- ≤ 200 classified records + 1 noise-rollup row
- Report under 500 lines back to parent (the report is the brief acknowledgment; the bulk of the data is in the .tmp file)
- Cite paths relative to repo root
- One-sentence summaries only — do NOT summarize entire files

## Prompt body (verbatim — ships in init.md Step 3.0)

> You are SpecSwarm's source-discovery agent. Map this project's documentation and configuration surface so the main `/ss:init` flow knows what to extract from.
>
> Repo root: `<INTERPOLATED_REPO_ROOT>`
> Full-scan mode: `<INTERPOLATED_FULL_SCAN_FLAG>` (default: false — scan only `docs/`, `specs/`, `documentation/`, `.specswarm/specs/`, repo-root depth-1 `*.md`/`*.mdx`, plus standard config files at repo root)
> Canonical memory dir: `<INTERPOLATED_MEMORY_DIR>` (only if it exists)
>
> Procedure:
> 1. From repo root, list all files respecting `.gitignore`. Skip `node_modules`, `.git`, `dist`, `build`, `vendor`, lockfiles, files > 1 MB.
> 2. For markdown files (.md, .mdx), read first 50 + last 20 lines to classify.
> 3. For configs (package.json, tsconfig.json, vite.config.\*, drizzle.config.\*, etc.), extract version/dependency info.
> 4. Check the canonical Claude Code memory at the interpolated path — list files if present.
> 5. Check sibling repos one level up via stem-filtered scan (match the current repo's basename stem before the first hyphen/underscore/dot).
>
> Classify each file into exactly one of:
> - `spec-doc`: markdown describing decisions, requirements, architecture, rules
> - `documentation`: README/CONTRIBUTING/CHANGELOG (general; not decisions)
> - `config`: build/tooling configuration (extract values)
> - `memory`: Claude Code memory file (`feedback_`/`project_`/`reference_`/`user_`)
> - `reference-codebase`: external repo referenced by docs
> - `source-code`: implementation (note language + count only)
> - `noise`: lockfiles, snapshots, auto-generated, irrelevant
>
> Write your output to `.specswarm/.discovery.tmp` as one record per line in tab-separated form:
>
> ```
> <category>\t<path>\t<size-bytes>\t<one-sentence-summary-or-empty>
> ```
>
> Spec-doc records MUST have a non-empty summary (one sentence, no embedded tabs or newlines). Other categories may have empty summaries.
>
> End the file with a single noise rollup row:
>
> ```
> noise-rollup\t\t<total-noise-files>\t<dominant-extensions-with-counts>
> ```
>
> Cap the total at 200 classified entries plus the rollup row. Cite paths relative to repo root. Do NOT summarize entire files.
>
> When you've written the file, return a brief acknowledgment to the parent in this exact form: `Discovered <N> spec-docs, <M> memory files, <K> configs, <noise-count> noise.`

## Failure modes

- **Cannot write `.specswarm/.discovery.tmp`**: parent detects empty/missing file in Step 3.5, falls back to v6.4.0 references behavior (no discovery-informed filtering). Step 4.0 short-circuits to "no spec content found".
- **Cap hit before scan completes**: rollup row reflects the cap. Recommend `--full-scan` in the report if it tripped.
- **Memory dir missing**: silent — produce no `memory` records, do not error.
