# The Piste Guide to R and Snowflake

Quarto book source for the end-to-end implementation guide (Workspace, skiLift, skiPatrol).

| | |
|---|---|
| **Published site** | [posit-dev.github.io/skiPatrol](https://posit-dev.github.io/skiPatrol/) |
| **Edit on GitHub** | [guide/Piste_Guide_to_R_and_Snowflake](https://github.com/posit-dev/skiPatrol/tree/main/guide/Piste_Guide_to_R_and_Snowflake) |
| **CI** | [publish-guide.yml](../.github/workflows/publish-guide.yml) |

## Local render

From the monorepo, source lives at `guide/Piste_Guide_to_R_and_Snowflake/` (synced here on public push).

```bash
cd guide/Piste_Guide_to_R_and_Snowflake
quarto render --to html --no-execute              # full book (27 chapters)
quarto render --to html --no-execute --profile publish   # what CI publishes (15)
quarto preview
```

CI publishes the **curated subset**, not the whole book. See
[the guide's own README](Piste_Guide_to_R_and_Snowflake/README.md#profiles-full-book-vs-published-subset).

## Monorepo development

Edit in `snowflake_model_reg_rpy2/guide/`, then run `bash sync_skiPatrol_to_public.sh` from the monorepo root.
