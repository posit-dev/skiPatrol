# Tests for the conda r-base pinning fix (P1-03, DB-8/DB-9)
# =============================================================================
# Regression coverage for a real failure: .pin_r_versions() pinned r-base to
# the exact running R version on the stated assumption that R itself came
# from conda-forge. False in Posit Workbench (a Posit-built R, not
# conda-forge), so the pin either doesn't exist on the channel or, as
# observed, exists while a dependent package (r-ranger) has no build against
# it -- breaking sfr_deploy_model(). See internal/backlog.md DB-8/DB-8a/DB-9
# and internal/effort-estimate.md section C.

# ---------------------------------------------------------------------------
# .r_is_conda_build()
# ---------------------------------------------------------------------------

test_that(".r_is_conda_build detects conda/mamba/micromamba in R.home()", {
  expect_true(.r_is_conda_build(home = "/opt/conda/envs/workspace/lib/R", conda_prefix = ""))
  expect_true(.r_is_conda_build(home = "/home/user/micromamba/envs/foo/lib/R", conda_prefix = ""))
  expect_true(.r_is_conda_build(home = "/opt/MAMBA/lib/R", conda_prefix = ""))  # case-insensitive
})

test_that(".r_is_conda_build is FALSE for a non-conda path with no CONDA_PREFIX", {
  expect_false(.r_is_conda_build(home = "/usr/local/lib/R", conda_prefix = ""))
  expect_false(.r_is_conda_build(home = "/usr/lib/R", conda_prefix = ""))
})

test_that(".r_is_conda_build falls back to CONDA_PREFIX containment", {
  # A path that names neither conda nor mamba, but sits under CONDA_PREFIX
  expect_true(.r_is_conda_build(
    home = "/some/env/lib/R",
    conda_prefix = "/some/env"
  ))
  expect_false(.r_is_conda_build(
    home = "/usr/local/lib/R",
    conda_prefix = "/some/other/env"
  ))
})

# ---------------------------------------------------------------------------
# .pin_r_versions() -- the actual fix
# ---------------------------------------------------------------------------

test_that("a conda-build R gets an exact r-base pin", {
  local_mocked_bindings(.r_is_conda_build = function(...) TRUE, .package = "snowflakeR")

  result <- suppressMessages(.pin_r_versions(character(0), NULL))
  expected <- paste0("r-base==", R.version$major, ".", R.version$minor)
  expect_true(expected %in% result)
})

test_that("a non-conda R does not get an exact r-base pin", {
  local_mocked_bindings(.r_is_conda_build = function(...) FALSE, .package = "snowflakeR")

  result <- suppressMessages(.pin_r_versions(character(0), NULL))
  expect_false(any(grepl("^r-base==", result)))
})

test_that("a non-conda R informs, rather than silently dropping the pin", {
  local_mocked_bindings(.r_is_conda_build = function(...) FALSE, .package = "snowflakeR")

  expect_message(
    .pin_r_versions(character(0), NULL),
    "does not look like a conda build"
  )
})

test_that("a user-supplied r-base pin is never overridden, conda or not", {
  local_mocked_bindings(.r_is_conda_build = function(...) TRUE, .package = "snowflakeR")
  result_conda <- suppressMessages(.pin_r_versions(character(0), "r-base==4.5.3"))
  expect_equal(sum(grepl("^r-base", result_conda)), 1L)
  expect_true("r-base==4.5.3" %in% result_conda)

  local_mocked_bindings(.r_is_conda_build = function(...) FALSE, .package = "snowflakeR")
  result_nonconda <- suppressMessages(.pin_r_versions(character(0), "r-base==4.5.3"))
  expect_equal(sum(grepl("^r-base", result_nonconda)), 1L)
  expect_true("r-base==4.5.3" %in% result_nonconda)
})

test_that("the recent-release staleness warning only fires when r-base was actually pinned", {
  # Regression for DB-9's other half: the warning must not fire on the
  # non-conda path, where r-base is deliberately left unpinned and release
  # age is irrelevant to what the solver will pick.
  local_mocked_bindings(.r_is_conda_build = function(...) FALSE, .package = "snowflakeR")
  expect_no_warning(suppressMessages(.pin_r_versions(character(0), NULL)))
})

test_that("pin_versions = FALSE still allows explicit conda_deps through untouched", {
  local_mocked_bindings(.r_is_conda_build = function(...) FALSE, .package = "snowflakeR")
  result <- suppressMessages(.pin_r_versions(character(0), c("numpy<2.0")))
  expect_true("numpy<2.0" %in% result)
  expect_false(any(grepl("^r-base", result)))
})
