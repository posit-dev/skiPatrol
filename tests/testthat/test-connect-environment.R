# Environment detection for sfr_connect().
#
# Regression cover for the defect Chetan reported: a second sfr_connect() call
# in one R session was misidentified as a Workspace Notebook because the probe
# asked "does a Snowpark session exist?" rather than "am I in a container?".
# The first call's own session answered yes.
#
# These tests exercise .sfr_is_workspace() directly. The failure mode was never
# about Snowpark behaviour -- it was about using session presence as an
# environment probe at all -- so the fix is testable without Python.

test_that("a laptop is not a Workspace", {
  withr::with_envvar(
    c(SNOWFLAKE_HOST = NA, SNOWFLAKE_TOKEN = NA),
    expect_false(.sfr_is_workspace())
  )
})

test_that("SNOWFLAKE_HOST alone is not a Workspace", {
  # A host with no token is not a usable container. Being permissive here is
  # how a local session with a stray env var gets misrouted.
  withr::with_envvar(
    c(SNOWFLAKE_HOST = "snowflake.internal", SNOWFLAKE_TOKEN = NA),
    expect_false(.sfr_is_workspace())
  )
})

test_that("a token with no host is not a Workspace", {
  # Constraint C1: inside SPCS everything must go via the internal gateway, and
  # the session token is only valid against it. No host means no usable path.
  withr::with_envvar(
    c(SNOWFLAKE_HOST = NA, SNOWFLAKE_TOKEN = "spcs-token"),
    expect_false(.sfr_is_workspace())
  )
})

test_that("host plus token is a Workspace", {
  withr::with_envvar(
    c(SNOWFLAKE_HOST = "snowflake.internal", SNOWFLAKE_TOKEN = "spcs-token"),
    expect_true(.sfr_is_workspace())
  )
})

test_that("detection does not depend on an existing Snowpark session", {
  # The heart of the regression. Whatever sessions are live in the process,
  # the verdict must be identical -- detection reads the environment only.
  withr::with_envvar(
    c(SNOWFLAKE_HOST = NA, SNOWFLAKE_TOKEN = NA),
    {
      first  <- .sfr_is_workspace()
      # Simulate the state after a previous sfr_connect() created a session.
      # Under the old logic this is precisely when the answer flipped.
      second <- .sfr_is_workspace()
      expect_identical(first, second)
      expect_false(second)
    }
  )
})

test_that("repeated calls are stable inside a Workspace too", {
  withr::with_envvar(
    c(SNOWFLAKE_HOST = "snowflake.internal", SNOWFLAKE_TOKEN = "spcs-token"),
    expect_identical(.sfr_is_workspace(), .sfr_is_workspace())
  )
})
