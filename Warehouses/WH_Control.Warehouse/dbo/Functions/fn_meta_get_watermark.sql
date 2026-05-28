CREATE   FUNCTION dbo.fn_meta_get_watermark (
    @EntityName VARCHAR(255)
)
RETURNS DATETIME2(3)
AS
BEGIN
    DECLARE @Watermark DATETIME2(3);
    DECLARE @Unit VARCHAR(50);

    -- Fetch the metadata tracking parameters for this specific entity
    SELECT 
        @Unit = UPPER(TRIM(increment_unit)),
        @Watermark = CASE 
            -- If it is configured at a Daily grain, convert the DATE to a DATETIME2(3)
            WHEN UPPER(TRIM(increment_unit)) = 'DAY' THEN CAST(last_extracted_date AS DATETIME2(3))
            -- For HOUR or SECOND grains, return the timestamp directly
            ELSE last_extracted_timestamp
        END
    FROM dbo.meta_control_watermark
    WHERE entity_name = @EntityName;

    -- Return the unified timestamp back to the caller
    RETURN @Watermark;
END;