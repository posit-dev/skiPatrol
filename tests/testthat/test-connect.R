# Unit tests for connection module
# =============================================================================

test_that("sfr_connect requires account", {
  # Point SNOWFLAKE_HOME at an empty dir so connections.toml is not found
  withr::with_envvar(
    c(SNOWFLAKE_ACCOUNT = NA,
      SNOWFLAKE_DEFAULT_CONNECTION_NAME = NA,
      SNOWFLAKE_HOME = tempdir()),
    {
      expect_error(
        sfr_connect(
          account = NULL,
          .use_snowflakeauth = FALSE
        ),
        "account"
      )
    }
  )
})

test_that("validate_connection rejects non-connection objects", {
  expect_error(
    snowflakeR:::validate_connection("not a connection"),
    "sfr_connection"
  )
  expect_error(
    snowflakeR:::validate_connection(42),
    "sfr_connection"
  )
})

test_that("sfr_has_connection returns logical", {
  result <- sfr_has_connection(.use_snowflakeauth = FALSE)
  expect_type(result, "logical")
})

test_that("is_sfr_connection identifies connection objects", {
  fake_conn <- structure(
    list(session = NULL, account = "test"),
    class = c("sfr_connection", "list")
  )
  expect_true(snowflakeR:::is_sfr_connection(fake_conn))
  expect_false(snowflakeR:::is_sfr_connection("not a connection"))
})

# ---------------------------------------------------------------------------
# .clean_session_value() -- regression for a live failure, 4 Sep 2026
#
# A Snowpark session created via the connection_name route (P1-02) with no
# warehouse/database/schema in its connections.toml profile has nothing set
# on any of get_current_warehouse()/_database()/_schema()/_role(). Getting
# that back as a bare NA (not NULL, not "", not "None") crashed both
# $.sfr_connection and refresh_conn_from_session's old duplicate logic with
# "missing value where TRUE/FALSE needed", because NA == "" is NA, not
# FALSE. Both now share this one helper.
# ---------------------------------------------------------------------------

test_that(".clean_session_value treats NA the same as NULL/empty/None", {
  expect_null(snowflakeR:::.clean_session_value(NA))
  expect_null(snowflakeR:::.clean_session_value(NA_character_))
  expect_null(snowflakeR:::.clean_session_value(NULL))
  expect_null(snowflakeR:::.clean_session_value(""))
  expect_null(snowflakeR:::.clean_session_value("None"))
})

test_that(".clean_session_value strips quotes from a real value", {
  expect_equal(snowflakeR:::.clean_session_value('"MY_WH"'), "MY_WH")
  expect_equal(snowflakeR:::.clean_session_value("MY_WH"), "MY_WH")
})

test_that("$.sfr_connection does not error when a live getter returns NA", {
  fake_session <- list(get_current_warehouse = function() NA)
  fake_conn <- structure(
    list(session = fake_session, warehouse = "cached-value"),
    class = c("sfr_connection", "list")
  )
  expect_null(fake_conn$warehouse)
})

test_that("refresh_conn_from_session does not error on a bare session with nothing set", {
  fake_session <- list(
    get_current_warehouse = function() NA,
    get_current_database  = function() NA,
    get_current_schema    = function() NA,
    get_current_role      = function() NA
  )
  fake_conn <- structure(
    list(session = fake_session, warehouse = NULL, database = NULL,
         schema = NULL, role = NULL),
    class = c("sfr_connection", "list")
  )
  result <- snowflakeR:::refresh_conn_from_session(fake_conn)
  expect_null(result[["warehouse"]])
  expect_null(result[["database"]])
  expect_null(result[["schema"]])
  expect_null(result[["role"]])
})
