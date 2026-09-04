# Tests for connections.toml OAuth profiles (P1-02, changes 4 + 7)
# =============================================================================
# Covers the diagnosed Native App defect: sfr_connect() never extracted a
# `token` from a connections.toml profile with authenticator = "oauth"
# (Posit Workbench / the Native App write exactly this shape), and
# create_session() had no parameter to receive one. See
# internal/posit_native_app_support/native-app-probe-findings.md and
# internal/posit_native_app_support/p1-02-design-review.md.
#
# The fix routes such profiles through the Python connector's own
# `connection_name` resolution rather than extracting the token into R --
# so these tests assert the token never reaches R at all, not just that
# the connection succeeds.

.write_oauth_profile <- function(name = "workbench", token = "wb-token-123",
                                  account = "wbacct") {
  tmp_dir <- tempfile()
  dir.create(tmp_dir, showWarnings = FALSE)
  writeLines(c(
    sprintf("[%s]", name),
    sprintf('account = "%s"', account),
    'authenticator = "oauth"',
    sprintf('token = "%s"', token)
  ), file.path(tmp_dir, "connections.toml"))
  tmp_dir
}

.fake_session <- function(account = "wbacct", warehouse = "WH",
                           database = "DB", schema = "SC", role = "ROLE") {
  list(
    get_current_account   = function() paste0('"', account, '"'),
    get_current_warehouse = function() paste0('"', warehouse, '"'),
    get_current_database  = function() paste0('"', database, '"'),
    get_current_schema    = function() paste0('"', schema, '"'),
    get_current_role      = function() paste0('"', role, '"')
  )
}

# ---------------------------------------------------------------------------
# .read_connections_toml() reports its source
# ---------------------------------------------------------------------------

test_that(".read_connections_toml attaches toml_file and toml_name", {
  tmp_dir <- .write_oauth_profile()
  withr::with_envvar(c(SNOWFLAKE_HOME = tmp_dir), {
    profile <- skiPatrol:::.read_connections_toml("workbench")
    expect_equal(profile$token, "wb-token-123")
    expect_equal(attr(profile, "toml_name"), "workbench")
    expect_equal(attr(profile, "toml_file"), file.path(tmp_dir, "connections.toml"))
  })
  unlink(tmp_dir, recursive = TRUE)
})

# ---------------------------------------------------------------------------
# .resolve_oauth_connection_name() -- shape detection
# ---------------------------------------------------------------------------

test_that(".resolve_oauth_connection_name detects an oauth-with-token profile", {
  tmp_dir <- .write_oauth_profile(name = "workbench")
  withr::with_envvar(c(SNOWFLAKE_HOME = tmp_dir), {
    expect_equal(skiPatrol:::.resolve_oauth_connection_name("workbench"), "workbench")
  })
  unlink(tmp_dir, recursive = TRUE)
})

test_that(".resolve_oauth_connection_name returns NULL without authenticator=oauth", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir, showWarnings = FALSE)
  writeLines(c("[keypair]", 'account = "a"', 'private_key_path = "/k.p8"'),
             file.path(tmp_dir, "connections.toml"))
  withr::with_envvar(c(SNOWFLAKE_HOME = tmp_dir), {
    expect_null(skiPatrol:::.resolve_oauth_connection_name("keypair"))
  })
  unlink(tmp_dir, recursive = TRUE)
})

test_that(".resolve_oauth_connection_name returns NULL when there is no toml", {
  withr::with_envvar(c(SNOWFLAKE_HOME = tempfile()), {
    expect_null(skiPatrol:::.resolve_oauth_connection_name(NULL))
  })
})

# ---------------------------------------------------------------------------
# sfr_connect() -- routes a Workbench-shaped profile through connection_name
# ---------------------------------------------------------------------------

test_that("sfr_connect routes an oauth profile through connection_name, not extraction", {
  tmp_dir <- .write_oauth_profile(name = "workbench", token = "wb-token-123")
  captured <- NULL

  local_mocked_bindings(
    get_bridge_module = function(module_name) {
      list(
        get_active_session = function() NULL,
        create_session = function(...) {
          captured <<- list(...)
          .fake_session(account = "wbacct")
        }
      )
    },
    .package = "skiPatrol"
  )

  withr::with_envvar(c(SNOWFLAKE_HOME = tmp_dir, SNOWFLAKE_ACCOUNT = NA,
                        SNOWFLAKE_DEFAULT_CONNECTION_NAME = NA), {
    conn <- sfr_connect(name = "workbench", .use_snowflakeauth = FALSE)
    expect_equal(conn$auth_method, "oauth")
    expect_equal(conn$account, "wbacct")
    expect_equal(conn$environment, "local")
  })

  # The token itself must never reach R: create_session() was called by
  # name, with no account and no token in the arguments.
  expect_equal(captured$connection_name, "workbench")
  expect_null(captured$account)
  expect_false("token" %in% names(captured))

  unlink(tmp_dir, recursive = TRUE)
})

test_that("an explicit account bypasses the oauth-profile route", {
  tmp_dir <- .write_oauth_profile(name = "workbench", token = "wb-token-123")
  captured <- NULL

  local_mocked_bindings(
    get_bridge_module = function(module_name) {
      list(
        get_active_session = function() NULL,
        create_session = function(...) {
          captured <<- list(...)
          .fake_session(account = "explicit-acct")
        }
      )
    },
    .package = "skiPatrol"
  )

  withr::with_envvar(c(SNOWFLAKE_HOME = tmp_dir, SNOWFLAKE_ACCOUNT = NA,
                        SNOWFLAKE_DEFAULT_CONNECTION_NAME = NA), {
    conn <- sfr_connect(name = "workbench", account = "explicit-acct",
                        user = "u", authenticator = "snowflake",
                        .use_snowflakeauth = FALSE)
    expect_equal(conn$account, "explicit-acct")
  })

  # Reached Strategy 2 (direct toml read), not the connection_name route.
  expect_null(captured$connection_name)
  expect_equal(captured$account, "explicit-acct")

  unlink(tmp_dir, recursive = TRUE)
})

test_that("an explicit authenticator bypasses the oauth-profile route", {
  tmp_dir <- .write_oauth_profile(name = "workbench", token = "wb-token-123")
  captured <- NULL

  local_mocked_bindings(
    get_bridge_module = function(module_name) {
      list(
        get_active_session = function() NULL,
        create_session = function(...) {
          captured <<- list(...)
          .fake_session(account = "wbacct")
        }
      )
    },
    .package = "skiPatrol"
  )

  withr::with_envvar(c(SNOWFLAKE_HOME = tmp_dir, SNOWFLAKE_ACCOUNT = NA,
                        SNOWFLAKE_DEFAULT_CONNECTION_NAME = NA), {
    sfr_connect(name = "workbench", authenticator = "externalbrowser",
                user = "u", .use_snowflakeauth = FALSE)
  })

  expect_null(captured$connection_name)
  expect_equal(captured$authenticator, "externalbrowser")

  unlink(tmp_dir, recursive = TRUE)
})

# ---------------------------------------------------------------------------
# sfr_connect(session = ) -- explicit external Snowpark session (change 7)
# ---------------------------------------------------------------------------

test_that("sfr_connect(session = ) wraps the given session directly", {
  fake <- .fake_session(account = "ext-acct", warehouse = "EXT_WH")

  bridge_touched <- FALSE
  local_mocked_bindings(
    get_bridge_module = function(module_name) {
      bridge_touched <<- TRUE
      list(get_active_session = function() stop("should not be called"))
    },
    .package = "skiPatrol"
  )

  conn <- sfr_connect(session = fake)

  expect_equal(conn$environment, "external")
  expect_equal(conn$auth_method, "external_session")
  expect_identical(conn$session, fake)
  expect_equal(conn$warehouse, "EXT_WH")
  # Auto-detect and every toml/snowflakeauth strategy must be skipped
  # entirely -- this is the whole point of the explicit parameter.
  expect_false(bridge_touched)
})
