---
description: Identify underspecified areas in the current feature spec by asking up to 5 highly targeted clarification questions and encoding answers back into the spec.
hidden: true
effort: high
---

<!--
ATTRIBUTION CHAIN:
1. Original: GitHub spec-kit (https://github.com/github/spec-kit)
   Copyright (c) GitHub, Inc. | MIT License
2. Adapted: SpecKit plugin by Marty Bonacci (2025)
3. Forked: SpecSwarm plugin with tech stack management
   by Marty Bonacci & Claude Code (2025)
-->


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

Goal: Detect and reduce ambiguity or missing decision points in the active feature specification and record the clarifications directly in the spec file.

Note: This clarification workflow is expected to run (and be completed) BEFORE invoking `/speckit.plan`. If the user explicitly states they are skipping clarification (e.g., exploratory spike), you may proceed, but must warn that downstream rework risk increases.

Execution steps:

1. **Discover Feature Context**:
   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

   # Source features location helper
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
   source "$PLUGIN_DIR/lib/features-location.sh"

   # Initialize features directory
   get_features_dir "$REPO_ROOT"

   BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
   FEATURE_NUM=$(echo "$BRANCH" | grep -oE '^[0-9]{3}')
   [ -z "$FEATURE_NUM" ] && FEATURE_NUM=$(list_features "$REPO_ROOT" | grep -oE '^[0-9]{3}' | sort -nr | head -1)

   find_feature_dir "$FEATURE_NUM" "$REPO_ROOT"
   # FEATURE_DIR is now set by find_feature_dir
   FEATURE_SPEC="${FEATURE_DIR}/spec.md"
   ```

   Validate: If FEATURE_SPEC doesn't exist, ERROR: "No spec found. Run `/specify` first."

2. Load the current spec file. Perform a structured ambiguity & coverage scan using this taxonomy. For each category, mark status: Clear / Partial / Missing. Produce an internal coverage map used for prioritization (do not output raw map unless no questions will be asked).

   Functional Scope & Behavior:
   - Core user goals & success criteria
   - Explicit out-of-scope declarations
   - User roles / personas differentiation

   Domain & Data Model:
   - Entities, attributes, relationships
   - Identity & uniqueness rules
   - Lifecycle/state transitions
   - Data volume / scale assumptions

   Interaction & UX Flow:
   - Critical user journeys / sequences
   - Error/empty/loading states
   - Accessibility or localization notes

   Non-Functional Quality Attributes:
   - Performance (latency, throughput targets)
   - Scalability (horizontal/vertical, limits)
   - Reliability & availability (uptime, recovery expectations)
   - Observability (logging, metrics, tracing signals)
   - Security & privacy (authN/Z, data protection, threat assumptions)
   - Compliance / regulatory constraints (if any)

   Integration & External Dependencies:
   - External services/APIs and failure modes
   - Data import/export formats
   - Protocol/versioning assumptions

   Edge Cases & Failure Handling:
   - Negative scenarios
   - Rate limiting / throttling
   - Conflict resolution (e.g., concurrent edits)

   Constraints & Tradeoffs:
   - Technical constraints (language, storage, hosting)
   - Explicit tradeoffs or rejected alternatives

   Terminology & Consistency:
   - Canonical glossary terms
   - Avoided synonyms / deprecated terms

   Completion Signals:
   - Acceptance criteria testability
   - Measurable Definition of Done style indicators

   Misc / Placeholders:
   - TODO markers / unresolved decisions
   - Ambiguous adjectives ("robust", "intuitive") lacking quantification

   For each category with Partial or Missing status, add a candidate question opportunity unless:
   - Clarification would not materially change implementation or validation strategy
   - Information is better deferred to planning phase (note internally)

2.5. **Cross-Check Against External References** (NEW in v6.1.0):

   Before generating the question queue, check whether each candidate question is already answered in the project's external references. The point of clarification is to *resolve* ambiguity — not to re-ask decisions the corpus has already locked in. For projects with substantial spec corpora and decision logs (Marty's customcult-v3 has 379+ [OPEN] markers, most with explicit corpus-side resolutions), this filter dramatically reduces noise.

   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
   PLUGIN_DIR_SS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
   LOADER="${PLUGIN_DIR_SS}/lib/references-loader.sh"

   REFERENCES_AVAILABLE=false
   SPEC_CORPUS_PATHS=()
   MEMORY_DIRS=()
   PRIOR_REFS_CONSULTED=()

   if [ -f "$LOADER" ]; then
     # shellcheck disable=SC1090
     source "$LOADER"

     if ss_references_exist; then
       REFERENCES_AVAILABLE=true

       while IFS= read -r path; do
         [ -z "$path" ] && continue
         abs=$(ss_references_resolve_path "$path")
         [ -f "$abs" ] && SPEC_CORPUS_PATHS+=("$abs")
       done < <(ss_references_spec_corpus_paths)

       while IFS= read -r path; do
         [ -z "$path" ] && continue
         [ -d "$path" ] && MEMORY_DIRS+=("$path")
       done < <(ss_references_memory_dirs)
     fi
   fi

   # Read references_consulted from spec.md frontmatter (set by /ss:specify in v6.1.0+)
   if [ -f "$FEATURE_SPEC" ]; then
     # Extract YAML frontmatter; parse 'references_consulted:' list
     # (Awk-only — no yq dependency)
     while IFS= read -r line; do
       [ -z "$line" ] && continue
       PRIOR_REFS_CONSULTED+=("$line")
     done < <(awk '
       /^---$/ { fm = !fm; next }
       fm && /^references_consulted:/ { in_list=1; next }
       fm && in_list && /^[[:space:]]*-[[:space:]]/ {
         sub(/^[[:space:]]*-[[:space:]]*/, "")
         sub(/[[:space:]]*#.*$/, "")
         sub(/[[:space:]]*$/, "")
         print
       }
       fm && in_list && /^[^[:space:]-]/ { in_list=0 }
     ' "$FEATURE_SPEC" 2>/dev/null)
   fi

   if [ "$REFERENCES_AVAILABLE" = true ]; then
     echo ""
     echo "🔗 Cross-checking candidate questions against external references:"
     for p in "${SPEC_CORPUS_PATHS[@]}"; do
       echo "   📄 $p"
     done
     for d in "${MEMORY_DIRS[@]}"; do
       echo "   🧠 $d"
     done
     if [ "${#PRIOR_REFS_CONSULTED[@]}" -gt 0 ]; then
       echo ""
       echo "   ↳ Spec.md frontmatter notes these refs were already consulted at /ss:specify time:"
       for r in "${PRIOR_REFS_CONSULTED[@]}"; do
         echo "     - $r"
       done
     fi
     echo ""
   fi
   ```

   **If `REFERENCES_AVAILABLE = true`, you (Claude) MUST do the following BEFORE generating the question queue in Step 3:**

   a. **Read each spec corpus path** in `SPEC_CORPUS_PATHS[@]` using the `Read` tool. Prioritize sections most likely to contain decisions:
   - Decision logs (typically `## Decision Log` or files with dated entries)
   - Schema definitions (data model sections)
   - Authoritative-source pointers (e.g., a builder kickoff doc that names which doc owns which topic)

   b. **Scan memory dirs** in `MEMORY_DIRS[@]` for `feedback_*.md` (preferences/rules) and `project_*.md` (state/context) files. These often encode decisions that aren't in the formal corpus.

   c. **For EACH candidate question from Step 2's ambiguity scan**, do this filter pass:
   - Search the corpus for matching content (use `Bash` + grep when corpus is large; use `Read` when targeted)
   - Categorize the question:
     - **CORPUS-RESOLVED** — corpus contains an explicit decision; drop the question and instead inject the corpus answer directly into the spec with a citation. Note this in the report (Step 8).
     - **CORPUS-PARTIAL** — corpus has related context but doesn't decide; keep the question, but PRE-LOAD the candidate answers from corpus context. AskUserQuestion options should reflect what the corpus has hinted at, plus any genuine alternatives.
     - **CORPUS-SILENT** — corpus says nothing; question proceeds as normal.
     - **CORPUS-CONFLICT** — corpus says X but the spec says Y. Surface this as a special blocking question: "The corpus (`{path}`) says X. Spec says Y. Which is canonical?" — answers feed back to spec.md.

   d. **Skip-question accounting**: keep an internal count of CORPUS-RESOLVED questions skipped. The Step 3 question budget (max 5) MAY be increased proportionally — if 3 questions were skipped because the corpus answered them, you have effectively 5 + 0 = 5 remaining (don't pad the queue with low-value questions just because budget exists). Lower-impact questions you previously held back can now surface if needed, but it's better to ask 2 high-impact questions than to pad to 5.

   e. **Citation discipline**: any candidate-question answer drawn from the corpus must cite the source in the spec update (per Step 5: Integration). Same format as /ss:specify Sources:
   ```markdown
   ### Q3: Authentication method (auto-resolved from corpus)

   **Answer**: OAuth-first signup (Google + Apple primary; email/password fallback)
   **Source**: `INTERACTION-FLOWS.md` Section 5.11.5.1 + `feedback_share_strategy.md` (Share Encouragement Strategy SE.4)
   **Decision date**: 2026-04-30 per CREATING-THE-STRATEGY.md decision log
   ```

   **If `REFERENCES_AVAILABLE = false`** (no references.md, or empty), skip Step 2.5 entirely. Question queue generation in Step 3 proceeds with v6.0.0 behavior — ambiguity-scan candidates flow directly into the prioritized queue with no corpus filter. No skip-accounting, no citations, no Sources.

3. Generate (internally) a prioritized queue of candidate clarification questions (maximum 5). Do NOT output them all at once. Apply these constraints:
    - Maximum of 10 total questions across the whole session.
    - Each question must be answerable with EITHER:
       * A short multiple‑choice selection (2–5 distinct, mutually exclusive options), OR
       * A one-word / short‑phrase answer (explicitly constrain: "Answer in <=5 words").
   - Only include questions whose answers materially impact architecture, data modeling, task decomposition, test design, UX behavior, operational readiness, or compliance validation.
   - Ensure category coverage balance: attempt to cover the highest impact unresolved categories first; avoid asking two low-impact questions when a single high-impact area (e.g., security posture) is unresolved.
   - Exclude questions already answered, trivial stylistic preferences, or plan-level execution details (unless blocking correctness).
   - Favor clarifications that reduce downstream rework risk or prevent misaligned acceptance tests.
   - If more than 5 categories remain unresolved, select the top 5 by (Impact * Uncertainty) heuristic.

4. Sequential questioning loop (interactive):
    - Present EXACTLY ONE question at a time.
    - Use the **AskUserQuestion** tool for each question:
       * For multiple-choice questions, provide options with descriptions
       * Include an "Other" option for free-form alternatives (when appropriate)
       * Set header to show progress: "Clarification N/M" (e.g., "Clarification 2/5")
       * Options should be concise labels (1-5 words) with detailed descriptions

    **Example AskUserQuestion usage:**
    ```
    Question: "What authentication method should we use?"
    Header: "Clarification 2/5"
    Options:
      1. "JWT tokens"
         Description: "JWT tokens with refresh rotation"
      2. "Session-based"
         Description: "Session-based with Redis storage"
      3. "OAuth 2.0"
         Description: "OAuth 2.0 with external provider"
      4. "Other"
         Description: "Provide alternative (<=5 words)"
    ```

    - When "Other" option is selected, prompt for free-form text input (<=5 words).
    - After receiving answer:
       * Record it in working memory (do not yet write to disk)
       * Move to the next queued question immediately
    - Stop asking further questions when:
       * All critical ambiguities resolved early (remaining queued items become unnecessary), OR
       * User signals completion (via "Other" response like "done", "good", "no more"), OR
       * You reach 5 asked questions.
    - Never reveal future queued questions in advance.
    - If no valid questions exist at start, immediately report no critical ambiguities.

5. Integration after EACH accepted answer (incremental update approach):
    - Maintain in-memory representation of the spec (loaded once at start) plus the raw file contents.
    - For the first integrated answer in this session:
       * Ensure a `## Clarifications` section exists (create it just after the highest-level contextual/overview section per the spec template if missing).
       * Under it, create (if not present) a `### Session YYYY-MM-DD` subheading for today.
    - Append a bullet line immediately after acceptance: `- Q: <question> → A: <final answer>`.
    - Then immediately apply the clarification to the most appropriate section(s):
       * Functional ambiguity → Update or add a bullet in Functional Requirements.
       * User interaction / actor distinction → Update User Stories or Actors subsection (if present) with clarified role, constraint, or scenario.
       * Data shape / entities → Update Data Model (add fields, types, relationships) preserving ordering; note added constraints succinctly.
       * Non-functional constraint → Add/modify measurable criteria in Non-Functional / Quality Attributes section (convert vague adjective to metric or explicit target).
       * Edge case / negative flow → Add a new bullet under Edge Cases / Error Handling (or create such subsection if template provides placeholder for it).
       * Terminology conflict → Normalize term across spec; retain original only if necessary by adding `(formerly referred to as "X")` once.
    - If the clarification invalidates an earlier ambiguous statement, replace that statement instead of duplicating; leave no obsolete contradictory text.
    - Save the spec file AFTER each integration to minimize risk of context loss (atomic overwrite).
    - Preserve formatting: do not reorder unrelated sections; keep heading hierarchy intact.
    - Keep each inserted clarification minimal and testable (avoid narrative drift).

6. Validation (performed after EACH write plus final pass):
   - Clarifications session contains exactly one bullet per accepted answer (no duplicates).
   - Total asked (accepted) questions ≤ 5.
   - Updated sections contain no lingering vague placeholders the new answer was meant to resolve.
   - No contradictory earlier statement remains (scan for now-invalid alternative choices removed).
   - Markdown structure valid; only allowed new headings: `## Clarifications`, `### Session YYYY-MM-DD`.
   - Terminology consistency: same canonical term used across all updated sections.

7. Write the updated spec back to `FEATURE_SPEC`.

8. Report completion (after questioning loop ends or early termination):
   - Number of questions asked & answered.
   - **Number of questions auto-resolved from corpus (NEW in v6.1.0)** — questions that would have been asked but were instead answered from references with citations. Display these in a separate sub-list:
     ```
     Auto-resolved from references (3):
       • Authentication method → OAuth-first (per INTERACTION-FLOWS.md §5.11.5.1)
       • Email service → Resend (per CREATING-THE-STRATEGY.md §4.15)
       • Cookie consent scope → EU/UK/CA via cf-ipcountry (per CC.7)
     ```
   - **Number of CORPUS-CONFLICT questions surfaced (if any)** — these block proceeding to /ss:plan.
   - Path to updated spec.
   - Sections touched (list names).
   - Coverage summary table listing each taxonomy category with Status: Resolved (was Partial/Missing and addressed by user OR by corpus auto-resolution), Deferred (exceeds question quota or better suited for planning), Clear (already sufficient), Outstanding (still Partial/Missing but low impact).
   - If any Outstanding or Deferred remain, recommend whether to proceed to `/speckit.plan` or run `/speckit.clarify` again later post-plan.
   - Suggested next command.

Behavior rules:
- If no meaningful ambiguities found (or all potential questions would be low-impact), respond: "No critical ambiguities detected worth formal clarification." and suggest proceeding.
- If spec file missing, instruct user to run `/speckit.specify` first (do not create a new spec here).
- Never exceed 5 total asked questions (clarification retries for a single question do not count as new questions).
- Avoid speculative tech stack questions unless the absence blocks functional clarity.
- Respect user early termination signals ("stop", "done", "proceed").
 - If no questions asked due to full coverage, output a compact coverage summary (all categories Clear) then suggest advancing.
 - If quota reached with unresolved high-impact categories remaining, explicitly flag them under Deferred with rationale.

Context for prioritization: {ARGS}
