# The Hitchhiker's Guide to R in Snowflake

Quarto book source for the end-to-end implementation guide (Workspace, skiLift, skiPatrol).

| | |
|---|---|
| **Published site** | [snowflake-labs.github.io/skiPatrol](https://snowflake-labs.github.io/skiPatrol/) |
| **Edit on GitHub** | [guide/Hitchhikers_Guide_to_R_in_Snowflake](https://github.com/posit-dev/skiPatrol/tree/main/guide/Hitchhikers_Guide_to_R_in_Snowflake) |
| **CI** | [publish-guide.yml](../.github/workflows/publish-guide.yml) |

## Local render

From the monorepo, source lives at `guide/Hitchhikers_Guide_to_R_in_Snowflake/` (synced here on public push).

```bash
cd guide/Hitchhikers_Guide_to_R_in_Snowflake
quarto render --to html --no-execute
quarto preview
```

## Monorepo development

Edit in `snowflake_model_reg_rpy2/guide/`, then run `bash sync_skiPatrol_to_public.sh` from the monorepo root.
