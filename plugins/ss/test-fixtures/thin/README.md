# Acme Thin Fixture

Minimal-corpus fixture for SpecSwarm v7 backward-compat tests. Used to verify
that `/ss:init` on a project with no `docs/`, no memory dir, and no prior
`.specswarm/` history behaves substantively identically to v6.4.0.

Has just this README and a `package.json`. No spec content. No decisions.
No principles. The expected `/ss:init` outcome is: discovery finds 0
spec-docs and 0 memory files; extractors are not dispatched; foundation files
are generated from auto-detect + interactive defaults only.
