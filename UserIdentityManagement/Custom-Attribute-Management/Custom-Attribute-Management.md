# Custom-Attribute-Management.ps1 — Explanation

## What this script does
Manages two genuinely different Entra ID features that both get called "custom attributes" and are easy to confuse: **Custom Security Attributes** (the modern, beta-only, attribute-set-based system covered in the Graph API toolkit's `CustomSecurityAttributes.md`) and **on-premises extension attributes** (the older `extensionAttribute1`–`extensionAttribute15` fields, originally from on-prem AD, still widely used for dynamic group rules and filtering).

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `CustomSecAttributeAssignment.ReadWrite.All` (assign/read custom security attribute values), `CustomSecAttributeDefinition.Read.All` (needed to resolve attribute set/name context), and `User.ReadWrite.All` (needed for the extension attribute actions).

**Why this script uses `Invoke-MgGraphRequest` instead of dedicated cmdlets**
Custom Security Attributes are a beta-only API (see `CustomSecurityAttributes.md`), and the typed JSON structure they need (`@odata.type`, nested attribute-set objects) is easiest to build reliably as raw JSON sent through `Invoke-MgGraphRequest`, rather than depending on a specific SDK cmdlet version supporting this exact shape. This is a good pattern to reuse anytime you're working against a beta-only or newly-added endpoint: build the JSON body yourself and send it directly.

**Looking up the user**
Same as the credential management script — the user lookup happens once per row, before the switch statement, since every action here needs the user's object ID.

**The switch statement (core logic)**

- **`setcustomattribute`** — reads `AttributeSet`, `AttributeName`, `ValueType`, and `AttributeValue` from the CSV row. The `ValueType` column controls how the raw text value gets converted: `boolean` becomes a real `$true`/`$false`, `integer` becomes a number, anything else stays a string. It then builds the exact nested JSON structure Custom Security Attributes require — an object keyed by the attribute set name, containing the `@odata.type` marker and the attribute name/value pair — and sends it as a `PATCH` to the **beta** endpoint (`/beta/users/{id}`), since this feature doesn't exist in v1.0 yet.

- **`getcustomattributes`** — sends a `GET` request with `$select=customSecurityAttributes` to retrieve just that property, then prints a compact JSON summary of whatever's currently assigned. If nothing is assigned, it clearly reports that rather than showing an empty/confusing result.

- **`setextensionattribute`** — this is the **separate, older mechanism**. It validates that `ExtensionAttributeNumber` is between 1 and 15 (Entra ID only supports that range, a holdover from on-prem AD schema), builds the field name dynamically (e.g. `extensionAttribute7`), and `PATCH`es it via the stable **v1.0** endpoint under `onPremisesExtensionAttributes` — no beta needed for this one, since it's a long-standing, stable feature.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,UserPrincipalName,AttributeSet,AttributeName,ValueType,AttributeValue,ExtensionAttributeNumber,ExtensionAttributeValue
setcustomattribute,jdoe@contoso.com,Engineering,ProjectCode,String,PRJ-1042,,
setcustomattribute,jdoe@contoso.com,Engineering,IsContractor,Boolean,false,,
getcustomattributes,jdoe@contoso.com,,,,,,
setextensionattribute,jdoe@contoso.com,,,,,7,RemoteWorker
```

## Notes
- **Even Global Administrator can't touch Custom Security Attributes by default** — as covered in `CustomSecurityAttributes.md`, this requires a dedicated role like Attribute Assignment Administrator. If this script fails with a permissions error despite the account having broad admin rights, that role assignment is the first thing to check.
- Before running `setcustomattribute`, the attribute set and attribute definition **must already exist** in the tenant (created via the Graph API toolkit's documented `attributeSets`/`customSecurityAttributeDefinitions` endpoints, or through the Entra admin center) — this script assigns *values*, it doesn't create the schema itself.
- `extensionAttribute1`–`15` are commonly used as the anchor for **dynamic group membership rules** (see `GroupAccessManagement` scripts) — a common real-world pattern is tagging users with something like `extensionAttribute7 = "RemoteWorker"` and then building a dynamic group filtered on that exact value.
