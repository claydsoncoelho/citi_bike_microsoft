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


# BRONZE_LAKEHOUSE_NAME = "LH_Bronze_Citi_Bike"
# SILVER_WAREHOUSE_NAME = "WH_Silver_Citi_Bike"
# SOURCE_TABLE_NAME = "WEATHER_NYC" 
# KEY_COLUMNS = "time_readable"

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
from delta.tables import DeltaTable
import com.microsoft.spark.fabric
import sempy.fabric as fabric
import notebookutils
import time

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

print(f'Trying to read from {BRONZE_SOURCE_PATH}')
# 2. Read latest Bronze batch (using path instead of table name)
df_bronze = spark.read.format("delta").load(BRONZE_SOURCE_PATH)
print(f'Successfully read from {BRONZE_SOURCE_PATH}')

# Filtering only the first 3 lines for testing
# df_bronze = df_bronze.limit(3)

# Rename all columns: replace spaces with underscores
df_bronze = df_bronze.toDF(*[c.replace(" ", "_") for c in df_bronze.columns])

# Sanitize KEY_COLUMNS to match the renamed columns
KEY_COLUMNS = [k.replace(" ", "_") for k in KEY_COLUMNS]

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Initial and Delta load

# CELL ********************

# 3. Handle Initial Load
# Use spark.catalog.tableExists with a direct file system check
if not notebookutils.fs.exists(BRONZE_SNAPSHOT_PATH):
    print("Initial load...")
    # scd_key_must be unique, so we need to concatenate the KEY_COLUMNS with the timestamp in milliseconds format
    ms_timestamp = int(time.time() * 1000) # Use time.time() for consistency with the merge logic
    scd_key = concat_ws("-", *[col(c).cast("string") for c in KEY_COLUMNS], lit(ms_timestamp).cast("string"))

    df_bronze.withColumn(SCD_KEY, scd_key) \
             .withColumn(SCD_START_TIMESTAMP, current_timestamp()) \
             .withColumn(SCD_END_TIMESTAMP, lit(None).cast("timestamp")) \
             .withColumn(SCD_IS_CURRENT, lit(True)) \
             .write.format("delta").mode("overwrite").save(BRONZE_SNAPSHOT_PATH)
    print("Table loaded.")
else:
    print("Performing Delta Merge SCD Type 2...")
    target_table = DeltaTable.forPath(spark, BRONZE_SNAPSHOT_PATH)
    df_silver_current = spark.read.format("delta").load(BRONZE_SNAPSHOT_PATH).filter(f"{SCD_IS_CURRENT} = true")
    columns_to_track = [c for c in df_bronze.columns if c not in KEY_COLUMNS]

    # 4. Identify UPDATES AND NEW RECORDS
    # Use a Left Join to keep everything in Bronze
    df_comparison = df_bronze.alias("src").join(
        df_silver_current.alias("tgt"),
        KEY_COLUMNS,
        "left"
    )

    # Create the dynamic SQL string for changes
    change_condition = None
    for c in columns_to_track:
        condition = ~(col(f"src.{c}").eqNullSafe(col(f"tgt.{c}")))
        change_condition = condition if change_condition is None else (change_condition | condition)

    # Check any key column is null to detect new records
    # (if the join missed, ALL tgt key columns will be null)
    any_key_null = col(f"tgt.{KEY_COLUMNS[0]}").isNull()

    # A. New Records: Key exists in Bronze but not in Silver
    df_new_records = df_comparison.filter(any_key_null).select("src.*")

    # B. Changed Records: Key exists in both, but values differ
    df_changed_records = df_comparison.filter(
        ~any_key_null & change_condition
    ).select("src.*")

    # Capture counts for logging
    new_count = df_new_records.count()
    changed_count = df_changed_records.count()
    print(f"Metrics: {new_count} new records, {changed_count} updated records.")

    df_updates = df_new_records.unionByName(df_changed_records)

    # .where(" OR ".join([f"src.{c} <=> tgt.{c}" for c in columns_to_track]))
    # This is a dynamic filter. Instead of hard-coding every column name, it generates a long string of comparisons. 
    # If your table has columns like temperature and humidity, the code generates:
    # WHERE src.temperature != tgt.temperature OR src.humidity != tgt.humidity

    # 5. Prepare Staged Data

    # mergeKey is a concatenation of all key columns
    # concat_ws uses a separator unlikely to appear in data: ||
    merge_key_expr = concat_ws("||", *[col(c).cast("string") for c in KEY_COLUMNS])

    # - mergeKey = NULL    → no match found → triggers whenNotMatchedInsert (new current row)
    # - mergeKey = KEY_COLUMNS → match found → triggers whenMatchedUpdate (expire old row)
    df_insert = df_updates.withColumn("mergeKey", lit(None).cast("string"))
    df_expire = df_updates.withColumn("mergeKey", merge_key_expr)

    staged_data = df_insert.unionByName(df_expire)

    # 6. Execute the Merge

    # Merge condition joins on all key columns
    merge_condition = " AND ".join(
        [f"tgt.{k} = src.{k}" for k in KEY_COLUMNS]
    )
    # mergeKey is used to identify which target rows to expire,
    # so it must match the same concatenation used in df_expire
    merge_key_match = " AND ".join(
        [f"CAST(tgt.{k} AS STRING)" for k in KEY_COLUMNS]
    )
    expire_condition = f"src.mergeKey = concat_ws('||', {', '.join([f'CAST(tgt.{k} AS STRING)' for k in KEY_COLUMNS])})"

    # scd_key_must be unique, so we need to concatenate the KEY_COLUMNS with the timestamp
    ms_timestamp = int(time.time() * 1000)
    scd_key = concat_ws("-", *[col(c).cast("string") for c in KEY_COLUMNS], lit(int(time.time() * 1000)).cast("string")) # Use time.time() for consistency with the initial load logic
    
    insert_values = {
        f"{SCD_KEY}": scd_key,
        f"{SCD_IS_CURRENT}": "true",
        f"{SCD_START_TIMESTAMP}": "current_timestamp()",
        f"{SCD_END_TIMESTAMP}": "null"
    }
    for k in KEY_COLUMNS:
        insert_values[k] = f"src.{k}"
    for c in columns_to_track:
        insert_values[c] = f"src.{c}"

    target_table.alias("tgt").merge(
        staged_data.alias("src"),
        expire_condition
    ).whenMatchedUpdate(
        condition=f"tgt.{SCD_IS_CURRENT} = true",
        set={
            f"{SCD_IS_CURRENT}": "false",
            f"{SCD_END_TIMESTAMP}": "current_timestamp()"
        }
    ).whenNotMatchedInsert(
        values=insert_values
    ).execute()

    print("Table updated successfully.")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# ## Copy snapshot from Lakehouse to Warehouse

# CELL ********************

print(f'Trying to read from {BRONZE_SNAPSHOT_PATH}')
# Read latest Bronze batch (using path instead of table name)
df_target = spark.read.format("delta").load(BRONZE_SNAPSHOT_PATH)
print(f'Successfully read from {BRONZE_SNAPSHOT_PATH}')

silver_table_name = f"{SILVER_WAREHOUSE_NAME}.dbo.{SOURCE_TABLE_NAME}_SNAPSHOT"

print(f"Copying to {silver_table_name}...")
df_target.write \
    .format("com.microsoft.spark.sqlanalytics") \
    .option("overwriteMode", "REGULAR") \
    .mode("overwrite") \
    .synapsesql(silver_table_name)

print("Pipeline process completed successfully!")

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
