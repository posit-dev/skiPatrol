# Shared configuration for the skiPatrol Quarto examples.
# Source this at the top of each .qmd in this directory.
#
# The point of this file is that the same .qmd runs unmodified in a local R
# session, the Posit Native App, and a Snowflake Workspace Notebook. Set the
# environment variables below where your environment needs something specific;
# leave them unset everywhere else. Modelled on the credit-risk demo's
# _config.R, which was validated end-to-end in all three environments.

# -- Connection profile ------------------------------------------------------
# Leave unset to let sfr_connect() auto-detect: a single connections.toml
# profile, a Native App OAuth profile, or a Workspace Notebook session, in that
# priority order. Set it only if you have several local profiles and need to
# pick one.
SFR_CONNECTION_NAME <- Sys.getenv("SFR_CONNECTION_NAME", NA)
if (is.na(SFR_CONNECTION_NAME) || !nzchar(SFR_CONNECTION_NAME)) {
  SFR_CONNECTION_NAME <- NULL
}

# -- Warehouse ---------------------------------------------------------------
# Account-specific, so there is no sensible default. "" -- not NULL -- falls
# back to the profile's or session's own default warehouse: sfr_connect()
# defaults this argument to "" and checks it with nzchar(), so NULL is not
# equivalent.
SFR_WAREHOUSE <- Sys.getenv("SFR_WAREHOUSE", "")

# -- Where the examples create their objects ---------------------------------
# These examples write a small number of demo tables. Point them at a database
# and schema you are happy to create and drop tables in.
SFR_DATABASE <- Sys.getenv("SFR_DATABASE", "SKIPATROL_EXAMPLES")
SFR_SCHEMA   <- Sys.getenv("SFR_SCHEMA", "PUBLIC")
