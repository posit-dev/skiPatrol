# Typed results from the Python bridge
# =============================================================================
# The bridge used to turn a query result into plain Python lists, losing
# Snowflake's column types, and R then guessed each column's type from its
# values. That turned digit-only text into numbers ('01234' became 1234),
# left dates as text, and made a column's type depend on whether it held a NULL.
#
# Bridge functions now send, for each column, Snowflake's type with its scale
# and precision (`kinds`), and the values as text in the same formats as the
# Snowflake SQL API: epoch days for DATE, seconds for TIME, epoch seconds for
# timestamps, "true"/"false" for BOOLEAN. This file turns that back into R
# types with the same rules as the skiLift package (R/type-map.R there), so
# a query returns the same classes whichever way it reached Snowflake.
# tests/testthat/test-bridge-types.R compares the two when skiLift is
# installed.
#
# Whole numbers: scale 0 and up to 9 digits is `integer`; larger ones follow
# the `skiLift.bigint` option ("numeric" by default, as in skiLift). Time
# zones: `skiLift.timezone_out` ("database" by default, the session's zone).

.bt_bigint_choices <- c("numeric", "integer64", "integer", "character")

#' A setting stored on a connection, or on an object that holds one
#'
#' `x` is a connection, or a feature store or model registry, which carry
#' theirs in `$conn`. `NULL` if there is none.
#' @noRd
.conn_setting <- function(x, name) {
  if (is.null(x)) return(NULL)
  .subset2(x, name) %||% .subset2(.subset2(x, "conn") %||% list(), name)
}

#' Check a `bigint` value; the same choices as skiLift's `dbConnect()`
#' @noRd
.check_bigint <- function(x, what = "bigint") {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% .bt_bigint_choices) {
    cli::cli_abort(c(
      "{.arg {what}} must be one of {.val {(.bt_bigint_choices)}}.",
      "i" = "It is the same setting as {.arg bigint} in skiLift's {.fn dbConnect}."
    ))
  }
  x
}

#' Check a `timezone_out` value; the same choices as skiLift's `dbConnect()`
#' @noRd
.check_timezone_out <- function(x, what = "timezone_out") {
  ok <- is.character(x) && length(x) == 1L && !is.na(x) &&
    (x %in% c("database", "local") || x %in% OlsonNames())
  if (!ok) {
    cli::cli_abort(c(
      "{.arg {what}} must be {.val database}, {.val local}, or a time zone name.",
      "i" = "It is the same setting as {.arg timezone_out} in skiLift's {.fn dbConnect}."
    ))
  }
  x
}

#' The bigint / time zone settings for a bridge result
#'
#' In order: the connection's `bigint` / `timezone_out` (from `sfr_connect()`),
#' then `options(skiLift.bigint)` / `options(skiLift.timezone_out)`, then the
#' defaults ("numeric", and the Snowflake session's zone).
#' @noRd
.bt_settings <- function(result, conn = NULL) {
  bigint <- .conn_setting(conn, "bigint")
  bigint <- if (is.null(bigint)) {
    .check_bigint(getOption("skiLift.bigint", "numeric"), "options(skiLift.bigint)")
  } else {
    .check_bigint(bigint)
  }

  setting <- .conn_setting(conn, "timezone_out")
  setting <- if (is.null(setting)) {
    .check_timezone_out(getOption("skiLift.timezone_out", "database"), "options(skiLift.timezone_out)")
  } else {
    .check_timezone_out(setting)
  }
  tz_out <- if (identical(setting, "database")) {
    result$session_timezone %||% "UTC"
  } else if (identical(setting, "local")) {
    z <- Sys.timezone()
    if (is.na(z) || !nzchar(z)) "UTC" else z
  } else {
    setting
  }
  list(bigint = bigint, tz_out = tz_out)
}

#' Convert one column of text values to its R type
#'
#' @param x Character vector, `NA` for NULL.
#' @param type Snowflake type name in lower case (`"fixed"`, `"text"`, ...).
#' @noRd
.bt_convert_column <- function(x, type, scale = 0L, precision = NA_integer_,
                               bigint = "numeric", tz_out = "UTC") {
  switch(type,
    "fixed" = .bt_fixed(x, scale, precision, bigint),
    "real" = , "float" = as.double(x),
    "boolean" = .bt_boolean(x),
    "date" = .bt_date(x),
    "time" = .bt_time(x),
    "timestamp_ntz" = , "timestamp" = .bt_timestamp(x, tz = "UTC"),
    "timestamp_ltz" = .bt_timestamp(x, tz = tz_out),
    "timestamp_tz" = .bt_timestamp(sub(" .*$", "", x), tz = tz_out),
    x
  )
}

.bt_fixed <- function(x, scale, precision, bigint) {
  if (is.na(scale) || scale != 0L) return(as.double(x))
  if (!is.na(precision) && precision > 0L && precision <= 9L) return(as.integer(x))
  switch(bigint,
    "integer64" = {
      rlang::check_installed("bit64", reason = 'to return whole numbers as integer64.')
      .bt_whole(x, bit64::as.integer64, "integer64")
    },
    "integer" = .bt_whole(x, as.integer, "integer"),
    "character" = x,
    as.double(x)
  )
}

.bt_whole <- function(x, convert, what) {
  out <- suppressWarnings(convert(x))
  lost <- is.na(out) & !is.na(x)
  if (any(lost)) {
    cli::cli_warn(c(
      "{sum(lost)} whole-number value{?s} did not fit {what} and {?was/were} returned as {.code NA}.",
      "i" = 'Use {.code options(skiLift.bigint = "numeric")} or {.code "character"} to keep them.'
    ))
  }
  out
}

.bt_boolean <- function(x) {
  lookup <- c("true" = TRUE, "false" = FALSE, "1" = TRUE, "0" = FALSE)
  unname(lookup[x])
}

.bt_date <- function(x) as.Date(suppressWarnings(as.numeric(x)), origin = "1970-01-01")

.bt_time <- function(x) {
  secs <- suppressWarnings(as.numeric(x))
  if (requireNamespace("hms", quietly = TRUE)) hms::as_hms(secs) else secs
}

.bt_timestamp <- function(x, tz = "UTC") {
  as.POSIXct(suppressWarnings(as.numeric(x)), origin = "1970-01-01", tz = tz)
}

#' Turn a typed bridge result into a data frame
#'
#' `result` has `columns`, `data` (column name -> values as text, with the
#' string "NA_SENTINEL_" for NULL), `nrows`, `kinds` (one list per column,
#' in order: `type`, `scale`, `precision`) and, when there is an LTZ/TZ
#' column, `session_timezone`.
#' @noRd
.bridge_typed_to_df <- function(result, lowercase = FALSE, conn = NULL) {
  cols <- as.character(unlist(result$columns))
  n <- result$nrows
  s <- .bt_settings(result, conn)

  # A result that went through a JSON file comes back with `kinds` simplified
  # to a data frame; make it a list of lists again.
  kinds <- result$kinds
  if (is.data.frame(kinds)) {
    kinds <- lapply(seq_len(nrow(kinds)), function(i) as.list(kinds[i, , drop = FALSE]))
  }

  out <- vector("list", length(cols))
  for (i in seq_along(cols)) {
    k <- kinds[[i]]
    x <- if (n == 0L) {
      character(0)
    } else {
      as.character(unlist(result$data[[cols[i]]], use.names = FALSE))
    }
    x[x %in% "NA_SENTINEL_"] <- NA_character_
    out[[i]] <- .bt_convert_column(
      x, k$type, k$scale %||% 0L, k$precision %||% NA_integer_, s$bigint, s$tz_out
    )
  }
  names(out) <- if (lowercase) tolower(cols) else cols
  as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
}
