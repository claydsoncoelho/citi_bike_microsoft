# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {}
# META }

# CELL ********************

import requests

# 1. Configuration
# Get the workspace id from your browser URL (the part after /groups/)
workspace_id = "f91c3786-cc5f-4a68-b38d-22848019e45b"           # groups/
report_id = "41ddc5d9-095c-4314-a074-2a9834ce3d66"
new_semantic_model_id = "881fc0ac-e60c-428c-b61a-4b346efde726"  # dataset/

# 2. Get the Fabric Token
token = mssparkutils.credentials.getToken("pbi")

# 3. Prepare API Call - Use the groups/{groupId} endpoint
url = f"https://api.powerbi.com/v1.0/myorg/groups/{workspace_id}/reports/{report_id}/Rebind"

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}
body = {
    "datasetId": new_semantic_model_id
}

# 4. Execute Rebind
response = requests.post(url, json=body, headers=headers)

# 5. Handle Response
if response.status_code == 200:
    print("Successfully rebound the report!")
else:
    print(f"Failed to rebind. Status Code: {response.status_code}")
    print(response.text)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
