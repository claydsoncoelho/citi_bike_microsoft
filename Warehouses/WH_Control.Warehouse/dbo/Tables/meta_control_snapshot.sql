CREATE TABLE [dbo].[meta_control_snapshot] (

	[bronze_lakehouse_name] varchar(255) NOT NULL, 
	[silver_warehouse_name] varchar(255) NOT NULL, 
	[source_table_name] varchar(255) NOT NULL, 
	[key_columns] varchar(1000) NOT NULL, 
	[timestamp_column_name] varchar(255) NULL, 
	[extract_timestamp_from] datetime2(3) NULL, 
	[extract_range_in_days] int NULL, 
	[is_active] bit NULL, 
	[last_updated_at] datetime2(3) NULL
);