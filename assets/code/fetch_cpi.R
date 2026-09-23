#!/usr/local/bin/Rscript

library(httr2)
library(jsonlite)

out_file <- "cpi.db"

# Input in the format:
# 2021-12-01:2022-01-01,2022-03-01:2024-07-01
stdin <- file("stdin", "r")
lines <- readLines(stdin)

ranges <- strsplit(lines, ",")

cpi_ranges = list()

get_cpi_range <- function(start, end) {
  url <- "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorByReferencePeriodRange"
  response <- request(url) |>
      req_method("GET") |>
      req_headers("Content-Type" = "application/json") |>
      req_url_query(
	vectorIds = "\"41690973\"",
	startRefPeriod = start,
	endReferencePeriod = end
      ) |>
      req_perform()

  response_body <- resp_body_string(response)
  parsed_body <- fromJSON(response_body, flatten = TRUE)

  months <- parsed_body$object.vectorDataPoint[[1]]$refPer
  values <- parsed_body$object.vectorDataPoint[[1]]$value

  data.frame(
    months = months,
    values = values
  )
}

for (i in 1:length(ranges[[1]])) {
  range <- strsplit(ranges[[1]][i], ':')
  start <- range[[1]][1]
  end <- range[[1]][2]

  cpi_ranges[[i]] <- get_cpi_range(start, end)
}

cpi_monthly <- do.call(rbind, cpi_ranges)
cpi_monthly <- cpi_monthly[order(cpi_monthly$months), ]
rownames(cpi_monthly) <- NULL # Reset row indices so they are sequential after sorting

# If the dataframe doesn't contain last (i.e., the most recent) month's CPI
# figure, append it to the dataframe. This is required as it will be our
# reference frame for present day dollar (PDD) calculations
this_month <- as.Date(format(Sys.Date(), "%Y-%m-01"), format = "%Y-%m-%d")
last_month <- format(this_month - 1, "%Y-%m-01")

url <- "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods"
response <- request(url) |>
req_method("POST") |>
req_headers(Accept = "application/json") |>
req_body_json(list(list( # API expects JSON array of objects ([{...}], first list become {} second list becomes [])
    vectorId = 41690973,
    latestN = 1
))) |>
req_perform()

response_body <- resp_body_string(response)
parsed_body <- fromJSON(response_body, flatten = TRUE)

latest_month <- parsed_body$object.vectorDataPoint[[1]]$refPer
latest_value <- parsed_body$object.vectorDataPoint[[1]]$value

if (cpi_monthly$months[nrow(cpi_monthly)] != latest_month) {
  cpi_monthly[nrow(cpi_monthly) + 1, ] <- list(latest_month, latest_value)
}

# Create new column with CPI figures shifted back in time by a month to make
# month-on-month (MoM) changes easier/more efficient to calculate
shifted_column <- c(
  cpi_monthly$values[2:nrow(cpi_monthly)],
  cpi_monthly$values[nrow(cpi_monthly)]
)
cpi_monthly[, ncol(cpi_monthly) + 1] <- list(shifted = shifted_column)

# Calculate backward-looking MoM CPI changes as a fraction of the next (future)
# month's CPI value
cpi_monthly[, ncol(cpi_monthly) + 1] <- list(
  mom_change = cpi_monthly$values / cpi_monthly$shifted
)

# Step backward through the MoM column, calculating the cumulative product at
# each step. This gives us the discount factor/exchange rate between one
# present-day dollar (PDD) and its historical equivalent. The inverse of this
# figure would be the actual present-day value of one dollar from the given
# month in history (growth factor of a historical dollar)
pdd <- c(
  numeric(nrow(cpi_monthly) - 1),
  cpi_monthly$mom_change[nrow(cpi_monthly)]
)
for (i in (nrow(cpi_monthly) - 1):1) {
  pdd[i] <- cpi_monthly$mom_change[i] * pdd[i + 1]
}
cpi_monthly[, ncol(cpi_monthly) + 1] <- list(discount = round(pdd, digits = 2))

print(cpi_monthly)

cat("D CPI1,000.00\n\n", file = out_file, append = FALSE)
for(i in 1:nrow(cpi_monthly)) {
  line <- paste0("P ", cpi_monthly$months[i], " CPI $", sprintf("%.2f", cpi_monthly$discount[i]), "\n")
  cat(line, file = out_file, append = TRUE)
}
