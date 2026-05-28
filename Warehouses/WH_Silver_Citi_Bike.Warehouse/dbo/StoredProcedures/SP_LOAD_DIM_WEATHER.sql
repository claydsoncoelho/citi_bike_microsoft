CREATE PROCEDURE dbo.SP_LOAD_DIM_WEATHER
AS
BEGIN

    -- Declare local variables
    DECLARE @CurrentTimestamp DATETIME2(3);

    -- Get watermark for this dim
    SELECT @CurrentTimestamp = WH_Control.dbo.fn_meta_get_watermark('DIM_WEATHER');

    -- If @CurrentTimestamp is null then set 1900-01-01 00:00:00.000
    IF @CurrentTimestamp IS NULL
    BEGIN
        SET @CurrentTimestamp = '1900-01-01 00:00:00.000';
        PRINT('DIM_WEATHER - Initializing @CurrentTimestamp to 1900-01-01 00:00:00.000. No watermark found.');
    END
    ELSE
    BEGIN
        PRINT('DIM_WEATHER - Watermark found: ' + CAST(@CurrentTimestamp AS NVARCHAR(50)));
        PRINT('Loading data from ' + CAST(@CurrentTimestamp AS NVARCHAR(50)) + '.');
    END

    -- Merge Silver table into Gold table
    MERGE WH_Gold_Citi_Bike.dbo.DIM_WEATHER AS Target
    USING (
        SELECT 
            CONCAT(CITY_ID, '_', FORMAT(TIME_READABLE, 'yyyyMMddHHmmss')) AS SCD_DIM_WEATHER_ID,
            DATE_READABLE,
            TIME_READABLE,
            COUNTRY,
            CITY_NAME,
            WEATHER_MAIN,
            WEATHER_DETAIL,
            TEMPERATURE_CELSIUS,
            HUMIDITY,
            WIND_SPEED,
            CITY_LATITUDE,
            CAST(CITY_LAT_BUCKET AS INT) AS CITY_LAT_BUCKET,
            CITY_LONGITUDE,
            CAST(CITY_LON_BUCKET AS INT) AS CITY_LON_BUCKET,
            CITY_LOCATION,
            TEMPERATURE_KELVIN,
            PRESSURE,
            WIND_DEG,
            CITY_ID,
            CITY_FINDNAME,
            TIME_READABLE AS SCD_VALID_FROM,
            CAST(NULL AS DATETIME2(3)) AS SCD_VALID_TO,
            'Y' AS SCD_CURRENT_FLAG
        FROM dbo.INT_DIM_WEATHER
        WHERE TIME_READABLE > @CurrentTimestamp
    ) AS Source
    -- Match records on the natural unique key combination
    ON (Target.CITY_ID = Source.CITY_ID AND Target.TIME_READABLE = Source.TIME_READABLE)
    
    -- 1. IF MATCHED: Update the existing record if any weather attributes changed
    WHEN MATCHED AND (
        Target.WEATHER_MAIN        <> Source.WEATHER_MAIN OR
        Target.WEATHER_DETAIL      <> Source.WEATHER_DETAIL OR
        Target.TEMPERATURE_CELSIUS <> Source.TEMPERATURE_CELSIUS OR
        Target.HUMIDITY            <> Source.HUMIDITY OR
        Target.WIND_SPEED          <> Source.WIND_SPEED
    ) THEN 
        UPDATE SET 
            Target.WEATHER_MAIN        = Source.WEATHER_MAIN,
            Target.WEATHER_DETAIL      = Source.WEATHER_DETAIL,
            Target.TEMPERATURE_CELSIUS = Source.TEMPERATURE_CELSIUS,
            Target.HUMIDITY            = Source.HUMIDITY,
            Target.WIND_SPEED          = Source.WIND_SPEED,
            Target.TEMPERATURE_KELVIN  = Source.TEMPERATURE_KELVIN,
            Target.PRESSURE            = Source.PRESSURE,
            Target.WIND_DEG            = Source.WIND_DEG,
            -- Update tracking metadata if code rerun changes logic
            Target.SCD_DIM_WEATHER_ID  = Source.SCD_DIM_WEATHER_ID

    -- 2. IF NOT MATCHED: Insert the completely new record
    WHEN NOT MATCHED THEN
        INSERT (
            SCD_DIM_WEATHER_ID,
            DATE_READABLE,
            TIME_READABLE,
            COUNTRY,
            CITY_NAME,
            WEATHER_MAIN,
            WEATHER_DETAIL,
            TEMPERATURE_CELSIUS,
            HUMIDITY,
            WIND_SPEED,
            CITY_LATITUDE,
            CITY_LAT_BUCKET,
            CITY_LONGITUDE,
            CITY_LON_BUCKET,
            CITY_LOCATION,
            TEMPERATURE_KELVIN,
            PRESSURE,
            WIND_DEG,
            CITY_ID,
            CITY_FINDNAME,
            SCD_VALID_FROM,
            SCD_VALID_TO,
            SCD_CURRENT_FLAG
        )
        VALUES (
            Source.SCD_DIM_WEATHER_ID,
            Source.DATE_READABLE,
            Source.TIME_READABLE,
            Source.COUNTRY,
            Source.CITY_NAME,
            Source.WEATHER_MAIN,
            Source.WEATHER_DETAIL,
            Source.TEMPERATURE_CELSIUS,
            Source.HUMIDITY,
            Source.WIND_SPEED,
            Source.CITY_LATITUDE,
            Source.CITY_LAT_BUCKET,
            Source.CITY_LONGITUDE,
            Source.CITY_LON_BUCKET,
            Source.CITY_LOCATION,
            Source.TEMPERATURE_KELVIN,
            Source.PRESSURE,
            Source.WIND_DEG,
            Source.CITY_ID,
            Source.CITY_FINDNAME,
            Source.SCD_VALID_FROM,
            Source.SCD_VALID_TO,
            Source.SCD_CURRENT_FLAG
        );

    PRINT('DIM_WEATHER - Merge statement finished.');

    -- Update wartermark if necessary
    SELECT @CurrentTimestamp = MAX(TIME_READABLE) FROM WH_Silver_Citi_Bike.dbo.WEATHER_NYC_SNAPSHOT;

    EXEC WH_Control.dbo.SP_META_UPDATE_WATERMARK 
            @EntityName = 'DIM_WEATHER', 
            @LastExtractedDate = NULL, 
            @LastExtractedTimestamp = @CurrentTimestamp, 
            @IncrementUnit = 'SECOND';

END;