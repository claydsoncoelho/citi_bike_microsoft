CREATE TABLE [dbo].[meta_control_watermark] (

	[entity_name] varchar(255) NULL, 
	[last_extracted_date] date NULL, 
	[last_extracted_timestamp] datetime2(3) NULL, 
	[increment_unit] varchar(50) NULL, 
	[last_updated_at] datetime2(3) NULL
);