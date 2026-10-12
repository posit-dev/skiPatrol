# sfr_predict_local() ----------------------------------------------------------

test_that("the standard path predicts with a base R model", {
  model <- lm(mpg ~ wt, data = mtcars)
  out <- sfr_predict_local(model, data.frame(wt = c(2.5, 3.0)))
  expect_equal(nrow(as.data.frame(out)), 2L)
})

test_that("a predict_body template runs and returns its result", {
  model <- lm(mpg ~ wt, data = mtcars)
  body <- "result_{{UID}} <- data.frame(pred = predict({{MODEL}}, newdata = {{INPUT}}))"
  out <- sfr_predict_local(model, data.frame(wt = c(2.5, 3.0, 3.5)), predict_body = body)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 3L)
  expect_named(out, "pred")
})

test_that("a predict_body template leaves the global environment untouched", {
  model <- lm(mpg ~ wt, data = mtcars)
  body <- paste(
    "scratch_{{UID}} <- 1",
    "unsuffixed_helper_for_test <- 1",
    "result_{{UID}} <- data.frame(pred = predict({{MODEL}}, newdata = {{INPUT}}))",
    sep = "\n"
  )
  before <- ls(globalenv(), all.names = TRUE)
  sfr_predict_local(model, data.frame(wt = 3), predict_body = body)
  expect_identical(ls(globalenv(), all.names = TRUE), before)
})

test_that("a failing predict_body template also leaves the global environment untouched", {
  model <- lm(mpg ~ wt, data = mtcars)
  before <- ls(globalenv(), all.names = TRUE)
  expect_error(
    sfr_predict_local(model, data.frame(wt = 3), predict_body = "stop('boom')"),
    "boom"
  )
  expect_identical(ls(globalenv(), all.names = TRUE), before)
})
