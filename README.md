# Spotter

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `spotter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:spotter, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/spotter>.

## Session-to-Commit Linking

Spotter associates Claude Code sessions with Git commits via a two-phase approach:

### Deterministic capture (hook path)

Claude Code hooks emit a minimal payload after each Bash tool use that creates commits. The `post-tool-capture.sh` script:

1. Compares `HEAD` before and after the tool execution
2. Computes `git rev-list` for new commit hashes (capped at 50)
3. POSTs `session_id`, `base_head`, `head`, and `new_commit_hashes` to `/api/hooks/commit-event`

These commits are stored as **observed_in_session** links with `confidence: 1.0`.

### Async enrichment and inference

An Oban worker enriches commit metadata (parents, author, changed files, patch-id) and computes inferred links:

| Link type | Confidence | Criteria |
|---|---|---|
| `observed_in_session` | 1.00 | Commit hash captured by hook |
| `descendant_of_observed` | 0.90 | Parent is an observed commit |
| `patch_match` | 0.85 | Stable patch-id matches an observed commit |
| `file_overlap` | 0.60 | Jaccard overlap >= 0.70, time delta <= 360 min |

Only links with `confidence >= 0.60` are persisted.

### Hook performance contract

- Target: **p95 <= 75ms** for hook script execution
- Hard budget: **<= 200ms** total script time
- cURL timeouts: `--connect-timeout 0.1`, `--max-time 0.3`
- No `git show` or `git patch-id` in hook scripts (deferred to backend)
- Silent-fail semantics: hooks never block Claude

### Known limitations

- Commits created outside Claude hooks are not deterministically observed
- Squash merges may require inference and can be low-confidence
- Git-only in V1; no GitHub/GitLab API integration

## Landing page (Astro + GitHub Pages)

### Local development

```bash
cd site
npm ci
npm run dev
```

### Production build check

```bash
cd site
npm ci
npm run build
```

### Enable deployment in GitHub

- Go to `Settings -> Pages` in `github.com/marot/spotter`
- Under **Build and deployment**, set **Source** to `GitHub Actions`
- Push to `main` to trigger `.github/workflows/deploy-pages.yml`
- Confirm published URL is `https://marot.github.io/spotter/`

### Notes

- Astro `base` is `/spotter` for project pages path handling.
- The workflow deploys only when files under `site/**` or the workflow file change.

