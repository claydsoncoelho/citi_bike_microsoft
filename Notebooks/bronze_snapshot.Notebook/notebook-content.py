# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse_name": "",
# META       "default_lakehouse_workspace_id": ""
# META     },
# META     "warehouse": {}
# META   }
# META }

# MARKDOWN ********************

# This notebook will: 
# 
# 1. Read data from a source delta table in a bronze lakehouse.
# 2. Create a snapshot of the source table in the same bronze lakehouse (<table_name>_SNAPSHOT).
# 3. Copy the snapshot from bronze lakehouse to silver warehouse.
# 
# Example:
# LH_Bronze_Citi_Bike.TRIPS > LH_Bronze_Citi_Bike.TRIPS_SNAPSHOT

# MARKDOWN ********************

# # <mark>Change parameters here if running manually:</mark>

# PARAMETERS CELL ********************

# Parameters

BRONZE_LAKEHOUSE_NAME = None
SILVER_WAREHOUSE_NAME = None
SOURCE_TABLE_NAME = None
KEY_COLUMNS = None
TIMESTAMP_COLUMN_NAME = None    # The column name used for date filtering (e.g., "time_readable" or "starttime")
EXTRACT_TIMESTAMP_FROM = None   # Base start timestamp (e.g., "2019-04-30 23:59:50.8000")
EXTRACT_RANGE_IN_DAYS = None    # Number of days to extend the window forward (e.g., 60)


# BRONZE_LAKEHOUSE_NAME = "LH_Bronze_Citi_Bike"
# SILVER_WAREHOUSE_NAME = "WH_Silver_Citi_Bike"
# SOURCE_TABLE_NAME = "WEATHER_NYC" 
# KEY_COLUMNS = "time_readable"
# TIMESTAMP_COLUMN_NAME = "time_readable"   
# EXTRACT_TIMESTAMP_FROM = "2019-04-30 23:59:50.8000"   
# EXTRACT_RANGE_IN_DAYS = 60

# SOURCE_TABLE_NAME = "TRIPS" 
# KEY_COLUMNS = "starttime,bikeid"

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# Constants

# SCD columns
SCD_START_TIMESTAMP = 'SCD_START_TIMESTAMP'
SCD_END_TIMESTAMP = 'SCD_END_TIMESTAMP'
SCD_IS_CURRENT = 'SCD_IS_CURRENT'
SCD_KEY = 'SCD_KEY'

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# # <mark>No more changes after this point.</mark>

# MARKDOWN ********************

# ## Reading and preparing data

# CELL ********************

from pyspark.sql.functions import current_timestamp, lit, col, expr, concat_ws
from datetime import datetime, timedelta
import notebookutils
import time
import com.microsoft.spark.fabric

# =====================================================================
# Parameter Parsing & Verification
# =====================================================================
# If KEY_COLUMNS is passed as a comma-separated string, convert it to a list
if isinstance(KEY_COLUMNS, str):
    KEY_COLUMNS = [k.strip() for k in KEY_COLUMNS.split(",") if k.strip()]

# Fail-safe check
if not BRONZE_LAKEHOUSE_NAME or not SOURCE_TABLE_NAME or not KEY_COLUMNS:
    raise ValueError(f"Missing required parameters! Got: LH={BRONZE_LAKEHOUSE_NAME}, Table={SOURCE_TABLE_NAME}, Keys={KEY_COLUMNS}")

print(f"Successfully initialized processing for:")
print(f" - Lakehouse: {BRONZE_LAKEHOUSE_NAME}")
print(f" - Table:      {SOURCE_TABLE_NAME}")
print(f" - Key(s):     {KEY_COLUMNS}")

# Parse and compute sliding window boundaries if parameters are supplied
window_filtering_enabled = False
if EXTRACT_TIMESTAMP_FROM and EXTRACT_RANGE_IN_DAYS and TIMESTAMP_COLUMN_NAME:
    # Sanitize timestamp column name to match eventual underscore replacement
    TIMESTAMP_COLUMN_NAME = TIMESTAMP_COLUMN_NAME.replace(" ", "_")
    
    # Clean up and standardize the incoming string format
    # Replace ISO 'T' separator with a standard space, and strip the trailing UTC 'Z' if present
    clean_ts_str = str(EXTRACT_TIMESTAMP_FROM).replace("T", " ").replace("Z", "")
    # Strip any trailing microseconds/sub-seconds for stable parsing
    clean_ts_str = clean_ts_str.split(".")[0].strip()
    
    # 2. Parse the string reliably using a consistent pattern
    try:
        start_dt = datetime.strptime(clean_ts_str, "%Y-%m-%d %H:%M:%S")
    except ValueError as parse_err:
        raise ValueError(
            f"Failed to parse EXTRACT_TIMESTAMP_FROM string '{EXTRACT_TIMESTAMP_FROM}' "
            f"after sanitizing to '{clean_ts_str}'. Details: {parse_err}"
        )
        
    # 3. Compute upper bound boundary
    end_dt = start_dt + timedelta(days=int(EXTRACT_RANGE_IN_DAYS))
    
    EXTRACT_TIMESTAMP_TO = end_dt.strftime("%Y-%m-%d %H:%M:%S")
    window_filtering_enabled = True
    print(f"Sliding Window Optimized: Filtering between '{start_dt.strftime('%Y-%m-%d %H:%M:%S')}' and '{EXTRACT_TIMESTAMP_TO}'")

# Dynamically lookup the Lakehouse properties by name in the current workspace
bronze_lh_metadata = notebookutils.lakehouse.get(BRONZE_LAKEHOUSE_NAME)

# Extract the clean, matching GUIDs
# Dynamically gets the ID of whatever workspace (Dev or Test) this notebook is currently running in
# https://www.youtube.com/watch?v=WOYkLfXjtp8
workspace_guid = bronze_lh_metadata.workspaceId
# You could also get workspace_guid with the command below:
# workspace_guid = notebookutils.runtime.context.get("currentWorkspaceId")
bronze_lakehouse_guid = bronze_lh_metadata.id

# Construct absolute paths using the workspace ID and the names of your items
BRONZE_SOURCE_PATH = f"abfss://{workspace_guid}@onelake.dfs.fabric.microsoft.com/{bronze_lakehouse_guid}/Tables/{SOURCE_TABLE_NAME}"
# BRONZE_SNAPSHOT_PATH = f"abfss://{workspace_guid}@onelake.dfs.fabric.microsoft.com/{bronze_lakehouse_guid}/Tables/{SOURCE_TABLE_NAME}_SNAPSHOT"
silver_table_name = f"{SILVER_WAREHOUSE_NAME}.dbo.{SOURCE_TABLE_NAME}_SNAPSHOT"

print(f"Source Path: {BRONZE_SOURCE_PATH}")
print(f"Target Warehouse Table: {silver_table_name}")

# Read latest Bronze batch (using path instead of table name)
df_bronze = spark.read.format("delta").load(BRONZE_SOURCE_PATH)

# Filtering only the first 3 lines for testing
# df_bronze = df_bronze.limit(3)

# Rename all columns: replace spaces with underscores
df_bronze = df_bronze.toDF(*[c.replace(" ", "_") for c in df_bronze.columns])

# Sanitize KEY_COLUMNS to match the renamed columns
KEY_COLUMNS = [k.replace(" ", "_") for k in KEY_COLUMNS]

# Apply window optimization to the source data stream
if window_filtering_enabled:
    df_bronze = df_bronze.filter(
        (col(TIMESTAMP_COLUMN_NAME) >= lit(EXTRACT_TIMESTAMP_FROM)) & 
        (col(TIMESTAMP_COLUMN_NAME) <= lit(EXTRACT_TIMESTAMP_TO))
    )
    print(f"Optimized Source Rows to process within window: {df_bronze.count()}")

# Check if the Warehouse snapshot table exists and has the history schema
try:
    df_history = spark.read.format("com.microsoft.spark.sqlanalytics").synapsesql(silver_table_name)
    table_exists = True
    has_scd_schema = SCD_KEY in df_history.columns
except Exception as e:
    table_exists = False
    has_scd_schema = False

print(f'table_exists: {table_exists}')
print(f'has_scd_schema: {has_scd_schema}')
print(f'df_history.isEmpty(): {df_history.isEmpty()}')

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Initial and Delta load

# CELL ********************

# =====================================================================
# SYSTEM PATH A: Initial Load (Or Empty Table Deployed via Git)
# =====================================================================
if not table_exists or not has_scd_schema or df_history.isEmpty():
    print("Initializing snapshot table directly in the Silver Warehouse...")
    
    ms_timestamp = int(time.time() * 1000)
    scd_key = concat_ws("-", *[col(c).cast("string") for c in KEY_COLUMNS], lit(ms_timestamp).cast("string"))

    df_initial = df_bronze.withColumn(SCD_KEY, scd_key) \
                          .withColumn(SCD_START_TIMESTAMP, current_timestamp()) \
                          .withColumn(SCD_END_TIMESTAMP, lit(None).cast("timestamp")) \
                          .withColumn(SCD_IS_CURRENT, lit(True))

    # Write the initial state directly to the Warehouse
    df_initial.write \
        .format("com.microsoft.spark.sqlanalytics") \
        .option("overwriteMode", "REGULAR") \
        .mode("overwrite") \
        .synapsesql(silver_table_name)
        
    print("Warehouse snapshot table initialized successfully.")

# =====================================================================
# SYSTEM PATH B: Incremental SCD Type 2 Update
# =====================================================================
else:
    print("Performing Window-Optimized SCD Type 2 via Warehouse Overwrite...")

    # Partition history to isolate older records from processing entirely
    if window_filtering_enabled:
        # Protect and isolate all historical rows outside the specified window boundaries
        df_history_outside_window = df_history.filter(
            (col(TIMESTAMP_COLUMN_NAME) < lit(EXTRACT_TIMESTAMP_FROM)) | 
            (col(TIMESTAMP_COLUMN_NAME) > lit(EXTRACT_TIMESTAMP_TO))
        )
        # Isolate target rows inside the window for active evaluation
        df_history_inside_window = df_history.filter(
            (col(TIMESTAMP_COLUMN_NAME) >= lit(EXTRACT_TIMESTAMP_FROM)) & 
            (col(TIMESTAMP_COLUMN_NAME) <= lit(EXTRACT_TIMESTAMP_TO))
        )
        print(f"Isolated {df_history_outside_window.count()} rows outside comparison boundaries.")
    else:
        df_history_outside_window = spark.createDataFrame([], df_history.schema)
        df_history_inside_window = df_history

    print(f"df_history_outside_window.count(): {df_history_outside_window.count()}")
    print(f"df_history_inside_window.count(): {df_history_inside_window.count()}")
    
    # Isolate active and historical records from the Warehouse
    df_history_inactive = df_history_inside_window.filter(col(SCD_IS_CURRENT) == False)
    df_history_active = df_history_inside_window.filter(col(SCD_IS_CURRENT) == True)
    
    columns_to_track = [c for c in df_bronze.columns if c not in KEY_COLUMNS]

    # Map incoming Bronze data against currently active Warehouse records
    df_comparison = df_bronze.alias("src").join(
        df_history_active.alias("tgt"),
        KEY_COLUMNS,
        "left"
    )

    # Dynamic change condition
    change_condition = None
    for c in columns_to_track:
        condition = ~(col(f"src.{c}").eqNullSafe(col(f"tgt.{c}")))
        change_condition = condition if change_condition is None else (change_condition | condition)

    any_key_null = col(f"tgt.{KEY_COLUMNS[0]}").isNull()

    # 1. Brand New Records (Exist in Bronze, not in Warehouse active history)
    df_new_records = df_comparison.filter(any_key_null).select("src.*")
    ms_timestamp = int(time.time() * 1000)
    df_new_scd = df_new_records.withColumn(SCD_KEY, concat_ws("-", *[col(c).cast("string") for c in KEY_COLUMNS], lit(ms_timestamp).cast("string"))) \
                               .withColumn(SCD_START_TIMESTAMP, current_timestamp()) \
                               .withColumn(SCD_END_TIMESTAMP, lit(None).cast("timestamp")) \
                               .withColumn(SCD_IS_CURRENT, lit(True))

    # 2. Changed Records - Part A: Create the New Active Rows
    df_changed_records = df_comparison.filter(~any_key_null & change_condition).select("src.*")
    df_changed_new_active = df_changed_records.withColumn(SCD_KEY, concat_ws("-", *[col(c).cast("string") for c in KEY_COLUMNS], lit(ms_timestamp + 1).cast("string"))) \
                                              .withColumn(SCD_START_TIMESTAMP, current_timestamp()) \
                                              .withColumn(SCD_END_TIMESTAMP, lit(None).cast("timestamp")) \
                                              .withColumn(SCD_IS_CURRENT, lit(True))

    # 3. Changed Records - Part B: Expire the Old Active Rows
    df_changed_tgt = df_comparison.filter(~any_key_null & change_condition).select("tgt.*")
    df_changed_expired = df_changed_tgt.withColumn(SCD_IS_CURRENT, lit(False)) \
                                       .withColumn(SCD_END_TIMESTAMP, current_timestamp())

    # 4. Unchanged Active Records (Keep as-is)
    df_unchanged_active = df_comparison.filter(~any_key_null & ~change_condition).select("tgt.*")

    print(f"Metrics: {df_new_records.count()} new records, {df_changed_records.count()} updated records.")

    # Reconstruct full history matching the exact original target schema column order
    final_columns = df_history_inside_window.columns

    # df_window_final will be the union of:
    # df_history_inactive   - All old inactive records.
    # df_unchanged_active   - All old active records that were not changed.
    # df_changed_expired    - All old active records that were changed and expired (old value).
    # df_changed_new_active - All old active records that were changed and are not expired (new value). 
    # df_new_scd            - All new records.
    
    # Union everything evaluated within the window
    df_window_final = df_history_inactive.select(final_columns) \
        .unionByName(df_unchanged_active.select(final_columns)) \
        .unionByName(df_changed_expired.select(final_columns)) \
        .unionByName(df_changed_new_active.select(final_columns)) \
        .unionByName(df_new_scd.select(final_columns))

    # Safely append the untouched older historical rows back into the main matrix 
    if window_filtering_enabled:
        df_final = df_window_final.unionByName(df_history_outside_window.select(final_columns))
    else:
        df_final = df_window_final

    # Completely overwrite the warehouse table with the updated history matrix
    df_final.write \
        .format("com.microsoft.spark.sqlanalytics") \
        .option("overwriteMode", "REGULAR") \
        .mode("overwrite") \
        .synapsesql(silver_table_name)

    print("Warehouse snapshot updated successfully!")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Copy snapshot from Lakehouse to Warehouse

# CELL ********************

# print(f'Trying to read from {BRONZE_SNAPSHOT_PATH}')
# # Read latest Bronze batch (using path instead of table name)
# df_target = spark.read.format("delta").load(BRONZE_SNAPSHOT_PATH)
# print(f'Successfully read from {BRONZE_SNAPSHOT_PATH}')

# silver_table_name = f"{SILVER_WAREHOUSE_NAME}.dbo.{SOURCE_TABLE_NAME}_SNAPSHOT"

# print(f"Copying to {silver_table_name}...")
# df_target.write \
#     .format("com.microsoft.spark.sqlanalytics") \
#     .option("overwriteMode", "REGULAR") \
#     .mode("overwrite") \
#     .synapsesql(silver_table_name)

# print("Pipeline process completed successfully!")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# spark.sql("""
#     UPDATE LH_Bronze_Citi_Bike.WEATHER_NYC
#     SET CITY_NAME = 'New York'
#     WHERE TIME_READABLE = '2016-07-05 22:30:36.000'
# """)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# df = spark.sql("""
#     SELECT * FROM LH_Bronze_Citi_Bike.WEATHER_NYC
#     WHERE TIME_READABLE = '2016-07-05 22:30:36.000'
# """)

# display(df)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
