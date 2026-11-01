# Extension-Attribute-Details.ps1 - Explanation

## What this script does
Exports `extensionAttribute1` to `extensionAttribute5` for every device object in Microsoft Entra ID - Entra Joined, Hybrid Joined and Entra Registered - along with basic device details (name, device ID, OS, join type, enabled state, last sign-in) into a CSV report.

It produces two files:

| File | Contents |
| :--- | :--- |
| `C:\temp\EntraDevices_ExtAttr.csv` | Every device in the tenant, with ExtAttr1-5 columns (empty where not set) |
| `C:\temp\EntraDevices_WithExtAttr.csv` | Only devices where at least one of ExtAttr1-5 has a value |

At the end it prints a count of devices per join type to the console.

## Why Graph and not the portal
The Entra admin center doesn't show device extension attributes as a column in the **Devices > All devices** list, and there's no built-in export for them. Microsoft Graph exposes them on the `device` resource through the `extensionAttributes` property (attributes 1-15), so the script reads them straight from Graph.

Two Graph details shape how the query is written:
- `extensionAttributes` is **not returned by default** - it has to be asked for in `$select`.
- The individual attributes (`extensionAttribute1`, `extensionAttribute2`...) **can't be selected on their own** - the whole `extensionAttributes` object is selected, and the script then picks out 1-5.

Graph Explorer can run the same query, but results come back in pages and every page has to be opened manually via `@odata.nextLink`. For a tenant with hundreds or thousands of devices, the script is the practical option since it loops through all pages and writes the CSV in one go.

## Requirements

**PowerShell**
- Windows PowerShell 5.1 or PowerShell 7 - the script is written to run on both.

**Module**
- Only `Microsoft.Graph.Authentication` is needed (it contains `Connect-MgGraph` and `Invoke-MgGraphRequest`). The full `Microsoft.Graph` module is not required.
```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

**Permissions**
- Delegated Graph scope: `Device.Read.All` (read-only - the script doesn't change anything).
- The signed-in account needs a role that can read devices, e.g. **Global Reader**, **Cloud Device Administrator** or **Intune Administrator**.
- On first run, `Device.Read.All` needs consent. If the tenant asks for admin approval, a Global Administrator or Privileged Role Administrator has to grant it.

**Output folder**
- The script creates `C:\temp` if it doesn't exist. Change the two `Export-Csv` paths if you want the reports somewhere else.

## Step-by-step breakdown

**1. Connect to Graph**
`Connect-MgGraph -Scopes "Device.Read.All"` opens the sign-in prompt and connects with read-only device permission.

**2. Build the query**
The URI selects only the properties needed for the report and uses `$top=999` - the maximum page size for devices - so large tenants need fewer round trips:
```
GET https://graph.microsoft.com/v1.0/devices?$select=displayName,deviceId,operatingSystem,operatingSystemVersion,trustType,accountEnabled,approximateLastSignInDateTime,extensionAttributes&$top=999
```

**3. Page through all devices**
The `do / while` loop calls `Invoke-MgGraphRequest`, adds that page's devices to `$all`, and follows `@odata.nextLink` until there are no more pages. The total device count is printed once done - compare it with the total in the Entra portal to confirm nothing was missed.

**4. Translate the join type**
Graph returns the join type in `trustType` with raw values, which the script maps to readable names:

| `trustType` | Join type |
| :--- | :--- |
| `AzureAd` | Entra joined |
| `ServerAd` | Hybrid joined |
| `Workplace` | Entra registered |

**5. Build the report**
For every device a flat object is created with the device details plus `ExtAttr1`-`ExtAttr5` pulled out of `extensionAttributes`.

**6. Export**
- Full report → `EntraDevices_ExtAttr.csv`
- Filtered report (any of ExtAttr1-5 populated) → `EntraDevices_WithExtAttr.csv`

**7. Summary**
`Group-Object JoinType` prints how many devices fall under each join type.

## Sample usage
```powershell
.\Extension-Attribute-Details.ps1
```

To quickly check the output after the run:
```powershell
Import-Csv C:\temp\EntraDevices_ExtAttr.csv | Select-Object -First 10 | Format-Table
```

## Important: Hybrid joined devices and on-prem values
Device extension attributes in Entra ID are **cloud-side** values. Entra Connect does **not** sync `extensionAttribute1`-`15` from the on-premises AD computer object to the Entra device object by default.

So if the values were set on the computer objects in on-prem Active Directory, the Hybrid joined devices in this report will show them as **empty**. In that case, pull them from AD instead (run on a domain-joined machine with the RSAT ActiveDirectory module):
```powershell
Get-ADComputer -Filter * -Properties extensionAttribute1,extensionAttribute2,extensionAttribute3,extensionAttribute4,extensionAttribute5 |
    Select-Object Name, ObjectGUID, extensionAttribute1, extensionAttribute2, extensionAttribute3, extensionAttribute4, extensionAttribute5 |
    Export-Csv C:\temp\AD_Computers_ExtAttr.csv -NoTypeInformation
```
For Hybrid joined devices, the Entra `DeviceId` generally matches the AD `ObjectGUID`, so the two reports can be joined on that.

Confirm with whoever owns the data **where** the attributes are populated (Entra or on-prem AD) before reading the report as "attributes missing".

## Troubleshooting

**`Unexpected token '??' in expression or statement`**
The `??` operator only exists in PowerShell 7. This script doesn't use it, but if you modify it and run on Windows PowerShell 5.1, use an `if` statement instead.

**`The term 'Connect-MgGraph' is not recognized`**
The Graph module isn't installed or isn't loaded. Install `Microsoft.Graph.Authentication` (see Requirements).

**`Import-Module : ... no valid module file was found in any module directory`**
Usually happens when the Documents folder is redirected to OneDrive - the module installs to `C:\Users\<user>\OneDrive\Documents\WindowsPowerShell\Modules`, which isn't in `PSModulePath`. Either import it by full path:
```powershell
Import-Module "C:\Users\<user>\OneDrive\Documents\WindowsPowerShell\Modules\Microsoft.Graph.Authentication\<version>\Microsoft.Graph.Authentication.psd1"
```
or install it for all users from an elevated prompt (lands in `C:\Program Files\WindowsPowerShell\Modules`):
```powershell
Install-Module Microsoft.Graph.Authentication -Scope AllUsers
```
If the import by full path also fails, OneDrive Files On-Demand may have left the files cloud-only - set the folder to **Always keep on this device**.

**`InteractiveBrowserCredential authentication failed: A window handle must be configured`**
A Web Account Manager (WAM) sign-in issue, common in PowerShell ISE. Use device code login:
```powershell
Connect-MgGraph -Scopes "Device.Read.All" -UseDeviceCode
```
or run the script from a normal PowerShell console instead of ISE.

**`Export-Csv : Could not find a part of the path`**
The output folder doesn't exist. The script creates `C:\temp` itself; if you changed the path, make sure that folder exists.

**`Insufficient privileges` / 403**
The signed-in account doesn't have a role that can read devices, or `Device.Read.All` hasn't been consented - see Requirements.

## Notes
- **Read-only** - the script only reads device objects and writes CSV files locally.
- `LastSignIn` is `approximateLastSignInDateTime`, which Entra updates roughly every 14 days, so treat it as approximate.
- To report on more attributes (6-15), add `ExtAttr6 = $ea.extensionAttribute6` and so on to the report object - no change to the Graph query is needed since the whole `extensionAttributes` object is already selected.
