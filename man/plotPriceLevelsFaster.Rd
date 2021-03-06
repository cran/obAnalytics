% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/visualisation.R
\name{plotPriceLevelsFaster}
\alias{plotPriceLevelsFaster}
\title{Poor man's heatmap.}
\usage{
plotPriceLevelsFaster(depth, spread, trades, show.mp = T, col.bias = 0.1)
}
\arguments{
\item{depth}{The order book depth (lob.data$depth).}

\item{spread}{Spread to overlay (getSpread(lob.data$depth.summary))}

\item{trades}{Trades (lob.data$trades).}

\item{show.mp}{If True, spread will be summarised as midprice.}

\item{col.bias}{1 = uniform colour spectrum. 0.25 = bias toward 0.25
(more red less blue). <= 0 enables logarithmic scaling.}
}
\description{
Used by plotPriceLevels filtering function.
}
\details{
An individual order book will consist of hundreds of thousands to millions
of updates per day. Plotting a heatmap of order book depth with even a few
thousand filtered events with ggplot is excruciatingly slow. This function
makes it possible to plot a heat map of all order book updates in a
reasonable amount of time. To achieve this, the function plots horizontal
colour coded lines for each price level update.
}
\author{
phil
}
\keyword{internal}

