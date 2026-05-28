-- Auto Generated (Do not modify) DF5D05103EC9D02A03DA35DC85F828E043C7C3DC225C5AC5FAB7EA08821497CB
 

CREATE VIEW dbo.INT_FACT_TRIPS_02 AS

WITH 
    source AS (SELECT * FROM dbo.INT_FACT_TRIPS_01),
    dim_weather as (select * from WH_Gold_Citi_Bike.dbo.DIM_WEATHER),
    dim_date as (select * from WH_Gold_Citi_Bike.dbo.DIM_DATE),

    -- This cte uses interger part of lat/lon and time of the day to try to find the precise weather.
    find_weather_first_try as (

        select
            source.bike_id,
            source.start_date,
            source.start_time,
            dim_weather_start_location.TIME_READABLE,
            dim_date.dim_date_id as dim_date_id_trip,
            dim_weather_start_location.SCD_DIM_WEATHER_ID,
            source.stop_time,
            source.trip_duration,
            source.trip_duration_seconds,
			source.trip_duration_min,
			source.trip_duration_min_range,
            source.period_of_day,
            source.trip_distance_meters,
            source.trip_distance_range,
            source.user_type,
            source.age,
            source.age_range,
            source.gender,
            source.birth_year,
            source.start_station_name,
            source.end_station_name,
            source.start_station_id,
            source.start_station_latitude,
            source.start_station_longitude,
            source.start_location,
            source.end_station_id,
            source.end_station_latitude,
            source.end_station_longitude,
            source.end_location,
            source.start_lat_bucket,
            source.start_lon_bucket,
            source.start_time_min,
            source.start_time_max

        from source

        left join dim_date on source.start_date = dim_date.date

        left join dim_weather dim_weather_start_location
            on dim_weather_start_location.CITY_LAT_BUCKET = source.start_lat_bucket  -- EQUALITY to improve performance
            and dim_weather_start_location.CITY_LON_BUCKET = source.start_lon_bucket -- EQUALITY to improve performance
            and dim_weather_start_location.DATE_READABLE = source.start_date -- EQUALITY to improve performance
            and dim_weather_start_location.TIME_READABLE between start_time_min and start_time_max
    ),

    weather_not_found as (

        select * from find_weather_first_try where SCD_DIM_WEATHER_ID is null

    ),

    find_weather_second_try as (

        select
            weather_not_found.bike_id,
            weather_not_found.start_date,
            weather_not_found.start_time,
            dim_weather_start_location.TIME_READABLE,
            dim_date.dim_date_id as dim_date_id_trip,
            dim_weather_start_location.SCD_DIM_WEATHER_ID,
            weather_not_found.stop_time,
            weather_not_found.trip_duration,
            weather_not_found.trip_duration_seconds,
			weather_not_found.trip_duration_min,
			weather_not_found.trip_duration_min_range,
            weather_not_found.period_of_day,
            weather_not_found.trip_distance_meters,
            weather_not_found.trip_distance_range,
            weather_not_found.user_type,
            weather_not_found.age,
            weather_not_found.age_range,
            weather_not_found.gender,
            weather_not_found.birth_year,
            weather_not_found.start_station_name,
            weather_not_found.end_station_name,
            weather_not_found.start_station_id,
            weather_not_found.start_station_latitude,
            weather_not_found.start_station_longitude,
            weather_not_found.start_location,
            weather_not_found.end_station_id,
            weather_not_found.end_station_latitude,
            weather_not_found.end_station_longitude,
            weather_not_found.end_location,
            weather_not_found.start_lat_bucket,
            weather_not_found.start_lon_bucket,
            weather_not_found.start_time_min,
            weather_not_found.start_time_max

        from weather_not_found

        left join dim_date on weather_not_found.start_date = dim_date.date

        left join dim_weather dim_weather_start_location
            on dim_weather_start_location.CITY_LAT_BUCKET = weather_not_found.start_lat_bucket  -- EQUALITY to improve performance
            and dim_weather_start_location.CITY_LON_BUCKET = weather_not_found.start_lon_bucket -- EQUALITY to improve performance
            and dim_weather_start_location.DATE_READABLE = weather_not_found.start_date -- EQUALITY to improve performance
    ),

    merge_both_results as (

        select * from find_weather_first_try where SCD_DIM_WEATHER_ID is not null
        union all
        select * from find_weather_second_try
    ),

    prepare_duplicated as (

        select
            bike_id,
            start_time,

            --Difference between the star_trip time and the weather time. 
            --Will be used to choose the best record in case of duplication
            -- the smaller the better.
            DATEDIFF(minute, start_time, TIME_READABLE) AS trip_weather_time_diff,
            start_date, 
            dim_date_id_trip,
            SCD_DIM_WEATHER_ID,
            stop_time,
            period_of_day,
            trip_distance_meters,
            trip_distance_range,
            user_type,
            age,
            age_range,
            gender,
            birth_year,
            start_station_name,
            end_station_name,
            trip_duration,
            trip_duration_seconds,
			trip_duration_min,
			trip_duration_min_range,
            start_station_id,
            start_station_latitude,
            start_station_longitude,
            start_lat_bucket,
            start_lon_bucket,
            start_location,
            end_station_id,
            end_station_latitude,
            end_station_longitude,
            end_location
        from merge_both_results
    ),

    enumerate_duplicated as (

        select
            *,
            row_number() over (
                partition by
                    bike_id,
                    start_time
                order by
                    trip_weather_time_diff asc
            ) as rn

        from prepare_duplicated
    ),

    remove_duplicated as (

        select * from enumerate_duplicated where rn = 1
    )      

SELECT * FROM remove_duplicated;