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
