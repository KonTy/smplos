#!/bin/bash
# EWW calendar data -- outputs single-line JSON for current month
# {"year","month","month_name","days","today","first_dow"}

year=$(date +%Y)
month=$(date +%-m)
month_name=$(date +%B)
today=$(date +%-d)
days=$(cal "$month" "$year" | awk 'NF {NDAYS=$NF}; END {print NDAYS}')
# Day of week for the 1st (0=Sun, 1=Mon, ... 6=Sat)
first_dow=$(date -d "$year-$(printf '%02d' "$month")-01" +%w 2>/dev/null || \
            date -j -f "%Y-%m-%d" "$year-$(printf '%02d' "$month")-01" +%w 2>/dev/null || echo 0)

printf '{"year":"%s","month":"%s","month_name":"%s","days":"%s","today":"%s","first_dow":"%s"}\n' \
  "$year" "$month" "$month_name" "$days" "$today" "$first_dow"
