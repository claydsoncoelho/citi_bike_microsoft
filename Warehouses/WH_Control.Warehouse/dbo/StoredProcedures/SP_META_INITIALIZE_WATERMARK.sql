CREATE     PROCEDURE dbo.SP_META_INITIALIZE_WATERMARK (
    @EntityName VARCHAR(255),
    @InitialDate DATE,
    @InitialTimestamp DATETIME2(3),
    @IncrementUnit VARCHAR(50)
)
AS
BEGIN
    -- 1. Check if the entity already exists using the scalar function
    IF dbo.fn_meta_check_entity_exists(@EntityName) = 1
    BEGIN
        -- Log a message and exit the procedure without changing anything
        PRINT CONCAT('Initialization skipped: Entity ''', @EntityName, ''' already exists in meta_control_watermark.');
        RETURN;
    END
    ELSE
    BEGIN
        -- 2. If it does not exist, call the update SP to create the initial seed record
        PRINT CONCAT('Creating watermark for: ''', @EntityName, '''.');
        
        EXEC dbo.SP_META_UPDATE_WATERMARK 
            @EntityName = @EntityName,
            @LastExtractedDate = @InitialDate,
            @LastExtractedTimestamp = @InitialTimestamp,
            @IncrementUnit = @IncrementUnit;
            
        PRINT CONCAT('Watermark for ''', @EntityName, ''' successfully created.');
    END
END;