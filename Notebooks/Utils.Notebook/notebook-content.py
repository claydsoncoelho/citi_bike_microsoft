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
import json

# --- CONFIGURATION ---
TENANT_ID = ""
CLIENT_ID = ""
CLIENT_SECRET = "" 
SPN_OBJECT_ID = ""

WORKSPACE_ID = "f0e66a8e-5ed0-498b-b420-cb1b2f369f9f"
NEW_LAKEHOUSE_NAME = "LH_Silver_Citi_Bike"

# --- GET ACCESS TOKEN FOR SPN ---
def get_spn_token(tenant_id, client_id, client_secret):
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    payload = {
        'grant_type': 'client_credentials',
        'client_id': client_id,
        'client_secret': client_secret,
        'scope': 'https://api.fabric.microsoft.com/.default'
    }
    response = requests.post(url, data=payload)
    response.raise_for_status()
    return response.json().get("access_token")

spn_token = get_spn_token(TENANT_ID, CLIENT_ID, CLIENT_SECRET)
print("Successfully authenticated as Service Principal.")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import base64
import json

def verify_spn_object_id(token, provided_id):
    # JWT tokens are three parts separated by dots; the second part is the payload
    try:
        payload_part = token.split('.')[1]
        # Add padding if necessary for base64 decoding
        missing_padding = len(payload_part) % 4
        if missing_padding:
            payload_part += '=' * (4 - missing_padding)
            
        decoded_payload = base64.b64decode(payload_part).decode('utf-8')
        token_data = json.loads(decoded_payload)
        
        token_oid = token_data.get('oid')
        
        print(f"--- Identity Verification ---")
        print(f"Object ID found in your Token: {token_oid}")
        print(f"Object ID you provided:        {provided_id}")
        
        if token_oid.lower() == provided_id.lower():
            print("\n✅ SUCCESS: The IDs match! Your SPN_OBJECT_ID is correct.")
        else:
            print("\n❌ MISMATCH: The IDs do not match. Please copy the 'Object ID found in your Token' and use that as your SPN_OBJECT_ID.")
            
    except Exception as e:
        print(f"Error decoding token: {e}")

verify_spn_object_id(spn_token, SPN_OBJECT_ID)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# --- Create Lakehouse ---

def create_lakehouse_as_spn(workspace_id, lakehouse_name, token):
    # Fabric API endpoint for creating items
    url = f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}/items"
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    # Define the new Lakehouse
    payload = {
        "displayName": lakehouse_name,
        "type": "Lakehouse"
    }
    
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code == 201:
        new_item = response.json()
        print("✅ Success! Lakehouse created by Service Principal.")
        print(f"Name: {new_item.get('displayName')}")
        print(f"ID:   {new_item.get('id')}")
    else:
        print(f"❌ Failed to create Lakehouse: {response.status_code}")
        print(response.text)

# Provide a unique name for the new Lakehouse
create_lakehouse_as_spn(WORKSPACE_ID, NEW_LAKEHOUSE_NAME, spn_token)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
