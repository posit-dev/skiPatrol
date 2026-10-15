# bit64::integer64 across the reticulate boundary ------------------------------
# Without the method skiPatrol registers, reticulate reads each int64's bytes
# as a double: 7 arrives in Python as 3.5e-323, silently.

skip_if_no_numpy <- function() {
  skip_if_not_installed("reticulate")
  skip_if_not_installed("bit64")
  skip_if_not(reticulate::py_module_available("numpy"), "numpy not available")
}

test_that("integer64 values reach Python exactly", {
  skip_if_no_numpy()
  x <- bit64::as.integer64(c("7", "2147483648", "9007199254740993", "-9223372036854775807"))
  py <- reticulate::r_to_py(x)
  expect_equal(as.character(reticulate::py_to_r(py$dtype)), "int64")
  # compare as text via Python so R's own double rounding cannot hide an error
  txt <- reticulate::py_eval("lambda a: [str(int(v)) for v in a]", convert = TRUE)(py)
  expect_equal(unlist(txt), c("7", "2147483648", "9007199254740993", "-9223372036854775807"))
})

test_that("integer64 columns inside a data frame are converted too", {
  skip_if_no_numpy()
  df <- data.frame(id = bit64::as.integer64(c("7", "9007199254740993")), n = 1:2)
  py <- reticulate::r_to_py(df)
  expect_equal(as.character(reticulate::py_to_r(py$dtypes$id)), "int64")
  txt <- reticulate::py_eval("lambda s: [str(int(v)) for v in s]", convert = TRUE)(py$id)
  expect_equal(unlist(txt), c("7", "9007199254740993"))
})

test_that("integer64 with missing values becomes float64 with NaN, as in pandas", {
  skip_if_no_numpy()
  py <- reticulate::r_to_py(bit64::as.integer64(c("7", NA, "9")))
  expect_equal(as.character(reticulate::py_to_r(py$dtype)), "float64")
  back <- unlist(reticulate::py_to_r(py$tolist()))
  expect_equal(is.na(back), c(FALSE, TRUE, FALSE))
  expect_equal(back[!is.na(back)], c(7, 9))
})

test_that("an empty integer64 vector converts", {
  skip_if_no_numpy()
  py <- reticulate::r_to_py(bit64::as.integer64(integer(0)))
  expect_equal(length(reticulate::py_to_r(py$tolist())), 0L)
})
