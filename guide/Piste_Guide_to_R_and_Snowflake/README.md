# The Piste Guide to R and Snowflake

Quarto book source. Published at [posit-dev.github.io/skiPatrol](https://posit-dev.github.io/skiPatrol/) via [posit-dev/skiPatrol](https://github.com/posit-dev/skiPatrol) (`guide/` on `main`). Develop in the monorepo under `guide/Piste_Guide_to_R_and_Snowflake/`.

## Local build

```bash
# Install Quarto: https://quarto.org/docs/get-started/
cd guide/Piste_Guide_to_R_and_Snowflake
quarto render --to html --no-execute   # fast — uses _freeze/ when present
quarto preview                          # live reload
```

Both build the **full** book — `profile.default` in `_quarto.yml` is `full`.

To re-execute cells that call Snowflake, set `SNOWFLAKE_DEFAULT_CONNECTION_NAME` and render without `--no-execute`, then commit updated `_freeze/` directories.

## Profiles: full book vs published subset

The chapter lists live in the **profiles**, not in `_quarto.yml`. Quarto
*concatenates* arrays when merging a profile over the base config and dedups
only byte-identical entries (verify with `quarto inspect --profile publish`), so
a profile can never *replace* `book.chapters`. With the base config carrying no
chapter list at all there is nothing to concatenate, and each profile supplies
its own complete list.

```bash
quarto render                      # full book (27 chapters) — the default
quarto render --profile publish    # curated subset (15 chapters)
```

`--profile publish` is what CI publishes. It also sets `project.render`, which
matters: restricting `book.chapters` alone still lets Quarto render every other
`.qmd` in the directory as an orphan page reachable by direct URL. `project.render`
is what actually keeps the held-back chapters out of `_site`.

**Editing a chapter list means editing two files.** Keep `_quarto-full.yml`,
`_quarto-publish.yml` and the latter's `held-chapters:` key in step.

`scripts/unlink_held_chapters.lua` runs only under the publish profile. Around
50 links in the published chapters point *into* held-back ones; the filter keeps
the link text, drops the anchor and appends a dagger, so the subset has no 404s.
It reads `held-chapters:` so the profile stays the single source of truth.

## Structure

- `_quarto.yml` — theme, format, shared book metadata (no chapter list)
- `_quarto-full.yml` — full chapter list (default profile)
- `_quarto-publish.yml` — curated subset, render exclusions, `held-chapters`
- `NN_topic/index.qmd` — one chapter per folder
- `appendices/` — reference material
- `_theme/` — Snowflake-branded SCSS (shared pattern with Feature Store guide)
- `scripts/unlink_held_chapters.lua` — publish-profile link filter

## Authoring

See [../GUIDE_DESIGN_AND_PLAN.md](../GUIDE_DESIGN_AND_PLAN.md) and [../_internal_development/](../_internal_development/) for migration notes and publishing workflow.
