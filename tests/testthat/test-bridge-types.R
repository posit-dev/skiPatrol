# Typed results from the Python bridge -----------------------------------------
# The bridge sends each column's Snowflake type and the values as text in the
# SQL API's formats. These checks use payloads of that shape.

.kind <- function(type, scale = 0L, precision = 0L) list(type = type, scale = scale, precision = precision)

.typed <- function(columns, kinds, data, nrows = length(data[[1]]), ...) {
  list(columns = as.list(columns), kinds = kinds, data = data, nrows = nrows, ...)
}

test_that("digit-only text stays text, with its leading zeros", {
  res <- .typed("ZIP", list(.kind("text")), list(ZIP = c("01234", "90210", "NA_SENTINEL_")))
  df <- .bridge_dict_to_df(res)
  expect_type(df$ZIP, "character")
  expect_equal(df$ZIP, c("01234", "90210", NA))
})

test_that("a number column with NULLs stays a number column", {
  res <- .typed("N", list(.kind("fixed", 0L, 38L)), list(N = c("7", "NA_SENTINEL_", "2147483648")))
  df <- .bridge_dict_to_df(res)
  expect_type(df$N, "double")
  expect_equal(df$N, c(7, NA, 2147483648))
})

test_that("dates and timestamps come back as dates and timestamps, not text", {
  res <- .typed(c("D", "T", "NTZ", "TZ"),
    list(.kind("date"), .kind("time", 9L), .kind("timestamp_ntz", 9L), .kind("timestamp_tz", 9L)),
    list(D = "20740", T = "45296.500000000", NTZ = "1791961496.000000000", TZ = "1791961496.000000000 1770"),
    session_timezone = "America/Los_Angeles")
  df <- .bridge_dict_to_df(res)
  expect_s3_class(df$D, "Date")
  expect_equal(format(df$D), "2026-10-14")
  expect_equal(as.numeric(df$T), 45296.5)
  expect_s3_class(df$NTZ, "POSIXct")
  expect_equal(attr(df$NTZ, "tzone"), "UTC")
  expect_equal(attr(df$TZ, "tzone"), "America/Los_Angeles")   # the session zone, as in skiLift
  expect_equal(format(df$TZ, tz = "UTC", "%H:%M:%S"), "07:04:56")
})

test_that("precision decides integer versus double, as in skiLift", {
  res <- .typed(c("A", "B", "C"),
    list(.kind("fixed", 0L, 9L), .kind("fixed", 0L, 38L), .kind("fixed", 2L, 10L)),
    list(A = "7", B = "7", C = "1.50"))
  df <- .bridge_dict_to_df(res)
  expect_type(df$A, "integer")
  expect_type(df$B, "double")
  expect_type(df$C, "double")
})

test_that("skiLift.bigint and skiLift.timezone_out are honoured", {
  res <- .typed(c("B", "L"), list(.kind("fixed", 0L, 38L), .kind("timestamp_ltz", 9L)),
                list(B = "9007199254740993", L = "1792006496.000000000"),
                session_timezone = "America/Los_Angeles")
  withr::local_options(skiLift.bigint = "character", skiLift.timezone_out = "UTC")
  df <- .bridge_dict_to_df(res)
  expect_identical(df$B, "9007199254740993")
  expect_equal(attr(df$L, "tzone"), "UTC")
  withr::local_options(skiLift.bigint = "nope")
  expect_error(.bridge_dict_to_df(res), "skiLift.bigint")
})

test_that("zero-row results are typed", {
  res <- list(columns = list("A", "D"), nrows = 0L, data = list(A = list(), D = list()),
              kinds = list(.kind("text"), .kind("date")))
  df <- .bridge_dict_to_df(res)
  expect_equal(nrow(df), 0L)
  expect_type(df$A, "character")
  expect_s3_class(df$D, "Date")
})

test_that("lowercase names are applied to typed results", {
  res <- .typed("MY_COL", list(.kind("text")), list(MY_COL = "a"))
  expect_named(.bridge_dict_to_df(res, lowercase = TRUE), "my_col")
})

test_that("results without types still use the old conversion", {
  res <- list(columns = c("N", "S"), nrows = 2L, data = list(N = c(1L, 2L), S = c("a", "b")))
  df <- .bridge_dict_to_df(res)
  expect_equal(df$N, c(1L, 2L))
  expect_equal(df$S, c("a", "b"))
})

test_that("the bridge converter gives the same classes and values as skiLift", {
  skip_if_not_installed("skiLift")
  # Older skiLift releases chose types by value and have no tz_out argument.
  skip_if_not("tz_out" %in% names(formals(skiLift:::sf_convert_column)),
              "installed skiLift predates the shared type rules")
  fixtures <- list(
    list("fixed", 0L, 9L,  c("1", NA, "42")),
    list("fixed", 0L, 38L, c("7", "2147483648", NA)),
    list("fixed", 2L, 10L, c("1.50", "-2.25", NA)),
    list("real",  0L, 0L,  c("3.5", "-1e-3", NA)),
    list("text",  0L, 0L,  c("01234", "a b", NA)),
    list("boolean", 0L, 0L, c("true", "false", NA)),
    list("date", 0L, 0L, c("20740", "-25567", NA)),
    list("time", 9L, 0L, c("45296.500000000", "0.000000000", NA)),
    list("timestamp_ntz", 9L, 0L, c("1791961496.000000000", NA)),
    list("timestamp_ltz", 9L, 0L, c("1792006496.123456000", NA)),
    list("timestamp_tz", 9L, 0L, c("1791961496.000000000 1770", NA)),
    list("variant", 0L, 0L, c("{}", NA))
  )
  for (f in fixtures) {
    mine   <- .bt_convert_column(f[[4]], f[[1]], f[[2]], f[[3]], "numeric", "America/Los_Angeles")
    theirs <- skiLift:::sf_convert_column(f[[4]], f[[1]], f[[2]], f[[3]], "numeric", "America/Los_Angeles")
    expect_equal(mine, theirs, info = f[[1]])
    expect_identical(class(mine), class(theirs), info = f[[1]])
  }
})

test_that("a typed result that went through a JSON file still converts", {
  res <- .typed(c("ZIP", "N"), list(.kind("text"), .kind("fixed", 0L, 9L)),
                list(ZIP = c("01234", "NA_SENTINEL_"), N = c("7", "8")))
  back <- jsonlite::fromJSON(jsonlite::toJSON(res, auto_unbox = TRUE))
  df <- .bridge_dict_to_df(back)
  expect_equal(df$ZIP, c("01234", NA))
  expect_type(df$N, "integer")
})
