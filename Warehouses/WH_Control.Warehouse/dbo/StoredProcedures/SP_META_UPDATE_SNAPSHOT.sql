CREATE PROCEDURE dbo.SP_META_UPDATE_SNAPSHOT (
    @silver_warehouse_name VARCHAR(255),
    @source_table_name VARCHAR(255),
    @timestamp_column_name VARCHAR(50)
)
AS
BEGIN
    -- EXEC dbo.SP_META_UPDATE_SNAPSHOT 'LH_Bronze_Citi_Bike', 'WEATHER_NYC', 'TIME_READABLE';
    -- EXEC dbo.SP_META_UPDATE_SNAPSHOT 'LH_Bronze_Citi_Bike', 'TRIPS', 'starttime';
    SET NOCOUNT ON;

    DECLARE @full_table_name NVARCHAR(510);
    DECLARE @extract_timestamp_from DATETIME2(3);
    DECLARE @dynamic_sql NVARCHAR(MAX);
    DECLARE @param_definition NVARCHAR(500);

    -- 1. Construct the fully qualified table name safely
    SET @full_table_name = QUOTENAME(@silver_warehouse_name) + '.' + QUOTENAME('dbo') + '.' + QUOTENAME(@source_table_name + '_SNAPSHOT') ;
    
    -- 2. Build the dynamic SQL string to evaluate the dynamic column inside the dynamic table
    --    QUOTENAME ensures that spaces or special characters in columns/tables don't break the SQL or introduce SQL injection
    SET @dynamic_sql = N'SELECT @max_ts_out = MAX(CAST(' + QUOTENAME(@timestamp_column_name) + N' AS DATETIME2(3))) FROM ' + @full_table_name;
    
    -- 3. Define the output parameter mapping for sp_executesql
    SET @param_definition = N'@max_ts_out DATETIME2(3) OUTPUT';

    -- 4. Execute the dynamic SQL statement safely
    EXEC sp_executesql 
        @dynamic_sql, 
        @param_definition, 
        @max_ts_out = @extract_timestamp_from OUTPUT;

    PRINT 'source_table_name: ' + @source_table_name;
    PRINT 'timestamp_column_name: ' + @timestamp_column_name;
    PRINT 'extract_timestamp_from: ' + CAST(@extract_timestamp_from AS VARCHAR(50));

    -- 5. Perform the MERGE operations using the fetched watermark value
    MERGE WH_Control.dbo.meta_control_snapshot AS Target
    USING (
        SELECT 
            @source_table_name AS source_table_name,
            @timestamp_column_name AS timestamp_column_name,
            @extract_timestamp_from AS extract_timestamp_from
    ) AS Source
    ON Target.source_table_name = Source.source_table_name
    AND Target.timestamp_column_name = Source.timestamp_column_name
    
    -- If entity exists, update the watermarks to the new position
    WHEN MATCHED THEN
        UPDATE SET 
            Target.extract_timestamp_from = Source.extract_timestamp_from,
            Target.last_updated_at = SYSDATETIME()
            
    -- Optional: If it doesn't exist yet in the metadata table, insert it 
    WHEN NOT MATCHED THEN
        INSERT (source_table_name, timestamp_column_name, extract_timestamp_from, last_updated_at)
        VALUES (Source.source_table_name, Source.timestamp_column_name, Source.extract_timestamp_from, SYSDATETIME());
END;