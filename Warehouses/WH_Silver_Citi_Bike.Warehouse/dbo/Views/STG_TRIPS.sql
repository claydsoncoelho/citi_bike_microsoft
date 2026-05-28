-- Auto Generated (Do not modify) 1277CD2AD140516FA2AE615A4DE84393B4AC5A1A5ADB1928F633152DCB5178ED


CREATE VIEW dbo.STG_TRIPS AS

WITH 
    source AS (
        SELECT * FROM WH_Silver_Citi_Bike.dbo.TRIPS_SNAPSHOT
    ),

    parameters AS (
		SELECT 31 AS time_window
	),

    -- Step 1: Fix datatypes for all columns needed in the final output
    datatypes AS (
        SELECT 
            -- Trip Duration & Timestamps
            CAST(tripduration AS INT) AS trip_duration,
            CAST(starttime AS DATETIME2(3)) AS start_time,
            CAST(stoptime AS DATETIME2(3)) AS stop_time,
            
            -- Start Station Details
            CAST(CAST(start_station_id AS FLOAT) AS INT) AS start_station_id,
            CAST(start_station_name AS VARCHAR(255)) AS start_station_name,
            CAST(start_station_latitude AS DECIMAL(9,6)) AS start_station_latitude,
            CAST(start_station_longitude AS DECIMAL(9,6)) AS start_station_longitude,
            CAST('POINT(' + start_station_longitude + ' ' + start_station_latitude + ')' AS VARCHAR(255)) as start_location,
            
            -- End Station Details
            CAST(CAST(start_station_id AS FLOAT) AS INT) AS end_station_id,
            CAST(end_station_name AS VARCHAR(255)) AS end_station_name,
            CAST(end_station_latitude AS DECIMAL(9,6)) AS end_station_latitude,
            CAST(end_station_longitude AS DECIMAL(9,6)) AS end_station_longitude,
            CAST('POINT(' + end_station_longitude + ' ' + end_station_latitude + ')' AS VARCHAR(255)) as end_location,
            
            -- Bike & User Details
            CAST(bikeid AS INT) AS bike_id,
            CAST(usertype AS VARCHAR(50)) AS user_type,
            CAST(birth_year AS INT) AS birth_year,
            CAST(gender AS INT) AS gender, -- encoded as 0, 1, 2
            
            -- SCD System Metadata Columns
            CAST(SCD_START_TIMESTAMP AS DATETIME2(3)) AS scd_start_timestamp,
            CAST(SCD_END_TIMESTAMP AS DATETIME2(3)) AS scd_end_timestamp,
            CAST(SCD_IS_CURRENT AS INT) AS scd_is_current
        FROM source
        WHERE SCD_IS_CURRENT = 1 -- Filters out historical versions, showing only active rows
    ),

    -- Step 2: Deduplicate (in case your SCD logic allowed multiple entries for one time)
    deduped_rows AS (
        SELECT 
            *,
            ROW_NUMBER() OVER (
                PARTITION BY start_time, bike_id 
                ORDER BY scd_start_timestamp DESC 
            ) as row_num
        FROM datatypes
    ),

    add_columns AS (
        SELECT
            bike_id,
            start_time,
            -- Extracting date parte of the timestamp to improve joing performance.
            -- It is faster to joing with a specific date then a range of timestamps.
            CAST(start_time AS DATE) AS start_date,
            -- Range of timestamps to join with a specific period of the day
            dateadd(minute, - parameters.time_window, start_time) as start_time_min,
			dateadd(minute, + parameters.time_window, start_time) as start_time_max,
            -- Trip duration in time format
            trip_duration as trip_duration_seconds,
            CAST(round(trip_duration / 60,0) as int) as trip_duration_min,
            CAST(DATEADD(second, trip_duration, '1970-01-01 00:00:00') AS TIME(0)) AS trip_duration,
            CAST(FORMAT(start_time, 'yyyyMM') AS VARCHAR) AS start_time_year_month,
            -- Period of day
            CASE
                WHEN DATEPART(hour, start_time) BETWEEN 6 AND 11  THEN 'Morning'
                WHEN DATEPART(hour, start_time) BETWEEN 12 AND 17 THEN 'Afternoon'
                WHEN DATEPART(hour, start_time) BETWEEN 18 AND 20 THEN 'Evening'
                ELSE 'Night'
            END AS period_of_day,
            -- Trip distance in meters using Haversine Formula
            CASE 
                WHEN start_station_latitude = end_station_latitude AND start_station_longitude = end_station_longitude THEN 0
                ELSE (
                    6371000 * ACOS(
                        COS(RADIANS(start_station_latitude)) * 
                        COS(RADIANS(end_station_latitude)) * 
                        COS(RADIANS(end_station_longitude) - RADIANS(start_station_longitude)) + 
                        SIN(RADIANS(start_station_latitude)) * 
                        SIN(RADIANS(end_station_latitude))
                    )
                )
            END AS trip_distance_meters,
            -- Since we have only 2 wather stations in NYC with distinct inter lat/lon:
            -- 40.714272	-74.005966
            -- 43.000351	-75.499901
            -- We are rounding the lat/lon bucket to an integer
            CAST(round(start_station_latitude, 0) AS INT) as start_lat_bucket,
            CAST(round(start_station_longitude, 0) AS INT) as start_lon_bucket,
            -- Age
            DATEPART(year, start_time) - birth_year as age,
            gender as gender_code,
            -- Gender
            case
                gender when 1 then 'Male' when 2 then 'Female' else 'Unknown'
            end as gender,
            stop_time,
            start_station_id,
            start_station_name,
            start_station_latitude,
            start_station_longitude,
            start_location,
            end_station_id,
            end_station_name,
            end_station_latitude,
            end_station_longitude,
            end_location,
            user_type,
            birth_year,
            scd_start_timestamp, 
            scd_end_timestamp,
            scd_is_current
        FROM deduped_rows, parameters
        WHERE row_num = 1
    )

SELECT * FROM add_columns;