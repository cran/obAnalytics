## Copyright (C) 2015,2016 Philip Stubbings <phil@parasec.net>
## Licensed under the GPL v2 license. See LICENSE.md for full terms.

##' Construct trades data.table.
##'
##' Given event data which has been pre-matched with maker/taker event ids,
##' this function will return a data.table containing all matched executions.
##' 
##' @param events Limit order event data with assigned maker/taker event ids.
##' @return A data.frame describing marketable order executions of the following
##' form:
##' \describe{
##'   \item{timestamp}{min(maker timestamp, taker timestamp) (first time we
##' learned of this trade)}
##'   \item{price}{Maker price (taker limit price can cross the book.)}
##'   \item{volume}{Lifted/traded volume}
##'   \item{direction}{Trade direction (side of the aggressor/taker)}
##'   \item{maker.event.id}{event.id corresponding to row in events data}
##'   \item{taker.event.id}{event.id corresponding to tow in events data}
##'   \item{maker}{Maker limit order id}
##'   \item{taker}{Taker limit order id}
##' }
##'
##' A market limit order (marketable) is first a taker and then becomes a maker
##' after landing in the order book before it's limit is reached.
##'
##' A market order is always a taker: it's volume will be filled before it's
##' limit is reached.
##'
##' Grouping executions by maker/taker can be used to analyse market impact
##' events.
##' 
##' @author phil
##' @examples
##' \dontrun{
##'
##' csv.file <- system.file("extdata", "orders.csv.xz", package="obAnalytics")
##' events <- loadEventData(csv.file)
##' events <- eventMatch(events)
##' trades <- matchTrades(events)
##' }
##' @keywords internal
matchTrades <- function(events) {

  # trades with matching maker/taker.
  # align them by event id.
  matching.bids <- events[events$direction == "bid" & 
      !is.na(events$matching.event), ]
  matching.bids <- matching.bids[order(matching.bids$event.id), ]
  matching.asks <- events[events$direction == "ask" & 
      !is.na(events$matching.event), ]
  matching.asks <- matching.asks[order(matching.asks$matching.event), ]
  stopifnot(all(matching.bids$event.id - matching.asks$matching.event == 0))

  # match makers and takers.
  # bid is maker if it comes first.
  # coming first is determined by exchange timestamp and if == then falls back
  # to order id.
  # it is assumed that the order id is incremented by the exchange.  
  bid.exchange.ts <- matching.bids$exchange.timestamp
  ask.exchange.ts <- matching.asks$exchange.timestamp
  bid.maker <- bid.exchange.ts < ask.exchange.ts | 
      (bid.exchange.ts == ask.exchange.ts & matching.bids$id < matching.asks$id)

  # trade timestamp is the first (local time) observation in the 2 matching
  # trades.
  bid.local.ts <- matching.bids$timestamp
  ask.local.ts <- matching.asks$timestamp
  timestamp <- as.POSIXct(ifelse(bid.local.ts <= ask.local.ts,
                                 bid.local.ts, ask.local.ts), 
                          origin="1970-01-01", tz="UTC")

  # the price at which the trade occured is the maker's limit price.
  price <- ifelse(bid.maker, matching.bids$price, matching.asks$price)
 
  # volume is either side of trade
  volume <- matching.bids$fill

  # if bid is maker, trade was initiated by a seller.
  direction <- factor(ifelse(bid.maker, "sell", "buy"))

  # finally, maker+taker id.
  maker.event.id <- ifelse(bid.maker, matching.bids$event.id, 
      matching.asks$event.id)
  taker.event.id <- ifelse(bid.maker, matching.asks$event.id, 
      matching.bids$event.id)

  # maker/taker order id
  maker <- with(events, id[match(maker.event.id, event.id)])
  taker <- with(events, id[match(taker.event.id, event.id)])
    
  # return timestamp ordered series.
  combined <- data.frame(timestamp, price, volume, direction, maker.event.id, 
      taker.event.id, maker, taker)
  combined <- combined[order(combined$timestamp), ]
    
  # check for price jumps > $10.
  # this can happen if a maker has been misclassified as a taker.
  # a misclassification can occur if the exchange does not match orders
  # in the same order as the order id. 
  jumps <- which(abs(diff(combined$price)) > 10)
  if(length(jumps) > 0) {
    warning(paste(format(head(events$timestamp, 1),"%D"), ":", length(jumps),
                  "jumps > $10 (swaping makers with takers)"))
    # go through the trades and swap maker id, event id and price with taker id,
    # event id and price.
    for(i in jumps) {
      prev.jump <- combined[i-1, ]
      this.jump <- combined[i, ]
      if(abs(this.jump$price-prev.jump$price) > 10) {
        taker.event.id <- this.jump$taker.event.id
        taker.price <- events[events$event.id == taker.event.id, ]$price
        taker.dir <- if(this.jump$direction == "buy") "sell" else "buy"
        swap <- data.frame(taker.price, taker.dir, taker.event.id,
                           this.jump$maker.event.id, this.jump$taker,
                           this.jump$maker)
        combined[i, c("price", "direction", "maker.event.id", "taker.event.id",
                      "maker", "taker")] <- swap
      }
    }
  }
  combined
}

##' Trade impacts.
##'
##' Generates a data.frame containing order book impacts.
##'
##' An impact consists of 1 or more limit orders being hit in order to fulfil a
##' market order. 
##' 
##' @param trades \code{\link{trades}} data.
##' @return A data.frame containing a summary of market order impacts:
##' \describe{
##'   \item{id}{market order id}
##'   \item{min.price}{minimum executed price}
##'   \item{max.price}{maximum executed price}
##'   \item{vwap}{VWAP obtained by market order}
##'   \item{hits}{number of limit orders hit by market order}
##'   \item{vol}{total volume removed by this impact}
##'   \item{start.time}{(local) start time of this impact}
##'   \item{end.time}{(local) end time of this impact}
##'   \item{dir}{direction of this impact (buy or sell)}
##' }
##' @author phil
##' @examples
##'
##' # get impacts data.frame from trades data.
##' impacts <- tradeImpacts(lob.data$trades)
##'
##' # impacts (in bps) 
##' sell.bps <- with(impacts[impacts$dir == "sell", ], {
##'   (max.price-min.price)/max.price
##' })
##' 10000*summary(sell.bps[sell.bps > 0])
##'
##' @export tradeImpacts
tradeImpacts <- function(trades) {

  # group by taker id.
  by.group <- by(trades, trades$taker, function(impact) {
    with(impact, {
      list(id=tail(taker, 1),
           min.price=min(price),
           max.price=max(price),
           vwap=round(vwap(price, volume), 2),
           hits=nrow(impact),
           vol=sum(volume),
           start.time=min(timestamp),
           end.time=max(timestamp),
           dir=tail(direction, 1))
    })
  })
    
  # return conversion of (by) result to data.frame
  do.call("rbind", lapply(by.group, function(x) data.frame(x)))
}
