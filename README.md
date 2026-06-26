# ArcHealthCheck-LogicApp

An Azure **Logic App (Consumption)**, deployed via Bicep, that produces a weekly
HTML-email report of **Azure Arc-enabled machines reporting connection issues**.

## What it does

The workflow runs every **Sunday at 00:00 (UTC by default)** and performs six steps:

| # | Step | Description |
|---|------|-------------|
| 1 | **Recurrence** | Weekly trigger, Sunday at midnight. |
| 2 | **HTTP (POST)** | Calls the Azure Resource Graph REST API, authenticated with the Logic App's **system-assigned managed identity** (no secrets). |
| 3 | **Parse JSON** | Parses the ARG response (`data[]`). |
| 4 | **Select** | Projects `Machine Name`, `Last Reported Extension Health`, `Recommended Action`. |
| 5 | **Create HTML table** | Renders the rows as an HTML table. |
| 6 | **Send an email (V2)** | Emails the table via the Office 365 Outlook connector. |

The ARG query returns Arc machines (`microsoft.hybridcompute/machines`) whose
status is not `Connected`. Adjust the query in [`infra/main.bicep`](infra/main.bicep)
to change the definition of "connection issues".

## Repository layout

```
infra/
  main.bicep                          Main template (Logic App, O365 connection, role assignment module)
  main.bicepparam                     Parameter values
  modules/
    subscriptionRoleAssignment.bicep  Reader role assignment at subscription scope
```

## Parameters

| Name | Default | Description |
|------|---------|-------------|
| `logicAppName` | `la-arc-conn-health` | Logic App workflow name. |
| `location` | resource group location | Azure region for the resources. |
| `targetSubscriptionId` | `00000000-...` *(placeholder)* | Subscription whose Arc machines are evaluated. |
| `recipientEmail` | `recipient@example.com` *(placeholder)* | Report recipient. Supply at deployment time. |
| `emailSubject` | `Weekly Arc-enabled Machine Connection Health Report` | Email subject line. |
| `office365ConnectionName` | `office365` | Office 365 API connection name. |
| `recurrenceTimeZone` | `UTC` | Time zone for the recurrence trigger. |
| `assignReaderRole` | `true` | Assign **Reader** on the target subscription to the app's identity. Requires Owner / User Access Administrator to deploy. |

> The subscription ID in [`infra/main.bicepparam`](infra/main.bicepparam) is a
> placeholder. Supply the real value at deploy time.

## Deploy

```powershell
# 1. Create (or reuse) a resource group
az group create --name arc-logicapp-rg --location eastus

# 2. Deploy the template, passing your real subscription ID and recipient email
az deployment group create `
  --resource-group arc-logicapp-rg `
  --template-file infra/main.bicep `
  --parameters infra/main.bicepparam `
  --parameters targetSubscriptionId=<your-subscription-id> `
  --parameters recipientEmail=<you@example.com>
```

## Post-deployment (one-time)

The Office 365 Outlook connection requires an interactive authorization before
mail can be sent:

1. In the Azure portal, open the resource group.
2. Open the **office365** API Connection.
3. Click **Edit API connection** → **Authorize** → sign in → **Save**.

Until this is done, the *Send an email (V2)* step will fail.

## Validate

Use **Run Trigger** on the Logic App in the portal to execute on demand;
otherwise it runs automatically on the weekly schedule.
