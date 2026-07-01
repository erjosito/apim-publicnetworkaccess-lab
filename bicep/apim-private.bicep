// APIM with inbound private endpoint and (optionally) public network access disabled.
//
// WHY TWO PHASES?
// publicNetworkAccess='Disabled' is REJECTED at create time and is only accepted once
// an APPROVED private endpoint exists. A single template cannot both create the service
// with Disabled AND create the PE, because the service PUT is evaluated before the PE
// exists. The supported IaC pattern is therefore two deployments of the SAME template:
//   Phase 1: disablePublicNetworkAccess = false  -> creates APIM (Enabled) + private endpoint
//   Phase 2: disablePublicNetworkAccess = true   -> flips the service to Disabled
// Both phases are declarative and pipeline-driven; nobody runs the CLI by hand.
//
// SKU NOTE: Standard v2 / Premium v2 and all classic tiers support inbound private
// endpoints. Basic v2 does NOT (PrivateEndpointNotSupportedInServiceSku) and therefore
// can never have public network access disabled.

@description('APIM instance name (globally unique).')
param serviceName string

@description('Location.')
param location string = resourceGroup().location

@description('Publisher email.')
param publisherEmail string

@description('Publisher name.')
param publisherName string

@description('APIM SKU. Use Developer/Standard/Premium (classic) or Standardv2/Premiumv2. Basicv2 cannot disable public access.')
@allowed([ 'Developer', 'Standard', 'Premium', 'Standardv2', 'Premiumv2' ])
param skuName string = 'Developer'

param skuCapacity int = 1

@description('Resource ID of the subnet that hosts the private endpoint.')
param peSubnetId string

@description('Phase 2 switch. Set true only AFTER the private endpoint is approved.')
param disablePublicNetworkAccess bool = false

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: serviceName
  location: location
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${serviceName}-pe'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${serviceName}-pe-conn'
        properties: {
          privateLinkServiceId: apim.id
          groupIds: [ 'Gateway' ]
        }
      }
    ]
  }
}

output apimId string = apim.id
output publicNetworkAccess string = apim.properties.publicNetworkAccess
