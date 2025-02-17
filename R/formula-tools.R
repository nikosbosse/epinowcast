#' Define a model manually using fixed and random effects
#'
#' @description For most typical use cases [enw_formula()] should
#' provide sufficient flexibility to allow models to be defined. However,
#' there may be some instances where more manual model specification is
#' required. This function supports this by allowing the user to supply
#' vectors of fixed, random, and customised random effects (where they are
#' not first treated as fixed effect terms). Prior to `1.0.0` this was the
#' main interface for specifying models and it is still used internally to
#' handle some parts of the model specification process.
#'
#' @param fixed A character vector of fixed effects.
#'
#' @param random A character vector of random effects. Random effects
#' specified here will be added to the fixed effects.
#'
#' @param custom_random A vector of random effects. Random effects added here
#' will not be added to the vector of fixed effects. This can be used to random
#' effects for fixed effects that only have a partial name match.
#'
#' @param no_contrasts Logical, defaults to `FALSE`. `TRUE` means that no
#' variable uses contrast. Alternatively a character vector of variables can be
#' supplied indicating which variables should  not have contrasts.
#'
#' @param add_intercept Logical, defaults to `FALSE`. Should an intercept be
#' added to the fixed effects.
#'
#' @return A list specifying the fixed effects (formula, design matrix, and
#' design matrix index), and random effects (formula and design matrix).
#'
#' @inheritParams enw_formula
#' @family formulatools
#' @importFrom stats as.formula
#' @export
#' @examples
#' data <- enw_example("prep")$metareference[[1]]
#' enw_manual_formula(data, fixed = "week", random = "day_of_week")
enw_manual_formula <- function(data, fixed = NULL, random = NULL,
                               custom_random = NULL, no_contrasts = FALSE,
                               add_intercept = TRUE) {
  data <- coerce_dt(data)
  if (add_intercept) {
    form <- "1"
  } else {
    form <- NULL
  }

  cr_in_dt <- purrr::map(
    custom_random, ~ colnames(data)[startsWith(colnames(data), .)]
  )
  cr_in_dt <- unlist(cr_in_dt)

  form <- c(form, fixed, random, cr_in_dt)
  if (length(random) > 0) {
    no_contrasts <- c(random)
  }
  form <- as.formula(paste0("~ ", paste(form, collapse = " + ")))

  # build effects design matrix (with  no contrasts)
  fixed <- enw_design(form, data,
    no_contrasts = no_contrasts,
    sparse = TRUE
  )

  # get effects
  effects <- enw_effects_metadata(fixed$design)

  random <- c(random, custom_random)

  if (length(random) == 0) {
    random <- enw_design(~1, effects, sparse = FALSE)
  } else {
    for (i in random) {
      effects <- enw_add_pooling_effect(effects, var_name = i, prefix = i)
    }
    rand_form <- c("0", "fixed", random)
    rand_form <- as.formula(paste0("~ ", paste(rand_form, collapse = " + ")))
    random <- enw_design(rand_form, effects, sparse = FALSE)
  }
  return(list(fixed = fixed, random = random))
}

#' Converts formulas to strings
#'
#' @return A character string of the supplied formula
#' @inheritParams split_formula_to_terms
#' @family formulatools
#' @examples
#' epinowcast:::as_string_formula(~ 1 + age_group)
as_string_formula <- function(formula) {
  form <- paste(deparse(formula), collapse = " ")
  form <- gsub("\\s+", " ", form, perl = FALSE)
  return(form)
}

#' Split formula into individual terms
#'
#' @return A character vector of formula terms
#' @inheritParams enw_formula
#' @family formulatools
#' @examples
#' epinowcast:::split_formula_to_terms(~ 1 + age_group + location)
split_formula_to_terms <- function(formula) {
  formula <- as_string_formula(formula)
  formula <- gsub("~", "", formula, fixed = TRUE)
  formula <- strsplit(formula, " + ", fixed = TRUE)[[1]]
  return(formula)
}

#' Finds random walk terms in a formula object
#'
#' @description This function extracts random walk terms
#' denoted using [rw()] from a formula so that they can be
#' processed on their own.
#'
#' @section Reference:
#' This function was adapted from code written
#' by J Scott (under an MIT license) as part of
#' the `epidemia` package (https://github.com/ImperialCollegeLondon/epidemia/).
#'
#' @return A character vector containing the random walk terms that have been
#' identified in the supplied formula.
#'
#' @inheritParams enw_formula
#' @family formulatools
#' @examples
#' epinowcast:::rw_terms(~ 1 + age_group + location)
#'
#' epinowcast:::rw_terms(~ 1 + age_group + location + rw(week, location))
rw_terms <- function(formula) {
  # use regex to find random walk terms in formula
  trms <- attr(terms(formula), "term.labels")
  match <- grepl("(^(rw)\\([^:]*\\))$", trms)

  # ignore when included in a random effects term
  match <- match & !grepl("|", trms, fixed = TRUE)
  return(trms[match])
}

#' Remove random walk terms from a formula object
#'
#' @description This function removes random walk terms
#' denoted using [rw()] from a formula so that they can be
#' processed on their own.
#'
#' @section Reference:
#' This function was adapted from code written
#' by J Scott (under an MIT license) as part of
#' the `epidemia` package (https://github.com/ImperialCollegeLondon/epidemia/).
#'
#' @inheritParams split_formula_to_terms
#' @return A formula object with the random walk terms removed.
#' @family formulatools
#' @examples
#' epinowcast:::remove_rw_terms(~ 1 + age_group + location)
#'
#' epinowcast:::remove_rw_terms(~ 1 + age_group + location + rw(week, location))
remove_rw_terms <- function(formula) {
  form <- as_string_formula(formula)
  form <- gsub("rw\\(.*?\\) \\+ ", "", form)
  form <- gsub("\\+ rw\\(.*?\\)", "", form)
  form <- gsub("rw\\(.*?\\)", "", form)

  form <- tryCatch(
    {
      as.formula(form)
    },
    error = function(cond) {
      as.formula(paste(form, 1))
    }
  )
  return(form)
}

#' Parse a formula into components
#'
#' @description This function uses a series internal functions
#' to break an input formula into its component parts each of which
#' can then be handled separately. Currently supported components are
#' fixed effects, [lme4] style random effects, and random walks using the
#' [rw()] helper function.
#'
#' @section Reference:
#' The random walk functions used internally by this function were
#' adapted from code written by J Scott (under an MIT license) as part of
#' the `epidemia` package (https://github.com/ImperialCollegeLondon/epidemia/).
#'
#' @return A list of formula components. These currently include:
#'  - `fixed`: A character vector of fixed effect terms
#'  - `random`: A list of of [lme4] style random effects
#'  - `rw`: A character vector of [rw()] random walk terms.
#' @inheritParams enw_formula
#' @importFrom lme4 nobars findbars
#' @family formulatools
#' @examples
#' epinowcast:::parse_formula(~ 1 + age_group + location)
#'
#' epinowcast:::parse_formula(~ 1 + age_group + (1 | location))
#'
#' epinowcast:::parse_formula(~ 1 + (age_group | location))
#'
#' epinowcast:::parse_formula(~ 1 + (1 | location) + rw(week, location))
parse_formula <- function(formula) {
  if (!inherits(formula, "formula")) {
    stop("'formula' must be a formula object.")
  }
  rw <- rw_terms(formula)
  formula <- remove_rw_terms(formula)
  fixed <- lme4::nobars(formula)
  random <- lme4::findbars(formula)

  model_terms <- list(
    fixed = split_formula_to_terms(fixed),
    random = random,
    rw = rw
  )
  return(model_terms)
}

#' Adds random walks with Gaussian steps to the model.
#'
#' A call to `rw()` can be used in the 'formula' argument of model
#' construction functions in the `epinowcast` package such as [enw_formula()].
#' Does not evaluate arguments but instead simply passes information for use in
#' model construction.
#'
#' @param time Defines the random walk time period.
#'
#' @param by Defines the grouping parameter used for the random walk.
#' If not specified no grouping is used. Currently this is limited to a single
#' variable.
#'
#' @param type Character string, how standard deviation of grouped random
#' walks is estimated: "independent", or "dependent" across groups;
#' enforced by [base::match.arg()].
#'
#' @return A list defining the time frame, group, and type with class
#' "enw_rw_term" that can be interpreted by [construct_rw()].
#' @export
#' @family formulatools
#' @examples
#' rw(time)
#'
#' rw(time, location)
#'
#' rw(time, location, type = "dependent")
rw <- function(time, by, type = c("independent", "dependent")) {
  type <- match.arg(type)
  if (missing(time)) {
    stop("time must be present")
  } else {
    time <- deparse(substitute(time))
  }

  if (missing(by)) {
    by <- NULL
  } else {
    by <- deparse(substitute(by))
  }
  out <- list(time = time, by = by, type = type)
  class(out) <- "enw_rw_term"
  return(out)
}

#' Constructs random walk terms
#'
#' @description This function takes random walks as defined
#' by [rw()], produces the required additional variables
#' (denoted using a "c" prefix and constructed using
#' [enw_add_cumulative_membership()]), and then returns the
#' extended `data.frame` along with the new fixed effects and the
#' random effect structure.
#'
#' @param rw A random walk term as defined by [rw()].
#'
#' @param data A `data.frame` of observations used to define the
#' random walk term. Must contain the time and grouping variables
#' defined in the [rw()] term specified.
#'
#' @return A list containing the following:
#'  - `data`: The input `data.frame` with the addition of the new variables
#' required by the specified random walk. These are added using
#' [enw_add_cumulative_membership()].
#'  -`terms`: A character vector of new fixed effects terms to add to a model
#' formula.
#'  - `effects`: A `data.frame` describing the random effect structure of the
#' new effects.
#' @family formulatools
#' @examples
#' data <- enw_example("preproc")$metareference[[1]]
#'
#' epinowcast:::construct_rw(rw(week), data)
#'
#' epinowcast:::construct_rw(rw(week, day_of_week), data)
construct_rw <- function(rw, data) {
  if (!inherits(rw, "enw_rw_term")) {
    stop("rw must be a random walk term as constructed by rw")
  }

  if (!is.numeric(data[[rw$time]])) {
    stop(
      "The time variable ", rw$time, " is not numeric but must be to be used ",
      "as a random walk term."
    )
  }

  if (anyNA(data[[rw$time]])) {
    stop("The time variable ", rw$time, " contains non-numeric values.")
  }

  # add new cumulative features to use for the random walk
  data <- enw_add_cumulative_membership(
    data,
    feature = rw$time
  )
  ctime <- paste0("c", rw$time)
  terms <- grep(ctime, colnames(data), value = TRUE)
  fdata <- data[, c(terms, rw$by), with = FALSE]
  if (!is.null(rw$by)) {
    if (is.null(fdata[[rw$by]])) {
      stop(
        "Requested grouping variable",
        rw$by, " is not present in the supplied data"
      )
    }
    if (length(unique(fdata[[rw$by]])) < 2) {
      message(
        "A grouped random walk using ", rw$by,
        " is not possible as this variable has fewer than 2 unique values."
      )
      rw$by <- NULL
    } else {
      terms <- paste0(rw$by, ":", terms)
    }
  }

  # make a fixed effects design matrix
  fixed <- enw_manual_formula(
    fdata,
    fixed = terms, no_contrasts = TRUE
  )$fixed$design

  # extract effects metadata
  effects <- enw_effects_metadata(fixed)

  # implement random walk structure effects
  if (is.null(rw$by) || rw$type %in% "dependent") {
    effects <- enw_add_pooling_effect(
      effects, var_name = paste0("rw__", rw$time), prefix = ctime
    )
  } else {
    for (i in unique(fdata[[rw$by]])) {
      nby <- paste0(rw$by, i)
      effects <- enw_add_pooling_effect(
        effects, var_name = paste0("rw__", nby, "__", rw$time),
        finder_fn = function(effect, pattern, prefix) {
          grepl(pattern, effect) & startsWith(effect, prefix)
        },
        pattern = ctime, prefix = paste0(rw$by, i)
      )
    }
  }
  return(list(data = data, terms = terms, effects = effects))
}

#' Defines random effect terms using the lme4 syntax
#'
#' @param formula A random effect as returned by [lme4::findbars()]
#' when a random effect is defined using the [lme4] syntax in
#' formula. Currently only simplified random effects (i.e
#'  LHS | RHS) are supported.
#'
#' @export
#' @return A list defining the fixed and random effects of the specified
#' random effect
#' @family formulatools
#' @examples
#' form <- epinowcast:::parse_formula(~ 1 + (1 | age_group))
#' re(form$random[[1]])
#'
#' form <- epinowcast:::parse_formula(~ 1 + (location | age_group))
#' re(form$random[[1]])
re <- function(formula) {
  terms <- strsplit(as_string_formula(formula), " | ", fixed = TRUE)[[1]]
  out <- list(fixed = terms[1], random = terms[2])
  class(out) <- "enw_re_term"
  return(out)
}

#' Constructs random effect terms
#'
#' @param re A random effect as defined using [re()] which itself takes
#' random effects specified in a model formula using the [lme4] syntax.
#'
#' @param data A `data.frame` of observations used to define the
#' random effects. Must contain the variables specified in the
#' [re()] term.
#'
#' @return A list containing the transformed data ("data"),
#' fixed effects terms ("terms") and a  `data.frame` specifying
#' the random effect structure between these terms (`effects`). Note
#' that if the specified random effect was not a factor it will have been
#' converted into one.
#'
#' @family formulatools
#' @importFrom purrr map
#' @examples
#' # Simple examples
#' form <- epinowcast:::parse_formula(~ 1 + (1 | day_of_week))
#' data <- enw_example("prepr")$metareference[[1]]
#' random_effect <- re(form$random[[1]])
#' epinowcast:::construct_re(random_effect, data)
#'
#' # A more complex example
#' form <- epinowcast:::parse_formula(
#'   ~ 1 + disp + (1 + gear | cyl) + (0 + wt | am)
#' )
#' random_effect <- re(form$random[[1]])
#' epinowcast:::construct_re(random_effect, mtcars)
#'
#' random_effect2 <- re(form$random[[2]])
#' epinowcast:::construct_re(random_effect2, mtcars)
construct_re <- function(re, data) {
  if (!inherits(re, "enw_re_term")) {
    stop("re must be a random effect term as constructed by re")
  }

  # extract random and fixed effects
  fixed <- strsplit(re$fixed, " + ", fixed = TRUE)[[1]]
  random <- strsplit(re$random, " + ", fixed = TRUE)[[1]]

  # expand random effects that are interactions
  expanded_random <- NULL
  random_int <- rep(FALSE, length(random))
  for (i in seq_along(random)) {
    current_random <- strsplit(random[i], ":", fixed = TRUE)[[1]]

    if (length(current_random) > 1) {
      if (length(current_random) > 2) {
        stop(
          "Interactions between more than 2 variables are not currently supported on the right hand side of random effects" # nolint
        )
      }
      if (length(unique(data[[current_random[2]]])) < 2) {
        message(
          "A random effect using ", current_random[2],
          " is not possible as this variable has fewer than 2 unique values."
        )
        random[i] <- current_random[1]
      } else {
        random_int[i] <- TRUE
      }
    }
    expanded_random <- c(expanded_random, current_random)
  }
  expanded_random <- unique(expanded_random)
  # detect if random effect interactions are present
  # loop through random effect interactions
  # make new random effects using unique values
  # add these new random effects to the data
  # add these new random effects to list of all random effects

  # combine into fixed effects terms
  terms <- NULL
  terms_int <- NULL
  for (i in seq_along(random)) {
    terms <- c(terms, paste0(fixed, ":", random[i]))
    terms_int <- c(terms_int, rep(random_int[i], length(fixed)))
  }
  names(terms_int) <- terms
  terms <- gsub("1:", "", terms, fixed = TRUE)
  terms <- terms[!startsWith(terms, "0:")]
  terms_int <- terms_int[!startsWith(terms, "0:")]

  # make all right hand side random effects factors
  data <- coerce_dt(data, required_cols = expanded_random)[,
    (expanded_random) := lapply(.SD, as.factor),
    .SDcols = expanded_random
  ]

  # make a fixed effects design matrix
  fixed <- enw_manual_formula(
    data,
    fixed = terms, no_contrasts = TRUE,
    add_intercept = FALSE
  )$fixed$design

  # extract effects metadata
  effects <- enw_effects_metadata(fixed)

  # implement random effects structure
  for (i in seq_along(terms)) {
    loc_terms <- strsplit(terms[i], ":", fixed = TRUE)[[1]]
    # expand right hand side random effect if its an interaction
    # and make a list to map to effects
    if (terms_int[i]) {
      expanded_int <- unique(data[[loc_terms[length(loc_terms)]]])
      expanded_int <- paste0(loc_terms[length(loc_terms)], expanded_int)
      j <- purrr::map(expanded_int, function(x) {
        j <- NULL
        if (length(loc_terms) > 2) {
          j <- loc_terms[1:(length(loc_terms) - 2)]
        }
        j <- c(j, paste0(loc_terms[length(loc_terms) - 1], ":", x))
        return(j)
      })
    } else {
      j <- list(loc_terms)
    }
    # link random effects with fixed effects
    # here we need to differentiate between random effects with
    # and without rhs interactions
    for (k in j) {
      if (length(k) == 1) {
          if (terms_int[i]) {
            effects <- enw_add_pooling_effect(
              effects, var_name = gsub(":", "__", k, fixed = TRUE),
              finder_fn = function(effect, pattern) {
                grepl(pattern[1], effect) &
                  grepl(pattern[2], effect, fixed = TRUE) &
                  lengths(
                    regmatches(effect, gregexpr(":", effect, fixed = TRUE))
                  ) == 1
              },
              pattern = strsplit(k, ":", fixed = TRUE)[[1]]
            )
          } else {
            effects <- enw_add_pooling_effect(
              effects, var_name = k,
              finder_fn = function(effect, pattern) {
                grepl(pattern, effect) & !grepl(":", effect, fixed = TRUE)
              },
              pattern = k
            )
          }
      } else {
        if (terms_int[i]) {
          effects <- enw_add_pooling_effect(
            effects,
            var_name = paste(gsub(":", "__", k, fixed = TRUE), collapse = "__"),
            finder_fn = function(effect, pattern) {
              grepl(pattern[1], effect) & grepl(pattern[2], effect) &
              grepl(pattern[3], effect)
            },
            pattern = c(k[1], strsplit(k[-1], ":", fixed = TRUE)[[1]])
          )
        } else {
          effects <- enw_add_pooling_effect(
            effects, var_name = paste(k, collapse = "__"),
            finder_fn = function(effect, pattern) {
              grepl(pattern[1], effect) & grepl(pattern[2], effect)
            },
            pattern = rev(k)
          )
        }
      }
    }
  }
  return(list(data = data, terms = terms, effects = effects))
}

#' Define a model using a formula interface
#'
#' @description This function allows models to be defined using a
#' flexible formula interface that supports fixed effects, random effects
#' (using [lme4] syntax). Note that the returned fixed effects design matrix is
#' sparse and so the index supplied is required to link observations to the
#' appropriate design matrix row.
#'
#' @param formula A model formula that may use standard fixed
#' effects, random effects using [lme4] syntax (see [re()]), and random walks
#' defined using the [rw()] helper function.
#'
#' @param data A `data.frame` of observations. It must include all
#' variables used in the supplied formula.
#'
#' @param sparse Logical, defaults to  `TRUE`. Should the fixed effects design
#' matrix be sparely defined.
#'
#' @return A list containing the following:
#'  - `formula`: The user supplied formula
#'  - `parsed_formula`: The formula as parsed by [parse_formula()]
#'  - `extended_formula`: The flattened version of the formula with
#'  both user supplied terms and terms added for the user supplied
#'  complex model components.
#'  - `fixed`:  A list containing the fixed effect formula, sparse design
#'  matrix, and the index linking the design matrix with observations.
#'  - `random`: A list containing the random effect formula, sparse design
#'  matrix, and the index linking the design matrix with random effects.
#'
#' @family formulatools
#' @export
#' @importFrom purrr map transpose
#' @importFrom data.table rbindlist setnafill
#' @examples
#' # Use meta data for references dates from the Germany COVID-19
#' # hospitalisation data.
#' obs <- enw_filter_report_dates(
#'   germany_covid19_hosp[location == "DE"],
#'   remove_days = 40
#' )
#' obs <- enw_filter_reference_dates(obs, include_days = 40)
#' pobs <- enw_preprocess_data(obs, by = c("age_group", "location"))
#' data <- pobs$metareference[[1]]
#'
#' # Model with fixed effects for age group
#' enw_formula(~ 1 + age_group, data)
#'
#' # Model with random effects for age group
#' enw_formula(~ 1 + (1 | age_group), data)
#'
#' # Model with a random effect for age group and a random walk
#' enw_formula(~ 1 + (1 | age_group) + rw(week), data)
#'
#' # Model defined without a sparse fixed effects design matrix
#' enw_formula(~1, data[1:20, ])
#'
#' # Model using an interaction in the right hand side of a random effect
#' # to specify an independent random effect per strata.
#' enw_formula(~ (1 + day | week:month), data = data)
enw_formula <- function(formula, data, sparse = TRUE) {
  data <- coerce_dt(data)

  # Parse formula
  parsed_formula <- parse_formula(formula)

  # Get random walk effects by iteratively looping through (as variables are
  # created in input data so need to use iteratively)
  if (length(parsed_formula$rw) > 0) {
    rw <- purrr::map(
      parsed_formula$rw,
      ~ eval(parse(text = paste0("epinowcast::", .)))
    )
    for (i in seq_along(rw)) {
      rw[[i]] <- construct_rw(rw[[i]], data)
      data <- rw[[i]]$data
      rw[[i]]$data <- NULL
    }
    rw <- purrr::transpose(rw)
    rw_terms <- unlist(rw$terms)
    rw_metadata <- data.table::rbindlist(
      rw$effects,
      use.names = TRUE, fill = TRUE
    )
  } else {
    rw_terms <- NULL
    rw_metadata <- NULL
  }

  # Get random effects for all specified random effects
  # Happens last as converts all RHS variables to factors (which can interact)
  # with other formula terms (i.e. random walks)
  if (length(parsed_formula$random) > 0) {
    random <- purrr::map(parsed_formula$random, re)
    for (i in seq_along(random)) {
      random[[i]] <- construct_re(random[[i]], data)
      data <- random[[i]]$data
      random[[i]]$data <- NULL
    }
    random <- purrr::transpose(random)

    random_terms <- unlist(random$terms)
    # Check that the user hasn't specified the same fixed and random effect
    if (any(random_terms %in% parsed_formula$fixed)) {
      stop(
        "Random effect terms must not be included in the fixed effects formula",
        call. = FALSE
      )
    }
    random_metadata <- data.table::rbindlist(
      random$effects,
      use.names = TRUE, fill = TRUE
    )
  } else {
    random_terms <- NULL
    random_metadata <- NULL
  }

  # Make fixed design matrix using all fixed effects from all components
  # this should include new variables added by the random effects
  # need to make sure all random effects don't have contrasts
  terms <- c(parsed_formula$fixed, random_terms, rw_terms)
  expanded_formula <- as.formula(paste0("~ ", paste(terms, collapse = " + ")))
  fixed <- enw_design(
    formula = expanded_formula,
    no_contrasts = random_terms,
    data = data,
    sparse = sparse
  )
  # Extract fixed effects metadata
  metadata <- enw_effects_metadata(fixed$design)

  # Combine with random effects and random walk effects
  if (!is.null(random_metadata)) {
    metadata <- metadata[!random_metadata, on = "effects"]
    metadata <- rbind(metadata, random_metadata, use.names = TRUE, fill = TRUE)
  }

  if (!is.null(rw_metadata)) {
    metadata <- metadata[!rw_metadata, on = "effects"]
    metadata <- rbind(metadata, rw_metadata, use.names = TRUE, fill = TRUE)
  }

  metadata <- cbind(
    metadata[, "effects"],
    data.table::setnafill(metadata[, -"effects"], fill = 0)
  )

  # Make the random effects design matrix
  if (ncol(metadata) == 2) {
    random <- enw_design(~1, metadata, sparse = FALSE)
  } else {
    random_formula <- as.formula(
      paste0(
        "~ 0 + ",
        paste(paste0("`", colnames(metadata)[-1], "`"), collapse = " + ")
      )
    )
    random <- enw_design(random_formula, metadata, sparse = FALSE)
  }

  out <- list(
    formula = as_string_formula(formula),
    parsed_formula = parsed_formula,
    expanded_formula = as_string_formula(expanded_formula),
    fixed = fixed,
    random = random
  )
  class(out) <- c("enw_formula", class(out))
  return(out)
}
