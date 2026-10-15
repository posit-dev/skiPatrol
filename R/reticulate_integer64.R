# Passing bit64::integer64 columns to Python
# =============================================================================
# reticulate does not know about integer64. It sees an ordinary double vector
# with a class attribute and copies the numbers across, but an integer64
# stores each 64-bit integer in the double's 8 bytes. So 7 arrives in Python
# as 3.5e-323, with no error or warning. skiLift returns integer64 only when
# asked (bigint = "integer64"), but any integer64 that reaches
# sfr_write_table(), sfr_log_model(sample_input = ), sfr_predict() and the
# other functions that send data frames to Python would be silently wrong.
#
# This registers a conversion method with reticulate, so it covers every
# r_to_py() call, including columns inside a data frame.

#' Convert an integer64 vector to a numpy array
#'
#' The bytes already are the int64 values, so they are reinterpreted rather
#' than converted: exact for every value, and fast. A vector containing `NA`
#' becomes float64 with `NaN`, which is what pandas does for whole numbers
#' that include nulls (values above 2^53 lose precision in that case only).
#' @noRd
.r_to_py_integer64 <- function(x, convert = FALSE) {
  np <- reticulate::import("numpy", convert = FALSE)
  if (anyNA(x)) {
    return(np$array(as.double(x)))
  }
  np$array(unclass(x))$view("int64")
}

#' Register the integer64 method with reticulate (called from .onLoad)
#' @noRd
.register_reticulate_integer64 <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) return(invisible())
  registerS3method(
    "r_to_py", "integer64", .r_to_py_integer64,
    envir = asNamespace("reticulate")
  )
  invisible()
}

# R data frames to pandas, safely
# =============================================================================
# Two more things go wrong when reticulate converts an R data frame:
#
# * An R integer is 32-bit, so a model signature inferred from it says INT32.
#   Snowflake's whole numbers are NUMBER(38,0), which Snowpark and the
#   `input_cols = "integer"` mapping call INT64.
# * An R integer NA is stored as -2147483648, and reticulate sends that number
#   to Python as a real value: the missing value becomes -2147483648, and a
#   table written from such a column contains it.
#
# Integer columns are therefore sent as doubles (which carry NA as NaN) and
# turned into int64, or pandas' nullable Int64 when there are NAs, which maps
# to a Snowflake NUMBER with NULLs.

#' Convert an R data frame to a pandas DataFrame
#' @noRd
.r_df_to_py <- function(df) {
  int_cols <- names(df)[vapply(df, is.integer, logical(1))]
  for (col in int_cols) {
    df[[col]] <- as.numeric(df[[col]])
  }
  py <- reticulate::r_to_py(df)
  for (col in int_cols) {
    py[[col]] <- py[[col]]$astype(if (anyNA(df[[col]])) "Int64" else "int64")
  }
  py
}
