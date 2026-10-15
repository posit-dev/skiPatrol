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

#' The bigint / time zone settings for a bridge result
#' @noRd
.bt_settings <- function(result) {
  bigint <- getOption("skiLift.bigint", "numeric")
  if (!is.character(bigint) || length(bigint) != 1L || !bigint %in% .bt_bigint_choices) {
    cli::cli_abort(c(
      "{.code options(skiLift.bigint)} must be one of {.val {(.bt_bigint_choices)}}.",
      "i" = "It is the same setting as {.arg bigint} in skiLift's {.fn dbConnect}."
    ))
  }
  setting <- getOption("skiLift.timezone_out", "database")
  tz_out <- if (identical(setting, "database")) {
    result$session_timezone %||% "UTC"
  } else if (identical(setting, "local")) {
    z <- Sys.timezone()
    if (is.na(z) || !nzchar(z)) "UTC" else z
  } else if (is.character(setting) && length(setting) == 1L && setting %in% OlsonNames()) {
    setting
  } else {
    cli::cli_abort(c(
      "{.code options(skiLift.timezone_out)} must be {.val database}, {.val local}, or a time zone name.",
      "i" = "It is the same setting as {.arg timezone_out} in skiLift's {.fn dbConnect}."
    ))
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
.bridge_typed_to_df <- function(result, lowercase = FALSE) {
  cols <- as.character(unlist(result$columns))
  n <- result$nrows
  s <- .bt_settings(result)

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
