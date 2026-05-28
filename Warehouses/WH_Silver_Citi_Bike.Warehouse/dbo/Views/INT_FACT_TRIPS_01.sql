-- Auto Generated (Do not modify) 52F95BAB3FE1B1A1D175D1D5E2CBE368F0BB3C57344F80D6D9371624E3194D1A
 

CREATE   VIEW dbo.INT_FACT_TRIPS_01 AS

WITH 
    source AS (
        SELECT * FROM dbo.STG_TRIPS
    ),

    prepare_filter as (
        select 
            -- Keys
            bike_id,
            start_time,

            -- Trip Duration & Timestamps
            start_date,
            start_time_min,
			start_time_max,
            stop_time,
            trip_duration_seconds,
			trip_duration_min,
            trip_duration,
			case
                when trip_duration_min between 0 and 10 then '0-10 min'
                when trip_duration_min between 11 and 20 then '11-20 min'
                when trip_duration_min between 21 and 30 then '21-30 min'
                when trip_duration_min between 31 and 40 then '31-40 min'
                when trip_duration_min between 41 and 50 then '41-50 min'
                else '50+'
            end as trip_duration_min_range,
            period_of_day,
			trip_distance_meters,

            -- Start Station Details
            start_lat_bucket,
            start_lon_bucket,
            start_station_id,
            start_station_name,
            start_station_latitude,
            start_station_longitude,
            start_location,
            
            -- End Station Details
            end_station_id,
            end_station_name,
            end_station_latitude,
            end_station_longitude,
            end_location,

            -- User Details
            user_type,
            birth_year,
            age,
			-- Age range
            case
                when age between 0 and 17
                then '0-17'
                when age between 18 and 24
                then '18-24'
                when age between 25 and 34
                then '25-34'
                when age between 35 and 44
                then '35-44'
                when age between 45 and 54
                then '45-54'
                when age between 55 and 64
                then '55-64'
                when age >= 65
                then '65+'
                else 'Unknown'
            end as age_range,
            gender_code,
            gender

        from source
    ), 

	stg_fact_01 as (
        select
            -- keys
            bike_id,
            start_time,

            -- Trip Duration & Timestamps
            start_date,
            start_time_min,
            start_time_max,
            stop_time,
            trip_duration_seconds,
			trip_duration_min,
            trip_duration,
			trip_duration_min_range,
            period_of_day,

            -- Trip distance in meters using Haversine Formula
            trip_distance_meters,
			case
                when trip_distance_meters between 0 and 1000 then '0-1 Km'
                when trip_distance_meters between 1001 and 2000 then '1-2 Km'
                when trip_distance_meters between 2001 and 3000 then '2-3 Km'
                when trip_distance_meters between 3001 and 4000 then '3-4 Km'
                when trip_distance_meters between 4001 and 5000 then '4-5 Km'
                else '5+'
            end as trip_distance_range,

            -- Start Station Details
            start_lat_bucket,
            start_lon_bucket,
            start_station_id,
            start_station_name,
            start_station_latitude,
            start_station_longitude,
            start_location,
            
            -- End Station Details
            end_station_id,
            end_station_name,
            end_station_latitude,
            end_station_longitude,
            end_location,

            -- User Details
            user_type,
            gender,
            birth_year,
			age_range, 
            age

        from prepare_filter
    )

SELECT * FROM stg_fact_01;