CREATE TABLE [dbo].[TRIPS_SNAPSHOT] (

	[SCD_KEY] varchar(255) NULL, 
	[tripduration] varchar(255) NULL, 
	[starttime] varchar(255) NULL, 
	[stoptime] varchar(255) NULL, 
	[start_station_id] varchar(255) NULL, 
	[start_station_name] varchar(255) NULL, 
	[start_station_latitude] varchar(255) NULL, 
	[start_station_longitude] varchar(255) NULL, 
	[end_station_id] varchar(255) NULL, 
	[end_station_name] varchar(255) NULL, 
	[end_station_latitude] varchar(255) NULL, 
	[end_station_longitude] varchar(255) NULL, 
	[bikeid] varchar(255) NULL, 
	[usertype] varchar(255) NULL, 
	[birth_year] varchar(255) NULL, 
	[gender] varchar(255) NULL, 
	[meta_filename] varchar(255) NULL, 
	[SCD_START_TIMESTAMP] datetime2(3) NULL, 
	[SCD_END_TIMESTAMP] datetime2(3) NULL, 
	[SCD_IS_CURRENT] bit NULL
);