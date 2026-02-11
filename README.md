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

