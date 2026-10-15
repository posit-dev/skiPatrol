# R data frames to pandas ------------------------------------------------------
# reticulate sends an R integer NA to Python as -2147483648, and an R integer
# column is 32-bit, so model signatures inferred from it say INT32.

skip_if_no_pandas <- function() {
  skip_if_not_installed("reticulate")
  skip_if_not(reticulate::py_module_available("pandas"), "pandas not available")
}

.py_values <- function(py, col) {
  helper <- reticulate::py_run_string("
import pandas as pd
def column_values(series):
    return [None if pd.isna(v) else int(v) for v in series.tolist()]
", convert = TRUE)
  helper$column_values(py[[col]])
}

test_that("integer columns are sent as int64", {
  skip_if_no_pandas()
  py <- .r_df_to_py(data.frame(a = 1:3, b = c(1.5, 2.5, 3.5), c = c("x", "y", "z")))
  expect_equal(as.character(reticulate::py_to_r(py$dtypes$a)), "int64")
  expect_equal(as.character(reticulate::py_to_r(py$dtypes$b)), "float64")
  expect_equal(unlist(.py_values(py, "a")), 1:3)
})

test_that("an integer NA becomes a missing value, not -2147483648", {
  skip_if_no_pandas()
  py <- .r_df_to_py(data.frame(a = c(1L, NA, 3L)))
  expect_equal(as.character(reticulate::py_to_r(py$dtypes$a)), "Int64")
  vals <- .py_values(py, "a")
  expect_null(vals[[2]])
  expect_false(any(unlist(vals) == -2147483648))
  expect_equal(unlist(vals), c(1L, 3L))
})

test_that("the data frame is not changed", {
  skip_if_no_pandas()
  df <- data.frame(a = c(1L, NA, 3L))
  .r_df_to_py(df)
  expect_true(is.integer(df$a))
})

test_that("the SDK infers INT64, not INT32, from an R integer column", {
  skip_if_no_pandas()
  skip_if_not(reticulate::py_module_available("snowflake.ml.model.model_signature"), "snowflake-ml-python not available")
  infer <- reticulate::py_run_string("
from snowflake.ml.model import model_signature as ms
def sig_types(pdf):
    return {f.name: str(f._dtype) for f in ms._infer_signature(pdf, role='input')}
", convert = TRUE)
  df <- data.frame(a = 1:3, b = c(1.5, 2.5, 3.5))
  before <- unlist(infer$sig_types(reticulate::r_to_py(df)))
  after  <- unlist(infer$sig_types(.r_df_to_py(df)))
  expect_equal(before[["a"]], "DataType.INT32")
  expect_equal(after[["a"]], "DataType.INT64")
  expect_equal(after[["b"]], "DataType.DOUBLE")
})
