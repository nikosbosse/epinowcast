% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{date_to_numeric_modulus}
\alias{date_to_numeric_modulus}
\title{Convert date column to numeric and calculate its modulus with given timestep.}
\usage{
date_to_numeric_modulus(dt, date_column, timestep)
}
\arguments{
\item{dt}{A data.table.}

\item{date_column}{A character string representing the name of the date
column in dt.}

\item{timestep}{An integer representing the internal timestep.}
}
\value{
A modified data.table with two new columns: one for the numeric
representation of the date minus the minimum date and another for its
modulus with the timestep.
}
\description{
This function processes a date column in a \code{data.table}, converting it to a
numeric representation and then computing the modulus with the provided
timestep.
}
\seealso{
Utility functions
\code{\link{aggregate_rolling_sum}()},
\code{\link{coerce_date}()},
\code{\link{coerce_dt}()},
\code{\link{convert_cmdstan_to_rstan}()},
\code{\link{expose_stan_fns}()},
\code{\link{get_internal_timestep}()},
\code{\link{is.Date}()},
\code{\link{stan_fns_as_string}()}
}
\concept{utils}
