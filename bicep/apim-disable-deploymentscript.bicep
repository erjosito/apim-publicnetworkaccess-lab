// ALTERNATIVE: run a script INSIDE the IaC deployment to disable public network access.
//
// Microsoft.Resources/deploymentScripts runs an Azure CLI script in an auto-provisioned
// container (ACI) as part of the deployment. With a dependsOn on the private endpoint it
// acts as an in-template "phase 2", collapsing the two-phase deploy into ONE deployment.
//
// Trade-offs vs. the pure two-phase template (apim-private.bicep):
//   + single deployment, no external pipeline step to flip the flag
//   - provisions an ACI + storage account (extra cost + ~1-2 min container spin-up)
//   - needs a managed identity with rights on the APIM instance
//   - imperative logic inside declarative IaC; you own idempotency + error handling
//
// In a real single-shot template you would also declare the APIM service and the private
// endpoint here and set `dependsOn: [ apim, pe ]` on the script. This file targets an
// existing instance to validate the MECHANISM.

@description('Name of the existing APIM instance to disable public access on.')
param serviceName string

param location string = resourceGroup().location

@description('Resource ID of the user-assigned identity the script runs as (needs API Management Service Contributor).')
param uamiId string

@description('Client ID of that user-assigned identity (for az login --identity).')
param uamiClientId string

resource disablePna 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'disable-pna-${serviceName}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    timeout: 'PT30M'
    environmentVariables: [
      { name: 'SVC', value: serviceName }
      { name: 'RG', value: resourceGroup().name }
      { name: 'SUB', value: subscription().subscriptionId }
      { name: 'MI_CLIENT_ID', value: uamiClientId }
    ]
    scriptContent: '''
set -e
az login --identity --username "$MI_CLIENT_ID" --output none
URL="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$SVC?api-version=2024-05-01"
az rest --method PATCH --url "$URL" --headers "Content-Type=application/json" --body '{"properties":{"publicNetworkAccess":"Disabled"}}' --output none
PNA=$(az rest --method GET --url "$URL" --query "properties.publicNetworkAccess" -o tsv)
echo "{\"publicNetworkAccess\":\"$PNA\"}" > "$AZ_SCRIPTS_OUTPUT_PATH"
'''
  }
}

output publicNetworkAccess string = disablePna.properties.outputs.publicNetworkAccess
