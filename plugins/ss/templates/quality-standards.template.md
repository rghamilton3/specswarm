# Quality Standards - [PROJECT_NAME]

**Last Updated**: [DATE]
**Auto-Generated**: [AUTO_GENERATED]

<!--
  Sections wrapped in the `ss:user-additions` ... `ss:end` HTML comment markers
  (see below) are preserved verbatim when /ss:init is re-run. Edit freely inside
  those blocks. The rest of the file is regenerated from project detection + your
  accepted reconciliation prompts on each /ss:init.
-->

---

## Quality Gates

These thresholds are enforced by `/ss:ship` before allowing merge to parent branch.

```yaml
# Overall Quality
min_quality_score: [MIN_QUALITY_SCORE]  # 0-100 scale (default: 80)
min_test_coverage: [MIN_TEST_COVERAGE]   # Percentage (default: 80)
enforce_gates: [ENFORCE_GATES]           # true/false (default: true)
```

---

## Performance Budgets

```yaml
# Bundle Size Limits
enforce_budgets: [ENFORCE_BUDGETS]     # true/false
max_bundle_size: [MAX_BUNDLE_SIZE]     # KB per bundle (default: 500)
max_initial_load: [MAX_INITIAL_LOAD]   # KB initial load (default: 1000)
max_chunk_size: [MAX_CHUNK_SIZE]       # KB per code-split chunk (default: 200)
```

---

## Code Quality Metrics

```yaml
# Complexity Thresholds
complexity_threshold: [COMPLEXITY_THRESHOLD]  # Cyclomatic complexity (default: 10)
max_file_lines: [MAX_FILE_LINES]             # Lines per file (default: 300)
max_function_lines: [MAX_FUNCTION_LINES]     # Lines per function (default: 50)
max_function_params: [MAX_FUNCTION_PARAMS]   # Parameters per function (default: 5)
```

---

## Testing Requirements

```yaml
# Test Coverage
require_tests: [REQUIRE_TESTS]  # true/false (default: true)
test_types:
  - unit          # Required
  - integration   # Recommended
  - e2e           # For critical flows

# Test Quality
min_assertions_per_test: 1
max_test_duration: 5000  # milliseconds per test
require_test_descriptions: true
```

---

## Code Review Standards

```yaml
# Review Requirements
require_code_review: [REQUIRE_CODE_REVIEW]  # true/false (default: true)
min_reviewers: [MIN_REVIEWERS]             # Number of required reviewers (default: 1)
require_tests_for_features: true
require_tests_for_bugfixes: true
```

---

## CI/CD Requirements

```yaml
# Build & Deploy
block_merge_on_failure: [BLOCK_MERGE_ON_FAILURE]  # true/false (default: true)
require_passing_tests: true
require_lint_pass: true
require_type_check_pass: true  # For TypeScript projects
```

---

## Security Standards

```yaml
# Security Requirements
require_security_scan: false  # Run /ss:analyze-quality before merge
block_on_critical_vulns: true
block_on_high_vulns: false
max_dependency_age: 365  # days (warn if dependency >1 year old)
```

---

## Documentation Standards

```yaml
# Documentation Requirements
require_readme_updates: false  # For new features
require_api_docs: false        # For public APIs
require_changelog_entry: true  # For all features/fixes
```

---

## Custom Quality Checks

[CUSTOM_CHECKS_SECTION]

<!-- ss:user-additions -->
<!-- Add project-specific quality checks below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->

---

## Exemptions

Projects can request exemptions for specific standards. Document exemptions here:

[EXEMPTIONS_SECTION]

<!-- ss:user-additions -->
<!-- Document accepted exemptions below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->

---

## Notes

[NOTES_SECTION]

<!-- ss:user-additions -->
<!-- Add project-specific notes below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->

---

**Quality Enforcement**: These standards are enforced by SpecSwarm commands:
- `/ss:ship` - Blocks merge if quality gates fail
- `/ss:analyze-quality` - Reports quality score against these standards
- `/ss:build` - Can enforce quality gates with `--quality-gate` flag
