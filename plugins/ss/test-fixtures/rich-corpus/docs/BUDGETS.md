# BUDGETS — Rich-Corpus Fixture

> Performance, accessibility, and browser-support thresholds. Used by
> SpecSwarm v7's `ss-quality-standards-extractor` subagent.

## Performance budgets

### Per-page Core Web Vitals (75th percentile, field data)

| Metric | Budget    | Page        |
|--------|-----------|-------------|
| LCP    | ≤ 2.5 s   | All pages   |
| TBT    | ≤ 200 ms  | All pages   |
| CLS    | ≤ 0.1     | All pages   |
| LCP    | ≤ 1.8 s   | `/` (home)  |
| LCP    | ≤ 2.0 s   | `/products/*` (PDP) |

### Asset budgets

- Initial JS bundle: ≤ 180 KB gzipped
- Initial CSS bundle: ≤ 30 KB gzipped
- Route-level chunk: ≤ 80 KB gzipped each
- Hero image: ≤ 100 KB, served as AVIF with WebP fallback

## Accessibility

- **WCAG 2.2 Level AA** mandatory
- **axe-core**: zero violations in CI for every PR
- **Screen reader**: VoiceOver (Safari) + NVDA (Firefox/Chrome) gating
- **Color contrast**: ≥ 4.5:1 for text < 18 pt; ≥ 3:1 for text ≥ 18 pt; ≥ 3:1 for non-text UI components
- **Focus visible**: every interactive element MUST show a visible focus indicator at all times (no `outline: none` without a replacement)
- **Touch targets**: ≥ 44 × 44 CSS pixels for primary actions on mobile; ≥ 24 × 24 acceptable for inline secondary controls
- **Reduced motion**: animations MUST respect `prefers-reduced-motion: reduce`; no parallax or auto-rotating carousels under reduced motion

## Browser support

- **Floor**: latest 2 versions of Chrome, Edge, Firefox, Safari
- iOS Safari: latest 2 versions
- **Dropped**: IE 11, Edge Legacy, Opera Mini, anything before Safari 15

## Coverage

- Unit + integration test coverage: ≥ 80% statements, ≥ 75% branches (CI gate)

## Email deliverability

- Transactional emails: 100% SPF + DKIM + DMARC alignment
- Bounce rate target: < 1% over rolling 30 days
- Open rate target (transactional): > 60%

---

_Fixture file. Not real product policy._
