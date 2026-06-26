// =============================================================================
// Subscription-scoped role assignment for a managed identity.
// =============================================================================

targetScope = 'subscription'

@description('Principal (object) ID of the identity receiving the role.')
param principalId string

@description('Role definition GUID to assign (e.g. Reader = acdd72a7-3385-48ef-bd42-f606fba81ae7).')
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
