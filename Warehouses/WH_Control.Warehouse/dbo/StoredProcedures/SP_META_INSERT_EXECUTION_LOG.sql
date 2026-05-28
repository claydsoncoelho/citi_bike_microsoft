CREATE   PROCEDURE dbo.SP_META_INSERT_EXECUTION_LOG (
    @ExecutionId VARCHAR(100),       -- Passed from Fabric Pipeline system variables
    @PipelineName VARCHAR(255),
    @StepName VARCHAR(255),
    @StepStatus VARCHAR(50),         -- 'STARTED', 'SUCCESS', 'FAILED'
    @AdditionalContext VARCHAR(MAX) = NULL -- Optional parameter for error tracking/row counts
)
AS
BEGIN
    -- Logging a step start
    -- EXEC dbo.SP_META_INSERT_EXECUTION_LOG 
    --     @ExecutionId = '00ad76ff-deff-45a0-a3c6-0d1e4b68fb2b',
    --     @PipelineName = 'PL_LOAD_GOLD_DW',
    --     @StepName = 'SP_LOAD_DIM_WEATHER',
    --     @StepStatus = 'STARTED';

    -- Logging a failure scenario with error context
    -- EXEC dbo.SP_META_INSERT_EXECUTION_LOG 
    --     @ExecutionId = '00ad76ff-deff-45a0-a3c6-0d1e4b68fb2b',
    --     @PipelineName = 'PL_LOAD_GOLD_DW',
    --     @StepName = 'SP_LOAD_FACT_TRIPS',
    --     @StepStatus = 'FAILED',
    --     @AdditionalContext = 'Error Code: Msg 15871. Function XACT_STATE is not supported.';

    INSERT INTO dbo.meta_execution_log (
        execution_id,
        pipeline_name,
        step_name,
        step_status,
        log_timestamp,
        additional_context
    )
    VALUES (
        CAST(@ExecutionId AS VARCHAR(100)), 
        @PipelineName,
        UPPER(@StepName),
        UPPER(@StepStatus),
        SYSDATETIME(), -- Captures system millisecond time natively
        @AdditionalContext
    );
END;