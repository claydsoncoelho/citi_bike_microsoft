-- Auto Generated (Do not modify) 5EA325FAC76F5CF6BF6ED4537D7BADB39A91171F7D8673FE1082302162D52D9A


CREATE   VIEW dbo.STG_WEATHER_NYC AS

WITH 
    source AS (
        SELECT * FROM WH_Silver_Citi_Bike.dbo.WEATHER_NYC_SNAPSHOT
    ),

    -- Step 1: Fix datatypes for all columns needed in the final output
    datatypes AS (
        SELECT 
            CAST(TIME_READABLE AS DATETIME2) AS TIME_READABLE,
            CAST(CITY_NAME AS VARCHAR(255)) AS CITY_NAME,
            CAST(COUNTRY AS VARCHAR(50)) AS COUNTRY,
            CAST(CITY_ID AS INT) AS CITY_ID,
            CAST(CITY_FINDNAME AS VARCHAR(255)) AS CITY_FINDNAME,
            CAST(CITY_LATITUDE AS DECIMAL(9,6)) AS CITY_LATITUDE,
            CAST(CITY_LONGITUDE AS DECIMAL(9,6)) AS CITY_LONGITUDE,
            CAST(WEATHER_DESCRIPTION AS VARCHAR(255)) AS WEATHER_DESCRIPTION,
            CAST(WEATHER_MAIN AS VARCHAR(100)) AS WEATHER_MAIN,
            CAST(TEMPERATURE AS FLOAT) AS TEMPERATURE,
            CAST(HUMIDITY AS INT) AS HUMIDITY,
            CAST(PRESSURE AS FLOAT) AS PRESSURE,
            CAST(WIND_SPEED AS FLOAT) AS WIND_SPEED,
            CAST(WIND_DEG AS FLOAT) AS WIND_DEG,
            CAST(METADATA_FILENAME AS VARCHAR(500)) AS METADATA_FILENAME,
            CAST(METADATA_FILE_ROW_NUMBER AS INT) AS METADATA_FILE_ROW_NUMBER,
            CAST(METADATA_FILE_LAST_MODIFIED AS DATETIME2) AS METADATA_FILE_LAST_MODIFIED,
            SCD_IS_CURRENT -- Keeping this from your SCD table just in case
        FROM source
        WHERE SCD_IS_CURRENT = 1 -- Usually, views like this only want the active records
    ),

    -- Step 2: Deduplicate (in case your SCD logic allowed multiple entries for one time)
    deduped_rows AS (
        SELECT 
            *,
            ROW_NUMBER() OVER (
                PARTITION BY TIME_READABLE 
                ORDER BY METADATA_FILE_LAST_MODIFIED DESC, METADATA_FILE_ROW_NUMBER DESC
            ) as row_num
        FROM datatypes
    ),

    -- Step 3: Final Logic and Geometry construction
    location_logic AS (
        SELECT
            TIME_READABLE,
            CITY_NAME,
            COUNTRY,
            CITY_ID,
            CITY_FINDNAME,
            CITY_LATITUDE,
            CITY_LONGITUDE,
            -- T-SQL CONCAT handles strings automatically
            CONCAT('POINT(', CAST(CITY_LONGITUDE AS VARCHAR(20)), ' ', CAST(CITY_LATITUDE AS VARCHAR(20)), ')') AS CITY_LOCATION,
            WEATHER_DESCRIPTION,
            WEATHER_MAIN,
            TEMPERATURE,
            HUMIDITY,
            PRESSURE,
            WIND_SPEED,
            WIND_DEG,
            METADATA_FILENAME,
            METADATA_FILE_ROW_NUMBER,
            METADATA_FILE_LAST_MODIFIED
        FROM deduped_rows
        WHERE row_num = 1
    )

SELECT * FROM location_logic;