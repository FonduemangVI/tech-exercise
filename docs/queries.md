# Demo queries

Run in the Log Analytics workspace (`wiz-ex-<region>-law`), Logs blade. Paste, do not type.

## Audit (R26): who created the VM's Contributor role assignment (W3)

Every change in the subscription is attributable. This shows the pipeline identity created the role assignment, from a reviewed PR.

The Log Analytics copy of the Activity Log only holds events from when its diagnostic setting was created. In this build the W3 grant came just before that (the setting failed on the first apply and was created on the re-run), so this query does not find it; `demo/demo.sh` reads the Activity Log itself (`az monitor activity-log list`, 90 days) instead. For a grant made after the setting existed, the query below works.

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
| extend Secret = extract(@"/secrets/([^/?]+)", 1, RequestUri), Caller = tostring(Identity.claim.oid)
| project TimeGenerated, OperationName, ResultSignature, CallerIpAddress, Caller, Secret
| order by TimeGenerated desc
```

Summary, one row per identity and secret. The secret name is taken from the request URI, which otherwise splits one secret across rows by port (`:8443`, `:8444`, none). `Caller` is an object ID: resolve it with `az ad sp show --id <oid> --query displayName`. Checked on 23 Oct 2026: `id-tasky` (the Secrets Store CSI driver, rotation on) reads `mongo-app-uri` and `tasky-jwt-secret` every 2 minutes; the Mongo VM's identity reads `mongo-admin-uri` for the backup. Nothing else reads any secret.

```kql
AZKVAuditLogs
| where OperationName in ("SecretGet", "SecretSet")
| extend Secret = extract(@"/secrets/([^/?]+)", 1, RequestUri), Caller = tostring(Identity.claim.oid)
| summarize Reads = count(), Last = max(TimeGenerated) by OperationName, Caller, Secret
| order by Secret asc
```
