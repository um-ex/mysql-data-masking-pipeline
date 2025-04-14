#!/usr/bin/bash

# load .env
<<eof
if [ -f .env ]; then
    echo "Loading environment variables from .env..."
    export $(grep -v '^#' .env | xargs)
else
    echo ".env file not found!"
    exit 1
fi
eof
#start_time=$(date +%s)

echo "Step 1: Preparing job list..."
./prepare_jobs.sh

echo "Step 2: Running jobs in parallel..."
cat job_list.txt | parallel -j 4 ./process_single.sh {}

echo "Step 3: Merging results..."
cat lookup_parts/*.txt > lookup_data.txt

echo "Step 4: Importing into MySQL..."
sudo mysql --defaults-file=$HOME/.my.cnf --local-infile=1 <<EOF
CREATE DATABASE IF NOT EXISTS masking_meta;
USE masking_meta;
DROP TABLE IF EXISTS masking_lookup;
CREATE TABLE masking_lookup (
    db_name VARCHAR(255),
    table_name VARCHAR(255),
    column_name VARCHAR(255),
    data_type VARCHAR(255),
    is_primary_key BOOLEAN DEFAULT 0,
    total_rows BIGINT,
    to_mask BOOLEAN DEFAULT 0,
    PRIMARY KEY (db_name, table_name, column_name)
);
LOAD DATA LOCAL INFILE 'lookup_data.txt'
INTO TABLE masking_lookup
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n'
(db_name, table_name, column_name, data_type, is_primary_key, total_rows, to_mask);
EOF


echo "Step 5: Exporting to CSV..."
if [ ! -f lookup_data.txt ]; then
    echo "Error: lookup_data.txt not found. Cannot export to CSV."
    exit 1
fi

csv_file="lookup_data.csv"
{
    echo "db_name,table_name,column_name,data_type,is_primary_key,total_rows,to_mask"
    awk -F'\t' 'BEGIN {OFS=","} {print $1,$2,$3,$4,$5,$6,$7}' lookup_data.txt
} > "$csv_file"

echo "CSV file '$csv_file' created."


<<eof
end_time=$(date +%s)
runtime=$((end_time - start_time))
echo "All done in $runtime seconds."
eof