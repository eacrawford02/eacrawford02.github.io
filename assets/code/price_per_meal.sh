#!/usr/local/bin/bash

source "${0%/*}/gen_transaction_helper.sh"

account="Expenses:Food:Groceries"
meals_per_day=4

while true; do
  case "$1" in
    --months) shift
	      months="$1"
	      ;;
    *) break ;;
  esac
  shift
done

ledger_file="$1"

if [ -z "$ledger_file" ]; then
  echo "Usage: price_per_meal.sh --months %Y-%m[:%Y-%m][,...] FILE"
  echo ""
  cat <<- EOM
	Note: Dates must be in YYYY-MM format.
	EOM
  exit 1
fi

# Parse --months argument and pass formatted list of ranges into R script to
# construct the CPI discount file
ifs="$IFS"
IFS=','
for month in $months; do
  case "$month" in
    *:*) is_range=true
	 ;;
    *) is_range=false
       ;;
  esac

  start_date=$(echo "$month" | cut -f 1 -d ':')
  start_date="${start_date}-01"
  if [ $is_range == 'true' ]; then
    end_date=$(echo "$month" | cut -f 2 -d ':')
    end_date="${end_date}-01"
  else
    end_date="$start_date"
  fi
  args="$args${start_date}:${end_date},"
done
IFS="$ifs"

# Remove trailing comma
args="${args:0:-1}"

# R cannot write to file location relative to the path where the script is
# located, so we must first cd into where the script is located to have the
# cpi.db file placed alongside it
wd=$(pwd)
cd "${0%/*}"
echo "$args" | ./fetch_cpi.R
cd "$wd"

total=0
num_days=0

ifs="$IFS"
IFS=','
for month in $months; do
  case "$month" in
    *:*) is_range=true
	 ;;
    *) is_range=false
       ;;
  esac

  start_date=$(echo "$month" | cut -f 1 -d ':')
  start_date="${start_date}-01"
  if [ $is_range == 'true' ]; then
    end_date=$(echo "$month" | cut -f 2 -d ':')
    end_date=$(date -j -v+1m -f "%Y-%m-%d" "${end_date}-01" +%Y-%m-%d)
  else
    end_date=$(date -j -v+1m -f "%Y-%m-%d" "$start_date" +%Y-%m-%d)
  fi

  # Ledger will corrupt running total/average figures with <Revalued> postings
  # in a register report when --exchange is used. Normally this is desirable
  # when exchanging one commodity for another, but when that option/mechanism
  # is used to adjust for inflation, it means that the final value will be off
  # by a significant amount. Thus, we must calculate the running total
  # ourselves across all days in the range(s), posting by posting
  date_iter="$start_date"
  while [ "$date_iter" != "$end_date" ]; do
    inner_while=$(mktemp)
    transactions=$(ledger -f "$ledger_file" --limit "date==[$date_iter]" --price-db "${0%/*}/cpi.db" --exchange CPI --no-revalued --no-rounding --register_format "%(quantity(display_amount))\n" register "$account")
    echo "$transactions" > "$inner_while"

    # If there are multiple transactions on a single day, consider them all
    while read transaction; do
      if [ ! -z "$transaction" ]; then
	#echo "$transaction"
	# Compute running total
	total=$(echo "$total + $transaction" | bc -l)
      fi
    done < "$inner_while"
    rm -rf "$inner_while"

    date_iter=$(date -j -v+1d -f "%Y-%m-%d" "$date_iter" +%Y-%m-%d)
  done
  start_date=$(date -j -f "%Y-%m-%d" "$start_date" +%s)
  end_date=$(date -j -f "%Y-%m-%d" "$end_date" +%s)
  num_days=$(echo "$num_days + ($end_date - $start_date) / 86400" | bc -l)
done
IFS="$ifs"

total=$(round_to_cent $total)
echo "Total: \$$total"
num_days=$(round_to_cent $num_days)
echo "$num_days days in timespan"
daily_total=$(echo "$total / $num_days" | bc -l)
daily_total=$(round_to_cent $daily_total)
echo "Daily total: \$$daily_total"
echo "Meals/day: $meals_per_day"
price_per_meal=$(echo "$daily_total / $meals_per_day" | bc -l)
price_per_meal=$(round_to_cent $price_per_meal)
echo "Price per meal: \$$price_per_meal"
