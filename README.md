# Citi Bike Analytics

## Project Overview & Objectives
This project delivered the Citi Bike Data Analytics Solution, using only Microsoft Cloud Platforms (Azure, Fabric and PowerBI). The solution uses a Medallion Architecture. The goal is to demonstrate a production-ready environment focusing on:
- **Security & Identity**: Implementing Service Principals and RBAC.
- **Fabric Development Best Practices**: Leveraging Fabric Lakehouses, Warehouses, Notebooks, Pipelines, etc.
- **CI/CD Workflow**: Using one of the recommended CI/CD Fabric deployment workflows.

## Architecture

<img width="742" height="559" alt="image" src="https://github.com/user-attachments/assets/fbdb2efc-41c5-4726-8dbc-5adae19f4349" />

## Azure Resources

The following Azure resources were provisioned. 

### Entra ID

The diagram below shows how the Role Based Access Control (RBAC) was implemented. This is a simple RBAC that includes only the service principal related groups. In a real scenario, other groups would be created to support different user access levels.

<img width="498" height="355" alt="image" src="https://github.com/user-attachments/assets/884f7044-664c-4629-bf62-8a2f0909cf48" />

**Groups**

Entity Name | Members | Purpose
-- | -- | --
grp_az_read | Service Principal | Read access to Azure resources, in this case Key Vault, but we could add more Azure resources here.
grp_az_read_storage_acc | grp_az_read | Read access to Azure storage account and specific containers.
grp_fabric_workspace_contributor | Service Principal | Contributor access to Fabric Workspace.

### Key Vault

Key Vault was created to manage the Service Principal secret securely.

Name: citi_bike
Role assignments: grp_za_read
- Key Vault Reader
- Key Vault Secrets User

**Important**: The creator of the “Fabric Key Vault Reference”, must have at least “Key Vault Certificate User” role in the key vault.
Reference: https://learn.microsoft.com/en-us/fabric/data-factory/azure-key-vault-reference-configure#prerequisites

### Service Principal

Service Principals not only improve the security and stability of Fabric environment, by removing the
dependencies on individual user accounts, but also are key components of process automation.

The app to create a service account is called App Registration. The following app registration
was created:

Create a service principal:

Path: Enterprise Application > New Application > Create your own application

Name: **sp_citi_bike**

Create a secret:

Path: App registration > Manage > Certificates & secrets

Value: **Saved in key vault**.

### Storage Account

The following Azure storage account and containers were created:

**Account**: citibike4clay

IAM: grp_az_read_storage_acc - Reader
- Container citi-bike: Trip history (CSV).
    - IAM: grp_az_read_storage_acc - Storage Blob Data Reader
- Container weather-ny: Daily weather metrics (CSV).
    - IAM: grp_az_read_storage_acc - Storage Blob Data Reader

## Fabric Resources

### Workspaces

Workspaces are places to collaborate and create collections of items like lakehouses, warehouses, and reports, and to create task flows. 

The following workspaces were created in Fabric:

Name | Purpose | Branch
-- | -- | --
citi_bike_feature_01 | Feature workspace | feature_01
cit_bike_dev | Development workspace | main
citi_bike_test | Test workspace |  
citi_bike_prod | Production workspace |  

As you can see, we only have one main branch and one or more feature branches, but we don’t have branches for test and prod workspaces. This is due to the CI/CD deployment workflow adopted, which is this one suggested by Microsoft Fabric official documentation:

<img width="704" height="317" alt="image" src="https://github.com/user-attachments/assets/29625e3c-8191-4f49-a899-4dba0bd022a7" />

Reference: https://learn.microsoft.com/en-us/fabric/cicd/manage-deployment

We are using this deployment process because we have each Semantic Model pointing to its respective Gold Warehouse in its respective workspaces, as you can see in the table below. In order to make this possible we need to use the Deployment rules feature of Fabric Deployment Pipelines.

Gold Warehouse | Semantic Model | Deployment Method
-- | -- | --
Dev | Feature | Git based
Dev | Dev | Git based
Test | Test | Fabric Deployment Pipelines
Prod | Prod | Fabric Deployment Pipelines

## Metadata Driven Pipelines

To go from a bunch of raw files stored in a blob to powerful analytic dashboard, a series of data ingestion and data transformation steps are executed in a very specific sequence. To orchestrate the execution of all those steps we use Microsoft Fabric Pipelines.

In a simple scenario, you need a pipeline for every single data source, wich can become messy and time-consuming to maintain. ****Metadata driven pipelines**** identify common activities and create reusable code to ingest and transform your data with less code, reduced maintenance and greater scalability. 

My metadata driven pipelines were inspired by this documentation, but they are modified to fulfill the specific needs of this project.
https://techcommunity.microsoft.com/blog/fasttrackforazureblog/metadata-driven-pipelines-for-microsoft-fabric/3891651


### Data flow

The sequence below shows how the data flows from source to report:

1. **Azure blob storage** - Source files are dropped here.
2. **LH_Bronze table** - Pipeline copies files into delta tables.
3. **LH_Silver snapshot table** - Notebook creates Silver snapshot tables of the Silver delta tables. 
4. **WH_Silver stage view** - Views that perform initial data transformation (datatypes, column derivation).
5. **WH_Silver intermediate view** - Views that perform heavy data transformation (dimensional model).
6. **WH_Gold data mart table** - Dimension and Fact tables saved here.
7. **Semantic Model** - Connects to gold warehouse, defines relationship between tables and metrics.
8. **Report** - Dashboards.

### WH_Control

Every metadata driven pipeline need a repository to save the, well... metadata. Instead of using an external database for data, I decide to use a Fabric Warehouse as my metadata repository.


<img width="476" height="874" alt="image" src="https://github.com/user-attachments/assets/15eebeb8-b7c0-4eff-afe8-5b7c8e1f60aa" />

WH_Control has tables, functions and stored procedures to support metadata driven pipelines.

**1. Tables**
- **meta_control_snapshot**: Contains each source table that must be snapshotted. This tables contains columns like table name and key columns.
- **meta_control_watermark**: Contains the watermark of each incremental table.
- **meta_execution_log**: Contains the log of each step of each execution. This is very helpful for monitoring and failure investigation.

**2. Functions**
- **fn_meta_get_watermark**: Get the watermark value of a table.

**3. Stored Procedures**
- **SP_META_INSERT_EXECUTION_LOG**: Insert a record in meta_exectution_log table.
- **SP_META_UPDATE_WATERMARK**: Update a record in meta_control_watermark table.

Metadata driven pipeline example: Each record in **meta_control_snapshot** is a source table that needs to be snapshotted. Since the snapshot process is **standardized and parameterized**, we can run it in a **loop**: 
1. Query metadata table.
2. Process each record in a loop.
3. Inside each iteration of the loop, transform data using notebook.

<img width="1155" height="250" alt="image" src="https://github.com/user-attachments/assets/50407480-35a2-4cd9-b049-fa730d0fdc0e" />






