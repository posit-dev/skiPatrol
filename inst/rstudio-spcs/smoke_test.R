# Smoke test for RStudio on SPCS — skiLift + skiPatrol + reticulate
# Run: source("~/smoke_test.R")

message("=== RStudio SPCS smoke test ===")

stopifnot(
  "SPCS token or SNOWFLAKE_HOST required" =
    nzchar(Sys.getenv("SNOWFLAKE_HOST", "")) ||
    file.exists("/snowflake/session/token")
)

cat("SNOWFLAKE_HOST:", Sys.getenv("SNOWFLAKE_HOST"), "\n")
cat("SNOWFLAKE_WAREHOUSE:", Sys.getenv("SNOWFLAKE_WAREHOUSE", "<unset>"), "\n")
cat("Token file exists:", file.exists("/snowflake/session/token"), "\n")

message("\n=== skiLift ===")
library(DBI)
library(skiLift)

con <- dbConnect(Snowflake())
on.exit(try(dbDisconnect(con), silent = TRUE), add = TRUE)

who <- dbGetQuery(con, "
  SELECT
    CURRENT_USER()   AS user,
    CURRENT_ROLE()   AS role,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_VERSION() AS version
")
print(who)

sample <- head(dbGetQuery(con, "
  SELECT C_CUSTKEY, C_NAME
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
  LIMIT 3
"))
print(sample)
message("skiLift: OK")

message("\n=== skiPatrol (SPCS Snowpark) ===")
stopifnot(requireNamespace("skiPatrol", quietly = TRUE))
stopifnot(requireNamespace("reticulate", quietly = TRUE))

source("~/spcs_helpers.R")
ml <- sfr_connect_spcs()

result <- ml$session$sql(
  "SELECT CURRENT_USER() AS u, CURRENT_WAREHOUSE() AS wh"
)$collect()
print(reticulate::py_to_r(result))
message("skiPatrol: OK")

message("\n=== ALL PASS ===")
