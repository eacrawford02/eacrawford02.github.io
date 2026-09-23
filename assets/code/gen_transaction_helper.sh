#!/usr/local/bin/bash

get_string () {
  local message="$1"
  local default="$2" # Optional

  ret_val=""
  read -p "$message" ret_val
  if [ -z "$ret_val" ]; then
    if [ ! -z "$default" ]; then
      ret_val="$default"
    fi
  fi
  echo "$ret_val"
}

get_date () {
  local message="$1"
  local default="$2" # Optional

  ret_val=""
  while [ -z $ret_val ]; do
    read -p "$message" ret_val
    case "$ret_val" in
      '')
	if [ ! -z "$default" ]; then
	  ret_val="$default"
	  continue
	fi
	;;
      *[!0-9-]*) echo "Input is not a valid date" > /dev/tty ;;
      - | -* | *- | *--*) echo "Input is not a valid date" > /dev/tty ;;
      ?[0-9][0-9]?-??-??) continue ;;
      *) echo "Input is not a valid date" > /dev/tty ;;
    esac
    ret_val=""
  done
  echo "$ret_val"
}

get_whole () {
  local message="$1"

  ret_val=""
  while [ -z $ret_val ]; do
    read -p "$message" ret_val
    case "$ret_val" in
      ''|*[!0-9]*) echo "Input is not a whole number" > /dev/tty ;;
      *) continue ;;
    esac
    ret_val=""
  done
  echo "$ret_val"
}

get_int () {
  local message="$1"
  shift 1
  local exclusions="$@" # Optional, numbers to exclude from input

  while [ -z $ret_val ]; do
    read -p "$message" ret_val
    case "$ret_val" in
      ''|*[!0-9-]*) echo "Input is not a valid integer" > /dev/tty ;;
      - | *- | ?-*) echo "Input is not a valid integer" > /dev/tty ;;
      *)
	# Search for user input in exclusions list
	permitted=true
	for exclusion in $exclusions; do
	  if [ $ret_val = $exclusion ]; then
	    permitted=false
	  fi
	done
	# Reject if present
	if [ "$permitted" = true ]; then
	  continue
	else
	  echo "Input \"$ret_val\" is not permitted" > /dev/tty
	fi
	;;
    esac
    ret_val=""
  done
  echo "$ret_val"
}

# TODO: change name to get_pos_float
get_float () {
  local message="$1"

  ret_val=""
  while [ -z $ret_val ]; do
    read -p "$message" ret_val
    case "$ret_val" in
      ''|*[!0-9.]*) echo "Input is not a positive rational number" > /dev/tty ;;
      . | *. | *.*.*) echo "Input is not a positive rational number" > /dev/tty ;;
      *)
	# If the user entered an integer, add decimal point and trailing zeros
	if ! echo "$ret_val" | grep '\.' > /dev/null 2>&1; then
	  ret_val="$ret_val.00"
	# Add trailing zeros to rational numbers
	elif ! echo "$ret_val" | grep '\...' > /dev/null 2>&1; then
	  ret_val="${ret_val}0"
	fi
	continue
	;;
    esac
    ret_val=""
  done
  echo "$ret_val"
}

# TODO: change name to get_float
get_float_adv () {
  local message="$1"
  shift 1
  local exclusions="$@" # Optional, numbers to exclude from input

  ret_val=""
  while [ -z $ret_val ]; do
    read -p "$message" ret_val
    case "$ret_val" in
      ''|*[!0-9.-]*) echo "Input is not a rational number" > /dev/tty ;;
      . | *. | *.*.*) echo "Input is not a rational number" > /dev/tty ;;
      *)
	# Search for user input in exclusions list
	permitted=true
	for exclusion in $exclusions; do
	  if [ $(echo "$ret_val == $exclusion" | bc) -eq 1 ]; then
	    permitted=false
	  fi
	done
	# Reject if present
	if [ "$permitted" = true ]; then
	  # If the user entered an integer, add decimal point and trailing zeros
	  if ! echo "$ret_val" | grep '\.' > /dev/null 2>&1; then
	    ret_val="$ret_val.00"
	  # Add trailing zeros to rational numbers
	  elif ! echo "$ret_val" | grep '\...' > /dev/null 2>&1; then
	    ret_val="${ret_val}0"
	  fi
	  continue
	else
	  echo "Input \"$ret_val\" is not permitted" > /dev/tty
	fi
	;;
    esac
    ret_val=""
  done
  echo "$ret_val"
}

longest_string_size () {
  # printf used to convert tab character escape sequences into <tab> characters
  local accounts=$(printf "$@")

  # Determine longest account name and use that to calculate the amount
  # alignment column index (less any indentation) for use during formatting
  longest=0
  ifs="$IFS"
  IFS=$'\t'
  for acct in $accounts; do
    length=${#acct}
    if [ $length -gt $longest ]; then
      longest=$length
    fi
  done
  IFS="$ifs"
  echo "$longest"
}

boc_fx_on () {
  local amount="$1"
  local currencyA="$2"
  local currencyB="$3"
  local ex_date="$4"

  # TODO: change to multiplication so that output is consistent with Ledger's
  # internal calculation when the "1 AAPL {{$1.42}} @ 1 USD {$1.42}" commodity-swap posting format
  # is used
  url="https://www.bankofcanada.ca/valet/observations/FX${currencyB}${currencyA}/csv?start_date=$ex_date&end_date=$ex_date"
  rate=$(curl -s -X 'GET' "$url" -H 'accept: application/json' | tail -n 1 | cut -f 2 -d ',' | tr -d '\"')
  ret_val=$(echo "scale=4; $amount / $rate" | bc)
  #ret_val=$(round_to_cent $cad)
  echo "$ret_val"
}

get_fx_rate () {
  local currencyA="$1"
  local currencyB="$2"
  local fx_date="$3"

  # change to multiplication so that output is consistent with Ledger's
  # internal calculation when the "1 AAPL {{$1.42}} @ 1 USD {$1.42}" commodity-swap posting format
  # is used
  url="https://www.bankofcanada.ca/valet/observations/FX${currencyA}${currencyB}/csv?start_date=$fx_date&end_date=$fx_date"
  rate=$(curl -s -X 'GET' "$url" -H 'accept: application/json' | tail -n 1 | cut -f 2 -d ',' | tr -d '\"')
  echo "${rate%?}" # Drop trailing newline character
}

round_to_cent () {
  local dollars="$1" # Amount in dollars

  # printf only performs rounding half to even for integers, not fractional
  # values to the right of the decimal point. Thus we must shift the decimal
  # point to the right of the smallest fractional value that we want to round
  # (i.e., cents) so that that smallest fractional value is rounded correctly,
  # then shift the decimal back into its original position
  cents=$(echo "$dollars * 100" | bc)
  rounded=$(printf "%.0f" $cents)
  dollars=$(echo "scale=2; $rounded / 100" | bc)
  # bc won't include a leading zero for numbers between -1 and 1; printf will
  # automatically add this when formatting a float
  printf "%.2f\n" "$dollars"
}

split_ledger () {
  local ledger_file="$1"
  local start_date="$2"

  # Starting from the supplied date, search forward in time for the next
  # transaction (exclusive of the starting date). If found, split the ledger
  # file at the line preceding the transaction. Otherwise, leave the ledger file
  # unchanged
  closest_date=$(ledger -f $ledger_file --limit "date > [$start_date]" --head 1 --format "%d\n" --date-format "%Y-%m-%d" register | head -n 1)
  if [ ! -z "$closest_date" ]; then
    csplit -s "$ledger_file" /$closest_date/
  else
    mv "$ledger_file" xx00
  fi
  #search=true
  #while [ "$search" = true ]; do
  #  if csplit -s "$ledger_file" /$closest_date/; then
  #    search=false
  #  else
  #    # The date utility cannot increment a specified date unless that date is
  #    # formatted as seconds since the Unix epoch, so we convert our current
  #    # search iteration's date to seconds here before subsequently incrementing
  #    # it by a day
  #    temp=$(date -j -f %Y-%m-%d $closest_date +%s)
  #    # Stop searching when we pass the present date
  #    if [ $temp -gt $(date -j +%s) ]; then
  #      search=false
  #      mv "$ledger_file" xx00
  #    fi
  #    closest_date=$(date -r $temp -v+1d +%Y-%m-%d)
  #  fi
  #done
}

format_posting () {
  local indentation="$1"
  local acct="$2"
  local amount_offset="$3" # Optional

  printf "%*s$acct" "$indentation"
  if [ ! -z "$amount_offset" ]; then
    printf "%*s" "$((amount_offset - ${#acct}))"
  fi
}

secure_loan () {
  local ledger_file="$1"
  local out_file="$2"
  local settlement_date="$3"
  local amount="$4" # amount should always be negative
  local exchange_currency="$5"
  local fx_rate="$6"
  local cash_acct="$7"
  local loan_acct="$8"

  # Formatting options
  indentation=4
  margin=8

  # We want to extend the end date searched by Ledger to include the settlement
  # date in case other transactions were also made on that day
  end_date=$(date -j -v+1d -f "%Y-%m-%d" $settlement_date +%Y-%m-%d)

  length=$(longest_string_size "$cash_acct\t$loan_acct")
  amount_offset=$((length + margin))

  balance=$(ledger -f $ledger_file --end $end_date --limit "commodity == '$exchange_currency'" --flat --format "%T" balance "$cash_acct")
  if [ -z "$balance" ]; then
    balance='0'
  else
    if [ "$exchange_currency" != '$' ]; then
      balance=${balance% *} # Drop the currency name; we only want the amount
    else
      balance=$(echo "${balance:1}" | tr -d ',') # Drop the dollar sign and thousandths separator returned by Ledger
    fi
  fi
  shortfall=$(echo "$balance + $amount" | bc)
  shortfall=$(round_to_cent $shortfall)
  if [ $(echo "$shortfall < 0" | bc) -eq 1 ]; then
    echo "/!\\ Warning: insufficient funds for transaction; taking out loan"
    echo "$settlement_date * Margin Loan" >> "$out_file"
    if [ "$exchange_currency" != '$' ]; then
      format_posting $indentation "$cash_acct" $amount_offset >> "$out_file"
      printf "${shortfall:1} $exchange_currency @ \$$fx_rate\n" >> "$out_file"
      format_posting $indentation "$loan_acct" $amount_offset >> "$out_file"
      printf -- "$shortfall $exchange_currency @ \$$fx_rate\n\n" >> "$out_file"
    else
      format_posting $indentation "$cash_acct" $amount_offset >> "$out_file"
      printf "\$${shortfall:1}\n" >> "$out_file"
      format_posting $indentation "$loan_acct" $amount_offset >> "$out_file"
      printf "\$$shortfall\n\n" >> "$out_file"
    fi
  fi
}

service_loan () {
  local ledger_file="$1"
  local out_file="$2"
  local settlement_date="$3"
  local amount="$4" # amount should always be positive
  local exchange_currency="$5"
  local fx_rate="$6"
  local cash_acct="$7"
  local loan_acct="$8"
  local gains_acct="$9"
  local losses_acct="${10}"

  # Formatting options
  indentation=4
  margin=8

  # We want to extend the end date searched by Ledger to include the settlement
  # date in case other transactions were also made on that day
  end_date=$(date -j -v+1d -f "%Y-%m-%d" $settlement_date +%Y-%m-%d)

  length=$(longest_string_size "$cash_acct\t$loan_acct")
  amount_offset=$((length + margin))

  # Becuase a loan is a type of Liability, the amount returned by Ledger for an
  # outstanding loan will be a negative value
  outstanding=$(ledger -f $ledger_file --end $end_date --limit "commodity == '$exchange_currency'" --flat --format "%T" balance "$loan_acct")
  if [ -z "$outstanding" ]; then
    outstanding='0'
  else
    if [ "$exchange_currency" != '$' ]; then
      outstanding=${outstanding% *} # Drop the currency name; we only want the amount
    else
      outstanding=$(echo "${outstanding:1}" | tr -d ',') # Drop the dollar sign and thousandths separator returned by Ledger
    fi
    outstanding=$(echo "-($outstanding)" | bc)
    outstanding=$(round_to_cent $outstanding)
  fi

  if [ $(echo "$outstanding > 0" | bc) -eq 1 ]; then
    if [ $(echo "$outstanding >= $amount" | bc) -eq 1 ]; then
      repayment="$amount"
    elif [ $(echo "$outstanding < $amount" | bc) -eq 1 ]; then
      repayment="$outstanding"
    fi

    echo "$settlement_date * Margin Loan Repayment" >> "$out_file"
    if [ "$exchange_currency" != '$' ]; then
      value=$(echo "$repayment * $fx_rate" | bc -l)
      prev_acb=$(ledger -f $ledger_file --end $end_date --limit "commodity == '$exchange_currency'" --basis --format "%T\n" balance $nonreg_acct | tail -n 1)
      prev_acb=$(echo "${prev_acb:1}" | tr -d ',') # Drop the dollar sign and thousandths separator returned by Ledger
      prev_amount=$(ledger -f $ledger_file --end $end_date --limit "commodity == '$exchange_currency'" --format "%T\n" balance $nonreg_acct | tail -n 1)
      prev_amount=${prev_amount% *} # Drop the currency name; we only want the amount
      basis=$(echo "$prev_acb * $repayment / $prev_amount" | bc -l)
      basis=$(round_to_cent $basis)
      capital_gains=$(echo "$value - $basis" | bc)
      capital_gains=$(round_to_cent $capital_gains)

      format_posting $indentation "$cash_acct" $amount_offset >> "$out_file"
      printf -- "-$repayment $exchange_currency {{\$$basis}} @ \$$fx_rate\n" >> "$out_file"

      # If the amount of capital gains/losses is non-zero, include it as a posting
      if [ $(echo "$capital_gains > 0" | bc) -eq 1 ]; then
	format_posting $indentation "$gains_acct" $amount_offset >> "$out_file"
	printf "\$-$capital_gains\n" >> "$out_file"
      elif [ $(echo "$capital_gains < 0" | bc) -eq 1 ]; then
	format_posting $indentation "$losses_acct" $amount_offset >> "$out_file"
	printf "\$${capital_gains:1}\n" >> "$out_file"
      fi

      format_posting $indentation "$loan_acct" $amount_offset >> "$out_file"
      printf "$repayment $exchange_currency @ \$$fx_rate\n\n" >> "$out_file"
    else
      format_posting $indentation "$cash_acct" $amount_offset >> "$out_file"
      printf "\$-$repayment\n" >> "$out_file"
      format_posting $indentation "$loan_acct" $amount_offset >> "$out_file"
      printf "\$$repayment\n\n" >> "$out_file"
    fi
  fi
}
