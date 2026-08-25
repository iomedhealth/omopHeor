# Utilities for validation, windowing, and in-database lifecycle

#' Validate window argument
#'
#' @param window A list of numeric vectors of length 2.
#' @param call Environment for error reporting.
#'
#' @return A named list of 2-element numeric vectors.
#' @noRd
validateWindow <- function(window, call = parent.frame()) {
  if (!is.list(window)) {
    if (is.numeric(window) && length(window) == 2) {
      window <- list(window)
    } else {
      cli::cli_abort("Argument 'window' must be a list of 2-element numeric vectors.", call = call)
    }
  }

  if (length(window) == 0) {
    cli::cli_abort("Argument 'window' cannot be empty.", call = call)
  }

  cleanWindow <- list()
  nms <- names(window)

  for (i in seq_along(window)) {
    w <- window[[i]]
    if (!is.numeric(w) || length(w) != 2) {
      cli::cli_abort("Each window element must be a numeric vector of length 2.", call = call)
    }
    if (is.na(w[1])) {
      w[1] <- -Inf
    }
    if (is.na(w[2])) {
      w[2] <- Inf
    }
    if (w[1] > w[2]) {
      cli::cli_abort(glue::glue("Window interval [{w[1]}, {w[2]}] is invalid: start cannot exceed end."), call = call)
    }

    wName <- if (!is.null(nms) && nms[i] != "") {
      tolower(nms[i])
    } else {
      sStr <- if (is.infinite(w[1])) "minf" else if (w[1] < 0) paste0("m", abs(w[1])) else as.character(w[1])
      eStr <- if (is.infinite(w[2])) "inf" else if (w[2] < 0) paste0("m", abs(w[2])) else as.character(w[2])
      tolower(paste0(sStr, "_to_", eStr))
    }
    cleanWindow[[wName]] <- w
  }

  cleanWindow
}

#' Validate index date column
#'
#' @param indexDate Character column name.
#' @param x Cohort table reference.
#' @param call Environment.
#'
#' @return Validated index date column name.
#' @noRd
validateIndexDate <- function(indexDate, x, call = parent.frame()) {
  omopgenerics::assertCharacter(indexDate, length = 1, call = call)
  if (!indexDate %in% colnames(x)) {
    cli::cli_abort(glue::glue("indexDate '{indexDate}' must be a column in x."), call = call)
  }
  indexDate
}

#' Validate censor date column
#'
#' @param censorDate Optional character column name.
#' @param x Cohort table reference.
#' @param call Environment.
#'
#' @return Validated censor date column name or NULL.
#' @noRd
validateCensorDate <- function(censorDate, x, call = parent.frame()) {
  if (is.null(censorDate)) {
    return(NULL)
  }
  omopgenerics::assertCharacter(censorDate, length = 1, call = call)
  if (!censorDate %in% colnames(x)) {
    cli::cli_abort(glue::glue("censorDate '{censorDate}' must be a column in x."), call = call)
  }
  censorDate
}

#' Validate target table name
#'
#' @param name Optional table name.
#' @param call Environment.
#'
#' @return Validated name string or NULL.
#' @noRd
validateName <- function(name, call = parent.frame()) {
  omopgenerics::assertCharacter(name, length = 1, null = TRUE, call = call)
}

#' Validate specialties argument
#'
#' @param specialties Optional named list of integer/numeric vectors.
#' @param call Environment for error reporting.
#'
#' @return Validated specialties list or NULL.
#' @noRd
validateSpecialties <- function(specialties, call = parent.frame()) {
  if (is.null(specialties)) {
    return(NULL)
  }
  if (!is.list(specialties) || is.null(names(specialties)) || any(names(specialties) == "")) {
    cli::cli_abort("Argument 'specialties' must be a named list of integer vectors.", call = call)
  }
  lapply(specialties, as.integer)
}

#' Validate countBy and collapseOverlapping arguments
#'
#' @param countBy Character scalar or vector specifying count granularity ('days' or 'records').
#' @param collapseOverlapping Optional logical flag. If FALSE, forces countBy to 'records'.
#' @param call Environment for error reporting.
#'
#' @return Normalized countBy string ('days' or 'records').
#' @noRd
validateCountBy <- function(countBy = c("days", "records"), collapseOverlapping = TRUE, call = parent.frame()) {
  if (!is.null(collapseOverlapping) && is.logical(collapseOverlapping) && length(collapseOverlapping) == 1) {
    if (!collapseOverlapping) {
      return("records")
    }
  }
  if (is.null(countBy)) {
    return("days")
  }
  if (is.character(countBy)) {
    countBy <- tolower(countBy[1])
  } else {
    cli::cli_abort("Argument 'countBy' must be either 'days' or 'records'.", call = call)
  }
  if (!countBy %in% c("days", "records")) {
    cli::cli_abort("Argument 'countBy' must be either 'days' or 'records'.", call = call)
  }
  countBy
}

#' Validate gapDays and collapseGap arguments
#'
#' @param gapDays Integer scalar >= 0. Maximum gap in days between contiguous stays.
#' @param collapseGap Optional alias for gapDays.
#' @param call Environment for error reporting.
#'
#' @return Validated integer gap threshold.
#' @noRd
validateGapDays <- function(gapDays = 1L, collapseGap = NULL, call = parent.frame()) {
  val <- if (!is.null(collapseGap)) collapseGap else gapDays
  if (is.null(val) || !is.numeric(val) || length(val) != 1 || is.na(val)) {
    cli::cli_abort("Argument 'gapDays' must be a single non-negative integer (>= 0).", call = call)
  }
  int_val <- as.integer(val)
  if (int_val < 0 || int_val != val) {
    cli::cli_abort("Argument 'gapDays' must be a single non-negative integer (>= 0).", call = call)
  }
  int_val
}


