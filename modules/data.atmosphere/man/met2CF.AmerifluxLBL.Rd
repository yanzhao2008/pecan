% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/met2CF.AmerifluxLBL.R
\name{met2CF.AmerifluxLBL}
\alias{met2CF.AmerifluxLBL}
\title{met2CF.AmerifluxLBL}
\usage{
met2CF.AmerifluxLBL(in.path, in.prefix, outfolder, start_date, end_date, format,
  overwrite = FALSE, verbose = FALSE, ...)
}
\arguments{
\item{in.path}{location on disk where inputs are stored}

\item{in.prefix}{prefix of input and output files}

\item{outfolder}{location on disk where outputs will be stored}

\item{start_date}{the start date of the data to be downloaded (will only use the year part of the date)}

\item{end_date}{the end date of the data to be downloaded (will only use the year part of the date)}

\item{overwrite}{should existing files be overwritten}

\item{verbose}{should ouput of function be extra verbose}
}
\description{
Get meteorology variables from Ameriflux LBL and convert to netCDF CF format
}
\author{
Ankur Desai
}
