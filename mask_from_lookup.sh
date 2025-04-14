#!/usr/bin/env bash

set -e

# Constants
LOOKUP_FILE="lookup_data.csv"
BATCH_SIZE=5000
MAX_RETRIES=3
RETRY_DELAY=10
LOG_FILE="masking_log.txt"

# Start timer
start_time=$(date +%s)

# Generate lookup table
echo "Generating latest lookup table..."
bash ./run.sh

# Trap for graceful exit
trap "echo -e '\nScript interrupted. Cleaning up...'; pkill -P $$; exit 1" SIGINT SIGTERM

# Logger
log_message() {
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "$timestamp - $1" | tee -a "$LOG_FILE"
}

# Masking generators
generate_random_name() { 
  NAMES=(Alice Bob Charlie Diana Oliver Harry Lily Noah Adie Arthur James Amelia George Oscar Jack Evelyn Ellis Brian Paul Donald Kyle Jeremy Jesse Elijah Willie)
  echo "${NAMES[$RANDOM % ${#NAMES[@]}]}"
}
generate_random_email() { echo "$(tr -dc a-z0-9 </dev/urandom | head -c6)@cloudtech.com"; }
generate_random_phone() { printf "98%08d\n" $((RANDOM % 100000000)); }
generate_random_ssn()   { echo "$((100+RANDOM%900))-$((10+RANDOM%90))-$((1000+RANDOM%9000))"; }
generate_random_ip()    { echo "$((RANDOM%256)).$((RANDOM%256)).$((RANDOM%256)).$((RANDOM%256))"; }
generate_random_address() { echo "$((RANDOM%1000)) Fake Street"; }
generate_random_account() { echo "$((1000000000 + RANDOM % 999999999))"; }
generate_random_generic() { echo "MASKED_$(tr -dc A-Z0-9 </dev/urandom | head -c6)"; }
generate_random_dob()    { echo "$((RANDOM % 50 + 1970))-$(printf "%02d" $((RANDOM % 12 + 1)))-$(printf "%02d" $((RANDOM % 28 + 1)))"; }
generate_random_passport() { echo "P${RANDOM}${RANDOM}${RANDOM}${RANDOM}"; }
generate_random_driver_license() { echo "DL-${RANDOM}${RANDOM}${RANDOM}"; }
generate_random_credit_card() { echo "4${RANDOM}${RANDOM}${RANDOM}${RANDOM}${RANDOM}${RANDOM}${RANDOM}${RANDOM}"; }

# Detect type from column name
get_mask_type() {
  COL="$1"
  COL_LC=$(echo "$COL" | tr '[:upper:]' '[:lower:]')
  case "$COL_LC" in
    *name*) echo "name" ;;
    *email*) echo "email" ;;
    *phone*|*mobile*) echo "phone" ;;
    *ssn*) echo "ssn" ;;
    *ip*) echo "ip" ;;
    *address*|*street*) echo "address" ;;
    *account*) echo "account" ;;
    *dob*|*birth*) echo "dob" ;;
    *passport*) echo "passport" ;;
    *driver*license*) echo "driver_license" ;;
    *credit*card*) echo "credit_card" ;;
    *) echo "generic" ;;
  esac
}

# Mask batch of rows
mask_data_batch() {
  db="$1"
  table="$2"
  column="$3"
  pk_col="$4"
  start="$5"
  end="$6"

  type=$(get_mask_type "$column")

  for row_id in $(seq "$start" "$end"); do
    case "$type" in
      name) val=$(generate_random_name) ;;
      email) val=$(generate_random_email) ;;
      phone) val=$(generate_random_phone) ;;
      ssn) val=$(generate_random_ssn) ;;
      ip) val=$(generate_random_ip) ;;
      address) val=$(generate_random_address) ;;
      account) val=$(generate_random_account) ;;
      dob) val=$(generate_random_dob) ;;
      passport) val=$(generate_random_passport) ;;
      driver_license) val=$(generate_random_driver_license) ;;
      credit_card) val=$(generate_random_credit_card) ;;
      *) val=$(generate_random_generic) ;;
    esac

    success=false
    retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
      sudo mysql --defaults-file="$HOME/.my.cnf" -D "$db" -e "UPDATE $table SET $column='$val' WHERE $pk_col=$row_id;" 2>/dev/null
      if [ $? -eq 0 ]; then
        success=true
        break
      fi
      retry=$((retry + 1))
      log_message "Retry $retry: Failed to update $db.$table.$column for $pk_col=$row_id"
      sleep "$RETRY_DELAY"
    done

    if ! $success; then
      log_message "Failed to update $db.$table.$column after $MAX_RETRIES retries."
    else
      echo "[$db.$table] Masked $column for $pk_col=$row_id"
    fi
  done
}

# Main loop
log_message "Masking started..."

tail -n +2 "$LOOKUP_FILE" | while IFS=',' read -r db table column dtype pk_flag total_rows to_mask; do
  if [[ "$pk_flag" == "1" ]]; then
    log_message "Skipping $db.$table.$column (Primary Key)"
    continue
  fi

  if [[ "$to_mask" != "1" ]]; then
    log_message "Skipping $db.$table.$column (to_mask=0)"
    continue
  fi

  log_message "Masking $db.$table.$column"

  # Get actual PK column name for this table
  pk_col=$(tail -n +2 "$LOOKUP_FILE" | awk -F',' -v db="$db" -v tbl="$table" '$1 == db && $2 == tbl && $5 == 1 { print $3 }' | head -n 1)
  if [ -z "$pk_col" ]; then
    log_message "No PK column found for $db.$table. Skipping..."
    continue
  fi

  total_rows=$(sudo mysql --defaults-file="$HOME/.my.cnf" -D "$db" -e "SELECT COUNT(*) FROM $table;" -N)
  batches=$(( (total_rows + BATCH_SIZE - 1) / BATCH_SIZE ))

  for ((b=0; b<batches; b++)); do
    start=$((b * BATCH_SIZE + 1))
    end=$((start + BATCH_SIZE - 1))
    if [ "$end" -gt "$total_rows" ]; then end=$total_rows; fi
    echo "Batch $((b+1)) → $db.$table.$column rows $start to $end"
    mask_data_batch "$db" "$table" "$column" "$pk_col" "$start" "$end" &
  done

  wait
  log_message "Finished masking $db.$table.$column"
done

log_message "All masking operations complete."

runtime=$(( $(date +%s) - start_time ))
echo "Total time: $runtime seconds"
