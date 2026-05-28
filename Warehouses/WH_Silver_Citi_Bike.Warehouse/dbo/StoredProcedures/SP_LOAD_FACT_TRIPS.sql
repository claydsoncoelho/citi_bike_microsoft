CREATE   PROCEDURE dbo.SP_LOAD_FACT_TRIPS
AS
BEGIN
    -- Declare local variables
    DECLARE @CurrentTimestamp DATETIME2(3);

    -- Get watermark for this fact table
    SELECT @CurrentTimestamp = WH_Control.dbo.fn_meta_get_watermark('FACT_TRIPS');

    -- If @CurrentTimestamp is null then set 1900-01-01 00:00:00.000
    IF @CurrentTimestamp IS NULL
    BEGIN
        SET @CurrentTimestamp = '1900-01-01 00:00:00.000';
        PRINT 'FACT_TRIPS - Initializing @CurrentTimestamp to 1900-01-01 00:00:00.000. No watermak found.';
    END
    ELSE
    BEGIN
        PRINT 'FACT_TRIPS - Watermark found: ' + CAST(@CurrentTimestamp AS NVARCHAR(50));
        PRINT 'Loading data from ' + CAST(@CurrentTimestamp AS NVARCHAR(50)) + '.';
    END

    -- Start a transaction to ensure data integrity
    BEGIN TRANSACTION;

    BEGIN TRY
        -- Step 1: Remove existing records for the dates we are about to load
        PRINT 'FACT_TRIPS - Trying to delete existing records if they match the same date range.';
        DELETE FROM WH_Gold_Citi_Bike.dbo.FACT_TRIPS
        WHERE DIM_DATE_ID_TRIP IN (
            SELECT DISTINCT dim_date_id_trip 
            FROM dbo.INT_FACT_TRIPS_02
            WHERE start_time > @CurrentTimestamp
        );
        PRINT 'FACT_TRIPS - Deletion process finished.';

        PRINT 'FACT_TRIPS - Inserting new records.';
        -- Step 2: Insert the newly aggregated records
        INSERT INTO WH_Gold_Citi_Bike.dbo.FACT_TRIPS (
            TRIP_COUNT,
            DIM_DATE_ID_TRIP,
            MAX_START_TIME,
            SCD_DIM_WEATHER_ID,
            TRIP_DURATION_MIN_RANGE,
            PERIOD_OF_DAY,
            TRIP_DISTANCE_RANGE,
            TRIP_DISTANCE_SUM_KM,
            USER_TYPE,
            AGE_RANGE,
            GENDER
        )
        SELECT
            COUNT(1) AS TRIP_COUNT,
            dim_date_id_trip AS DIM_DATE_ID_TRIP,
            MAX(start_time) AS MAX_START_TIME,
            SCD_DIM_WEATHER_ID,
            trip_duration_min_range AS TRIP_DURATION_MIN_RANGE,
            period_of_day AS PERIOD_OF_DAY,
            trip_distance_range AS TRIP_DISTANCE_RANGE,
            SUM(trip_distance_meters) / 1000.0 AS TRIP_DISTANCE_SUM_KM,
            user_type AS USER_TYPE,
            age_range AS AGE_RANGE,
            gender AS GENDER
        FROM dbo.INT_FACT_TRIPS_02
        WHERE start_time > @CurrentTimestamp
        GROUP BY 
            dim_date_id_trip,
            SCD_DIM_WEATHER_ID,
            trip_duration_min_range,
            period_of_day,
            trip_distance_range,
            user_type,
            age_range,
            gender;

        -- Commit the changes if everything succeeds
        COMMIT TRANSACTION;
        PRINT 'FACT_TRIPS loaded successfully.';

        -- Update wartermark if necessary
        SELECT @CurrentTimestamp = MAX(MAX_START_TIME) FROM WH_Gold_Citi_Bike.dbo.FACT_TRIPS;

        EXEC WH_Control.dbo.SP_META_UPDATE_WATERMARK 
            @EntityName = 'FACT_TRIPS', 
            @LastExtractedDate = NULL, 
            @LastExtractedTimestamp = @CurrentTimestamp, 
            @IncrementUnit = 'SECOND';

    END TRY
    BEGIN CATCH
        -- In Fabric, if an error happens inside the TRY block,
        -- we unconditionally roll back the transaction we opened on Line 6.
        ROLLBACK TRANSACTION;

        -- Raise the error up to your Fabric Data Pipeline orchestrator
        THROW;
    END CATCH;
END;