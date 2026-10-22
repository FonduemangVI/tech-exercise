# Demo queries

Run in the Log Analytics workspace (`wiz-ex-<region>-law`), Logs blade. Paste, do not type.

## Audit (R26): who created the VM's Contributor role assignment (W3)

Every change in the subscription is attributable. This shows the pipeline identity created the role assignment, from a reviewed PR.

```kql
AzureActivity
| where OperationNameValue =~ "Microsoft.Authorization/roleAssignments/write"
| where ActivityStatusValue =~ "Success"
| project TimeGenerated, Caller, Scope = tostring(Properties_d.entity)
| order by TimeGenerated desc
```

## Detective (R28): anonymous reads of the backups (W6)

The same query drives the alert in `infra/alerts.tf`.

```kql
StorageBlobLogs
| where AuthenticationType == "Anonymous"
| where OperationName in ("GetBlob", "ListBlobs", "GetBlobProperties")
| where Uri has "/backups"
| project TimeGenerated, OperationName, CallerIpAddress, UserAgentHeader, Uri
```

## Key Vault: who read which secret

```kql
AZKVAuditLogs
| where OperationName in ("SecretGet", "SecretSet")
| project TimeGenerated, OperationName, ResultSignature, CallerIpAddress, Caller = tostring(Identity.claim.oid), Secret = RequestUri
| order by TimeGenerated desc
```
