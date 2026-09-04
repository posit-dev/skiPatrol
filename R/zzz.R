# Package load/attach hooks
# Following CRAN rules: no side effects on load, no Python init here

# Internal package environment for caching bridge modules, sessions, etc.
.pkg_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  # Set default options (user can override)
  op <- options()
  op_sfr <- list(
    snowflakeR.python_env = "r-snowflakeR",
    snowflakeR.verbose = FALSE,
    snowflakeR.print_width = 200L,
    snowflakeR.lowercase_columns = FALSE,
    snowflakeR.preserve_write_case = FALSE
  )
  toset <- !(names(op_sfr) %in% names(op))
  if (any(toset)) options(op_sfr[toset])

  # Declarative only -- py_require() records requirements for reticulate's
  # ephemeral-environment auto-provisioning; it does not touch Python, so
  # it doesn't violate "no Python init on load" above. Without this,
  # auto-provisioning has nothing to go on and can pick a Python newer
  # than snowflake-ml-python supports -- observed live in the Posit
  # Native App: reticulate forced Python 3.12 with no Snowflake SDK
  # installed, so sfr_connect() failed with "No module named 'snowflake'"
  # on a session that had never touched Python before. Mirrors
  # DESCRIPTION's SystemRequirements and pyproject.toml's dev environment
  # (excluding scikit-learn/shap, which are for building demo models, not
  # for the package's own runtime).
  if (requireNamespace("reticulate", quietly = TRUE) &&
      exists("py_require", envir = asNamespace("reticulate"), mode = "function")) {
    reticulate::py_require(
      packages = c(
        "snowflake-ml-python>=1.5.0",
        "snowflake-snowpark-python>=1.20",
        "snowflake-connector-python[pandas]",
        "pandas>=2.0",
        "pyarrow>=14"
      ),
      python_version = ">=3.9,<3.12"
    )
  }

  invisible()
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "snowflakeR ", utils::packageVersion("snowflakeR"),
    " - R interface to the Snowflake ML platform"
  )
}
