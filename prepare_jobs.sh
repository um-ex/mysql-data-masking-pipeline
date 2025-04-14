#!/usr/bin/env bash
<<eof
# load .env
if [ -f .env ]; then
    echo "Loading environment variables from .env..."
    export $(grep -v '^#' .env | xargs)
else
    echo ".env file not found!"
    exit 1
fi
eof
LOG_FILE="error_log.txt"
JOB_LIST="job_list.txt"

# Ensure job list and log file exist
touch "$LOG_FILE"
touch "$JOB_LIST"

# Skip system databases
SKIP_DB="information_schema|mysql|performance_schema|sys|masking_meta"

# Get list of user databases
databases=$(sudo mysql --defaults-file=$HOME/.my.cnf -e "SHOW DATABASES;" 2>>"$LOG_FILE" | grep -vE "$SKIP_DB" | tail -n +2)

echo "Found databases:"
echo "$databases"

for db in $databases; do
    echo "📂 Accessing DB: $db"

    tables=$(sudo mysql --defaults-file=$HOME/.my.cnf -D"$db" -e "SHOW TABLES;" 2>>"$LOG_FILE")
    if [ $? -ne 0 ]; then
        echo "Error accessing tables in DB: $db — skipped" | tee -a "$LOG_FILE"
        continue
    fi

    tables=$(echo "$tables" | tail -n +2)

    for table in $tables; do
        job_line="${db}|${table}"

        # Check job_list.txt live (not from memory)
        if grep -Fxq "$job_line" "$JOB_LIST"; then
            echo "⏭️ Already exists: $job_line — skipping"
            continue
        fi

        echo "   → Checking table: $table"

        # Validate table access
        sudo mysql --defaults-file=$HOME/.my.cnf -D"$db" -e "DESCRIBE \`$table\`;" 2>>"$LOG_FILE" >/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to access: $job_line — skipped" | tee -a "$LOG_FILE"
            continue
        fi

        echo "$job_line" >> "$JOB_LIST"
        echo "Added: $job_line"
    done
done

echo "Done. job_list.txt now contains $(wc -l < "$JOB_LIST") jobs."
echo "Check $LOG_FILE for errors."
