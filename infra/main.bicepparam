using './main.bicep'

param logicAppName = 'la-arc-conn-health'
param targetSubscriptionId = '00000000-0000-0000-0000-000000000000'
// Supply recipientEmail at deployment time, e.g. --parameters recipientEmail=<you@example.com>
param emailSubject = 'Weekly Arc-enabled Machine Connection Health Report'
param office365ConnectionName = 'office365'
param recurrenceTimeZone = 'UTC'
param assignReaderRole = true
