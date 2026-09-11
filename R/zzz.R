# Package load/attach hooks
# Following CRAN rules: no side effects on load, no Python init here

# Internal package environment for caching bridge modules, sessions, etc.
.pkg_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  # Set default options (user can override)
  op <- options()
  op_sfr <- list(
    skiPatrol.python_env = "r-skiPatrol",
    skiPatrol.verbose = FALSE,
    skiPatrol.print_width = 200L,
    skiPatrol.lowercase_columns = FALSE,
    skiPatrol.preserve_write_case = FALSE
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
        # Upper bound is deliberate and load-bearing, not caution. uv resolves
        # the newest match, but a model logged here is *served* from a conda
        # environment built off Snowflake's channel, and the SDK pins its own
        # installed version into that environment. Snowflake's channel lags
        # PyPI, so a release that is days old can be unresolvable server-side:
        # on 11 Sep an unbounded spec resolved to 2.0.0 (published 10 Sep) and
        # deployment died in the container build with
        # "snowflake-ml-python ==2.0.0 does not exist".
        #
        # <2 is the right ceiling, and the 1.x line is proven rather than
        # assumed: every model version logged in this account on 7 Sep records
        # client "snowflake-ml-python 1.54.0" and deployed to SPCS
        # successfully. Do NOT tighten this on the basis of
        # repo.anaconda.com/pkgs/snowflake/linux-64 -- that public mirror
        # listed nothing above 1.51.0 on 11 Sep and so does not reflect what
        # SPCS image builds actually resolve. Checking it led to exactly that
        # wrong conclusion once already.
        #
        # Moving to 2.x needs the server side to have caught up; see backlog
        # DB-20 for the systematic version/channel pre-flight.
        "snowflake-ml-python>=1.5.0,<2",
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
    "skiPatrol ", utils::packageVersion("skiPatrol"),
    " - R interface to the Snowflake ML platform"
  )
}
