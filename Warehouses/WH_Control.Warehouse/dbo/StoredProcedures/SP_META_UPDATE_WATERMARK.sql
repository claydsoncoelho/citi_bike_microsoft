CREATE   PROCEDURE dbo.SP_META_UPDATE_WATERMARK (
    @EntityName VARCHAR(255),
    @LastExtractedDate DATE,
    @LastExtractedTimestamp DATETIME2(3),
    @IncrementUnit VARCHAR(50)
)
AS
BEGIN
    -- Calling examples:
    -- For a daily grain pull
    -- EXEC dbo.SP_META_UPDATE_WATERMARK 'STG_TRIPS', '2020-01-31', NULL, 'DAY';

    -- For an hourly/sub-second grain pull
    -- EXEC dbo.SP_META_UPDATE_WATERMARK 'WEATHER_NYC', NULL, '2026-05-17 14:30:00.000', 'HOUR';

    -- Force uppercase on increment unit for consistency (DAY, HOUR, etc.)
    DECLARE @CleanUnit VARCHAR(50) = UPPER(TRIM(@IncrementUnit));

    MERGE dbo.meta_control_watermark AS Target
    USING (
        SELECT 
            @EntityName AS entity_name,
            @LastExtractedDate AS last_extracted_date,
            @LastExtractedTimestamp AS last_extracted_timestamp,
            @CleanUnit AS increment_unit
    ) AS Source
    ON (Target.entity_name = Source.entity_name)
    
    -- If entity exists, update the watermarks to the new position
    WHEN MATCHED THEN
        UPDATE SET 
            Target.last_extracted_date = Source.last_extracted_date,
            Target.last_extracted_timestamp = Source.last_extracted_timestamp,
            Target.increment_unit = Source.increment_unit,
            Target.last_updated_at = SYSDATETIME()

    -- If it's a new pipeline entity, insert it
    WHEN NOT MATCHED THEN
        INSERT (
            entity_name,
            last_extracted_date,
            last_extracted_timestamp,
            increment_unit,
            last_updated_at
        )
        VALUES (
            Source.entity_name,
            Source.last_extracted_date,
            Source.last_extracted_timestamp,
            Source.increment_unit,
            SYSDATETIME()
        );
END;