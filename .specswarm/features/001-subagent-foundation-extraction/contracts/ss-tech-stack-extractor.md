# Contract: ss-tech-stack-extractor

## Role

Read project sources and propose content for `.specswarm/tech-stack.md`. One of three extractors dispatched in parallel from Step 4.0.

## Dispatch

From `/ss:init` Step 4.0, as one of three concurrent `Agent` tool calls in a single assistant message:

```
Agent({
  description: "Extract tech-stack proposals from spec corpus",
  subagent_type: "general-purpose",
  prompt: <prompt body, with reading list interpolated from discovery output>
})
```

## Inputs

- `.specswarm/.discovery.tmp` contents (parent reads, passes a filtered subset to the subagent in the prompt)
- Filtered reading list:
  - All `spec-doc` records (paths from `.discovery.tmp`)
  - Memory files matching `project_tech*`, `project_*stack*`, `project_*framework*`, `project_*decisions*`
  - `package.json`, lockfile, `tsconfig.json`, framework config files (if present)
  - Excluded: `user_*.md` (unless parent invoked with `--include-user-memory`)

## Process

1. Read each file on the reading list in full (or via grep for files > 2000 lines — search for keys named below).
2. Identify the canonical-section values listed under Output Keys.
3. Tag each finding with confidence per the rules below.
4. Emit a pipe-delimited record per finding to `.specswarm/.proposals.tech-stack.tmp`.

## Output keys

- `framework`, `framework_version`
- `language`, `language_version`, `language_strict_flags`
- `build_tool`, `build_tool_version`
- `state_mgmt`
- `styling`
- `unit_test`, `integration_test`, `e2e_test`
- `approved_lib.<n>` — positional, n=1..k (k ≤ 20)
- `prohibited.<n>` — positional, n=1..k
- `open_decision.<n>` — items tagged `[OPEN]` with phase deadlines

## Confidence rules

- `high`: explicit + version + `[DECIDED]` marker or equivalent (decision log entry, ratified strategy doc)
- `medium`: explicit but no decision marker
- `low`: inferred (a single dep entry without prose; a single mention in a non-canonical file)

## Output format

See [data-model.md §Format 2](../data-model.md). Pipe-delimited; multi-line values use `<<<BLOCK ... BLOCK`.

## Constraints

- Cap 60 records
- Skip duplicates within own output (prefer highest confidence on collision)
- Report under 800 lines back to parent

## Prompt body (verbatim)

> You are SpecSwarm's tech-stack extractor. Read project sources and propose content for `.specswarm/tech-stack.md`.
>
> Read in full (or via grep where files exceed 2000 lines):
> <INTERPOLATED_READING_LIST>
>
> Identify:
> 1. Framework (name + version + rationale)
> 2. Language (name + version + strict flags + rationale)
> 3. Build tool (name + version + rationale)
> 4. State management approach
> 5. Styling approach
> 6. Testing tools (unit / integration / e2e — each)
> 7. Approved libraries (positive list)
> 8. Prohibited technologies (negative list — "do not use X", "rejected over Y")
> 9. Open tech decisions (`[OPEN]` markers tied to tech choices with phase deadlines)
>
> Output your proposals to `.specswarm/.proposals.tech-stack.tmp` as pipe-delimited records:
>
> ```
> tech-stack|<key>|<value>|<confidence>|<citation>|<rationale>
> ```
>
> Where:
> - `<key>` is one of: `framework`, `framework_version`, `language`, `language_version`, `language_strict_flags`, `build_tool`, `build_tool_version`, `state_mgmt`, `styling`, `unit_test`, `integration_test`, `e2e_test`, `approved_lib.<n>`, `prohibited.<n>`, `open_decision.<n>` (positional indices for repeated keys)
> - `<confidence>` is one of: `high` (explicit + version + `[DECIDED]` marker), `medium` (explicit, no decision marker), `low` (inferred)
> - `<citation>` is `<repo-relative-path>` or `<repo-relative-path>:<line-or-§section>`
> - `<rationale>` is free text on one line
>
> If any field contains a newline, a literal `|`, or the markers themselves, wrap the field in:
>
> ```
> <<<BLOCK
> ...content...
> BLOCK
> ```
>
> The BLOCK closer sits alone on its line. After the closer, the next character is the next field delimiter `|`.
>
> Cap 60 records. Skip duplicates within your output (prefer highest confidence).
>
> When you've written the file, return a brief acknowledgment to the parent: `Tech-stack: <N> proposals (<H> high / <M> medium / <L> low).`

## Failure modes

- **Empty/truncated output**: parent's Step 4.1 sees an empty file → falls back to today's interactive prompts for the tech-stack destination only.
- **Malformed records**: aggregator rejects them and logs to audit; rest of the file is still consumed.
- **No spec-doc input**: subagent should still emit proposals from `package.json` (framework + language + build_tool + testing — confidence `medium` or `low`). Empty output is acceptable only for projects with literally no config files.
