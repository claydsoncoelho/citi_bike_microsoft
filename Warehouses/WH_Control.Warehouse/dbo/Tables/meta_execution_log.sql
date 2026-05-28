CREATE TABLE [dbo].[meta_execution_log] (

	[execution_id] varchar(100) NULL, 
	[pipeline_name] varchar(255) NULL, 
	[step_name] varchar(255) NULL, 
	[step_status] varchar(50) NULL, 
	[log_timestamp] datetime2(2) NULL, 
	[additional_context] varchar(max) NULL
);