#!/bin/bash

# Load .env file if present
#if [ -f .env ]; then
#    echo "Loading environment variables from .env..."
#    export $(grep -v '^#' .env | xargs)
#else
#    echo ".env file not found!"
#    exit 1
#fi

# ========== Config ==========
input="$1"
LOG_DIR="logs"
PROCESSED_LOG="$LOG_DIR/processed.log"
FAILED_LOG="$LOG_DIR/failed.log"
LOOKUP_DIR="lookup_parts"
TIMEOUT=60   # seconds
TEST_MODE=false  # Set to true for dry run (no queries)

# ========== Parse input ==========
db=$(echo "$input" | cut -d'|' -f1)
table=$(echo "$input" | cut -d'|' -f2)

# ========== Create directories ==========
mkdir -p "$LOOKUP_DIR" "$LOG_DIR"

# ========== Skip if already processed ==========
if grep -qxF "$input" "$PROCESSED_LOG" 2>/dev/null; then
  echo "Skipping already processed: $db.$table"
  exit 0
fi

echo "Processing: $db.$table"

# ========== Get Primary Keys ==========
pk_cols=$(timeout $TIMEOUT sudo mysql --defaults-file="$HOME/.my.cnf" -N -D "$db" -e "
  SELECT COLUMN_NAME
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = '$table' AND COLUMN_KEY = 'PRI';
") 2>/dev/null

if [ $? -ne 0 ]; then
  echo "Failed to fetch primary key for $db.$table" | tee -a "$FAILED_LOG"
  exit 1
fi

pk_cols_csv=$(echo "$pk_cols" | tr '\n' ',' | sed 's/,$//')

# ========== Get Row Count ==========
total_rows=$(timeout $TIMEOUT sudo mysql --defaults-file="$HOME/.my.cnf" -N -D "$db" -e "
  SELECT COUNT(*) FROM \`$table\`;
") 2>/dev/null

if [ $? -ne 0 ]; then
  echo "Failed to get row count for $db.$table" | tee -a "$FAILED_LOG"
  exit 1
fi

# ========== Fetch Metadata ==========
if [ "$TEST_MODE" = true ]; then
  echo "[TEST MODE] Would fetch metadata for $db.$table"
else
  timeout $TIMEOUT sudo mysql --defaults-file="$HOME/.my.cnf" -D "$db" -e "
    SELECT 
        '$db',
        '$table',
        COLUMN_NAME,
        DATA_TYPE,
        CASE WHEN FIND_IN_SET(COLUMN_NAME, '$pk_cols_csv') > 0 THEN 1 ELSE 0 END AS is_primary_key,
        $total_rows AS total_rows,
        CASE 
            WHEN LOWER(COLUMN_NAME) REGEXP 'ssn|email|address|street|ip(_|)?address|country|state|zip(_|)?code|zipcode|(^|_)name($|_)|first(_|)?name|fname|name_of_|username|phone|phone(_|)?no|phone(_|)?number|mobile|mobile(_|)?no|mobile(_|)?number'
            THEN 1 
            ELSE 0 
        END AS to_mask

    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = '$table'
    AND DATA_TYPE IN ('int','varchar','text','char','tinytext','mediumtext','longtext','bigint','date','decimal','float','double');
  " | tail -n +2 > "$LOOKUP_DIR/${db}_${table}.txt" 2>/dev/null

  if [ $? -ne 0 ]; then
    echo "Failed to write metadata for $db.$table" | tee -a "$FAILED_LOG"
    exit 1
  fi
fi

# ========== Log processed ==========
echo "$input" >> "$PROCESSED_LOG"
echo "Done: $db.$table"
