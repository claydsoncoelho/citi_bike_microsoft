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
# META     }
# META   }
# META }

# MARKDOWN ********************

# This notebook will: 
# 
# 1. Create a DIM_DATE table in the bronze lakehouse.
# 2. Copy the table from bronze lakehouse to gold warehouse.
# 
# Example:
# LH_Bronze_Citi_Bike.DIM_DATE > WH_Gold_Citi_Bike.DIM_DATE

# MARKDOWN ********************

# # <mark>Change parameters here:</mark>

# PARAMETERS CELL ********************

# ==========================================
# Parameters
# ==========================================

BRONZE_LAKEHOUSE_NAME = None
GOLD_WAREHOUSE_NAME = None
TABLE_NAME = None
START_DATE = None
END_DATE = None

# BRONZE_LAKEHOUSE_NAME = "LH_Bronze_Citi_Bike"
# GOLD_WAREHOUSE_NAME = "WH_Gold_Citi_Bike"
# TABLE_NAME = "DIM_DATE"
# START_DATE = "2018-01-01"
# END_DATE = "2020-01-31"

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# # <mark>No more changes after this point.</mark>

# MARKDOWN ********************

# # Generate data in data frame.

# CELL ********************

from pyspark.sql.functions import expr, col, date_format, year, month, quarter
import com.microsoft.spark.fabric

bronze_table_name = f"{BRONZE_LAKEHOUSE_NAME}.{TABLE_NAME}"
gold_table_name = f"{GOLD_WAREHOUSE_NAME}.dbo.{TABLE_NAME}"

# ==========================================
# STEP 1: Generate the Date Dimension
# ==========================================
print(f"Generating date sequence from {START_DATE} to {END_DATE}...")

# Create the sequence array
df_spine = spark.range(1).select(
    expr(f"sequence(to_date('{START_DATE}'), to_date('{END_DATE}'), interval 1 day)").alias("date_day")
)

# Explode the array into individual rows and build schema
df_dim_date = df_spine.select(expr("explode(date_day)").alias("date")).select(
    date_format(col("date"), "yyyyMMdd").alias("dim_date_id"),
    col("date"),
    month(col("date")).alias("month"),
    year(col("date")).alias("year"),
    date_format(col("date"), "MMMM").alias("month_name"),
    quarter(col("date")).alias("quarter")
)


# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# # Save to Bronze Lakehouse

# CELL ********************

# ==========================================
# STEP 2: Save to Bronze Lakehouse
# ==========================================

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
BRONZE_SOURCE_PATH = f"abfss://{workspace_guid}@onelake.dfs.fabric.microsoft.com/{bronze_lakehouse_guid}/Tables/{TABLE_NAME}"

print(f'Trying to write to {BRONZE_SOURCE_PATH}')
df_dim_date.write.format("delta").mode("overwrite").save(BRONZE_SOURCE_PATH)
print(f'Table saved at {BRONZE_SOURCE_PATH}')

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# MARKDOWN ********************

# # Copy data to Gold Warehouse

# CELL ********************

# ==========================================
# STEP 3: Copy to Gold Warehouse
# ==========================================
print(f"Copying {bronze_table_name} to {gold_table_name}...")

df_dim_date.write \
    .mode("overwrite") \
    .synapsesql(gold_table_name)

print("Pipeline process completed successfully!")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
