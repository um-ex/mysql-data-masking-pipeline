# MySQL Data Masking Pipeline
## Overview 
This project is a Bash-based MySQL data masking pipeline that identifies sensitive columns from multiple databases and replaces their values with masked data using generated random values. It is designed to help create sanitized versions of production databases for testing environments. 

## Phase 1: Metadata Extraction & Lookup Table Generation 
Scripts: run.sh, prepare_jobs.sh, process_single.sh

1. run.sh
    - Main entry point.
    - Calls prepare_jobs.sh to discover all databases/tables (excluding schemas).
    - Launces process_single.sh in parallel for each database|table.
    - Merges partial lookup files into:
        - lookup_data.txt (raw data)
        - lookup_data.csv (CSV for review/editing)
        - Also imports into masking_meta.masking_lookup MySQL table.
2. prepare_jobs.sh
    - Scans all MySQL databases.
    - Filters out system schemas like mysql, performance_schema, etc.
    - Generates job_list.txt with database|table entries for processing. 

3. process_single.sh
    - For each db|table, fetches:
        - Primary key(s)
        - Column metadata (name, type, nullable, etc.)
    - Detects columns suitable for masking (e.g., names, phones, emails).
    - Stores metadata into lookup_parts/ folder as db.table.txt files 

## Phase 2: Data Masking Based on Lookup Table 
Script: mask_from_lookup.sh
    - Reads the final lookup_data.csv or MySQL masking_lookup table.
    - Applies masking to specified columns (to_mask=1) using:
        - Randomized substitution (name/phone/email/generators)
        - Batch processing (e.g., 500-1000 rows per query)
        - Parallel execution for performance
        - Retry logic for safety

## Directory Structure

.
├── run.sh                   # Master pipeline controller
├── prepare_jobs.sh          # Discovers valid jobs (database|table)
├── process_single.sh        # Extracts table metadata into lookup parts
├── mask_from_lookup.sh      # Performs actual data masking
├── job_list.txt             # Generated list of jobs to process
├── lookup_parts/            # Intermediate metadata per table
├── lookup_data.txt          # Raw merged metadata
├── lookup_data.csv          # Editable CSV format for masking
└── logs/                    # Logs for each step (optional)
