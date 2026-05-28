CREATE   PROCEDURE dbo.SP_META_INCREMENT_WATERMARK (
    @EntityName VARCHAR(255)
)
AS
BEGIN
    -- This procedure reads the current state of the specified entity from dbo.meta_control_watermark, evaluates the increment_unit rule, 
    -- adds exactly 1 unit using a conditional DATEADD mechanism, and updates the watermark to the new position.

    -- Examples:
    -- Example 1: Advances 'STG_TRIPS' from '2020-01-31' to '2020-02-01'
    -- EXEC dbo.SP_META_INCREMENT_WATERMARK @EntityName = 'STG_TRIPS';

    -- Example 2: Advances 'WEATHER_NYC' from '2026-05-17 14:30:00.000' to '2026-05-17 15:30:00.000'
    -- EXEC dbo.SP_META_INCREMENT_WATERMARK @EntityName = 'WEATHER_NYC';

    -- Declare local variables to store current values
    DECLARE @CurrentUnit VARCHAR(50);
    DECLARE @CurrentDate DATE;
    DECLARE @CurrentTimestamp DATETIME2(3);

    -- 1. Fetch the current watermark specifications for the entity
    SELECT 
        @CurrentUnit = UPPER(TRIM(increment_unit)),
        @CurrentDate = last_extracted_date,
        @CurrentTimestamp = last_extracted_timestamp
    FROM dbo.meta_control_watermark
    WHERE entity_name = @EntityName;

    -- Safeguard: If the entity doesn't exist, stop and throw an informative error
    IF @CurrentUnit IS NULL
    BEGIN
        DECLARE @ErrorMsg VARCHAR(300) = CONCAT('Error: Entity ''', @EntityName, ''' was not found in dbo.meta_control_watermark.');
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END

    -- 2. Dynamically apply the 1-unit increment based on the unit type
    IF @CurrentUnit = 'DAY' AND @CurrentDate IS NOT NULL
    BEGIN
        UPDATE dbo.meta_control_watermark
        SET 
            last_extracted_date = DATEADD(day, 1, @CurrentDate),
            last_updated_at = SYSDATETIME()
        WHERE entity_name = @EntityName;
    END
    
    ELSE IF @CurrentUnit = 'HOUR' AND @CurrentTimestamp IS NOT NULL
    BEGIN
        UPDATE dbo.meta_control_watermark
        SET 
            last_extracted_timestamp = DATEADD(hour, 1, @CurrentTimestamp),
            last_updated_at = SYSDATETIME()
        WHERE entity_name = @EntityName;
    END
    
    ELSE IF @CurrentUnit = 'SECOND' AND @CurrentTimestamp IS NOT NULL
    BEGIN
        UPDATE dbo.meta_control_watermark
        SET 
            last_extracted_timestamp = DATEADD(second, 1, @CurrentTimestamp),
            last_updated_at = SYSDATETIME()
        WHERE entity_name = @EntityName;
    END
    
    ELSE
    BEGIN
        -- Error handling fallback for mismatched datatypes and configuration configurations
        DECLARE @MismatchMsg VARCHAR(300) = CONCAT('Error: The increment_unit (', @CurrentUnit, ') for entity ''', @EntityName, ''' does not match populated date/timestamp columns.');
        RAISERROR(@MismatchMsg, 16, 1);
    END
END;