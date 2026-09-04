# Install skiLift + skiPatrol from tarballs (preferred) or GitHub fallback.
options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"))

cran_deps <- c(
  "remotes", "httr2", "cli", "rlang", "DBI", "dplyr", "dbplyr", "tidyr",
  "jsonlite", "reticulate"
)

message("Installing CRAN dependencies...")
install.packages(cran_deps, Ncpus = 4, quiet = TRUE)

pkg_dir <- "/tmp/pkg"
tarballs <- list.files(pkg_dir, pattern = "\\.tar\\.gz$", full.names = TRUE)

install_tarball <- function(pattern) {
  hit <- tarballs[grep(pattern, basename(tarballs), ignore.case = TRUE)]
  if (length(hit) == 0) return(FALSE)
  message("Installing from tarball: ", basename(hit[1]))
  install.packages(hit[1], repos = NULL, type = "source", quiet = TRUE)
  TRUE
}

if (!install_tarball("^skiLift")) {
  message("No skiLift tarball — installing from GitHub...")
  remotes::install_github("posit-dev/skiLift", upgrade = "never", quiet = TRUE)
}

if (!install_tarball("^skiPatrol")) {
  message("No skiPatrol tarball — installing from GitHub...")
  remotes::install_github("posit-dev/skiPatrol", upgrade = "never", quiet = TRUE)
}

message("Verifying packages...")
stopifnot(
  requireNamespace("skiLift", quietly = TRUE),
  requireNamespace("skiPatrol", quietly = TRUE)
)
message("Package install OK")
