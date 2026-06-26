// =============================================================================
// Arc-enabled machine connection health report - Logic App (Consumption)
// -----------------------------------------------------------------------------
// Workflow steps:
//   1. Recurrence            - every week, Sunday at 00:00
//   2. HTTP (POST)           - Azure Resource Graph query for unhealthy Arc machines
//   3. Parse JSON            - parse the ARG response
//   4. Select                - project MachineName / LastReportedExtensionHealth / RecommendedAction
//   5. Create HTML table     - render the selected rows as an HTML table
//   6. Send an email (V2)    - email the table via the Office 365 Outlook connector
// =============================================================================

targetScope = 'resourceGroup'

@description('Name of the Logic App (Consumption) workflow.')
param logicAppName string = 'la-arc-conn-health'

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Target subscription ID whose Arc-enabled machines are evaluated by the ARG query.')
param targetSubscriptionId string = '00000000-0000-0000-0000-000000000000'

@description('Recipient email address for the report. Supply at deployment time.')
param recipientEmail string = 'recipient@example.com'

@description('Subject line of the report email.')
param emailSubject string = 'Weekly Arc-enabled Machine Connection Health Report'

@description('Name of the Office 365 Outlook API connection resource.')
param office365ConnectionName string = 'office365'

@description('Time zone used by the recurrence trigger.')
param recurrenceTimeZone string = 'UTC'

@description('Assign the Reader role on the target subscription to the Logic App managed identity so it can run the ARG query. Requires the deploying principal to have Owner / User Access Administrator on the subscription.')
param assignReaderRole bool = true

// -----------------------------------------------------------------------------
// Office 365 Outlook managed API connection
// NOTE: After deployment this connection must be authorized once in the portal
//       (open the connection resource and click "Authorize") so the Logic App
//       can send mail on behalf of the signed-in account.
// -----------------------------------------------------------------------------
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365ConnectionName
  location: location
  properties: {
    displayName: office365ConnectionName
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}

// -----------------------------------------------------------------------------
// Logic App (Consumption) with a system-assigned managed identity
// -----------------------------------------------------------------------------
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Week'
            interval: 1
            timeZone: recurrenceTimeZone
            schedule: {
              weekDays: [
                'Sunday'
              ]
              hours: [
                0
              ]
              minutes: [
                0
              ]
            }
          }
        }
      }
      actions: {
        HTTP: {
          runAfter: {}
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${environment().resourceManager}providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              subscriptions: [
                targetSubscriptionId
              ]
              query: '''resources
| where type =~ 'microsoft.hybridcompute/machines'
| extend connectionStatus = tostring(properties.status)
| where connectionStatus != 'Connected'
| extend MachineName = name
| extend LastReportedExtensionHealth = connectionStatus
| extend RecommendedAction = strcat('Investigate Arc agent connectivity for ', name, ' (last status: ', connectionStatus, ')')
| project MachineName, LastReportedExtensionHealth, RecommendedAction
| order by MachineName asc'''
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: environment().resourceManager
            }
          }
        }
        Parse_JSON: {
          runAfter: {
            HTTP: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'HTTP\')'
            schema: {
              type: 'object'
              properties: {
                data: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      MachineName: {
                        type: 'string'
                      }
                      LastReportedExtensionHealth: {
                        type: 'string'
                      }
                      RecommendedAction: {
                        type: 'string'
                      }
                    }
                  }
                }
              }
            }
          }
        }
        Select: {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@body(\'Parse_JSON\')?[\'data\']'
            select: {
              'Machine Name': '@item()?[\'MachineName\']'
              'Last Reported Extension Health': '@item()?[\'LastReportedExtensionHealth\']'
              'Recommended Action': '@item()?[\'RecommendedAction\']'
            }
          }
        }
        Create_HTML_table: {
          runAfter: {
            Select: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select\')'
            format: 'HTML'
          }
        }
        'Send_an_email_(V2)': {
          runAfter: {
            Create_HTML_table: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/Mail'
            body: {
              To: recipientEmail
              Subject: emailSubject
              Body: '<p>The following Arc-enabled machines are reporting connection issues:</p>@{body(\'Create_HTML_table\')}'
              Importance: 'Normal'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Reader role assignment for the Logic App managed identity on the target
// subscription so the ARG query can read resources.
// -----------------------------------------------------------------------------
module readerRole 'modules/subscriptionRoleAssignment.bicep' = if (assignReaderRole) {
  name: 'arc-health-reader-role'
  scope: subscription(targetSubscriptionId)
  params: {
    principalId: logicApp.identity.principalId
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  }
}

output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
output office365ConnectionId string = office365Connection.id
