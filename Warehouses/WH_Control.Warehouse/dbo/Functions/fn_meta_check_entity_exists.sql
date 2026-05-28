CREATE   FUNCTION dbo.fn_meta_check_entity_exists (
    @EntityName VARCHAR(255)
)
RETURNS BIT
AS
BEGIN
    DECLARE @Exists BIT;

    IF EXISTS (
        SELECT 1 
        FROM dbo.meta_control_watermark 
        WHERE entity_name = @EntityName
    )
        SET @Exists = 1;
    ELSE
        SET @Exists = 0;

    RETURN @Exists;
END;