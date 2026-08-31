# Create a Mock OMOP CDM Reference for Testing and Demonstrations

Create a Mock OMOP CDM Reference for Testing and Demonstrations

## Usage

``` r
mockOmopHeor(numberIndividuals = 10)

mockHERMES(numberIndividuals = 10)
```

## Arguments

- numberIndividuals:

  Number of synthetic individuals to create. Default: 10.

## Value

A `cdm_reference` object connected to an in-memory DuckDB database.

## Examples

``` r
# \donttest{
library(omopHeor)
cdm <- mockOmopHeor()
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp6vFzql/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> ! cdm name not specified and could not be inferred from the cdm source table
# }
```
