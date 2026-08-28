[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\BulkUserProvisioning-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("User.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$users = Import-Csv -Path $CsvPath

foreach ($row in $users) {

    $action = $row.Action.Trim().ToLower()
    $upn = $row.UserPrincipalName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "new" {
                $passwordProfile = @{
                    Password = $row.Password
                    ForceChangePasswordNextSignIn = $true
                }

                $newUserParams = @{
                    AccountEnabled = $true
                    DisplayName = $row.DisplayName
                    UserPrincipalName = $upn
                    MailNickname = $row.MailNickname
                    PasswordProfile = $passwordProfile
                    UsageLocation = $row.UsageLocation
                    Department = $row.Department
                    JobTitle = $row.JobTitle
                }

                New-MgUser -BodyParameter $newUserParams | Out-Null
                $status = "Success"
                $message = "User created."
            }

            "update" {
                $existingUser = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

                $updateParams = @{}
                if ($row.DisplayName) { $updateParams["DisplayName"] = $row.DisplayName }
                if ($row.Department)  { $updateParams["Department"] = $row.Department }
                if ($row.JobTitle)    { $updateParams["JobTitle"] = $row.JobTitle }
                if ($row.UsageLocation) { $updateParams["UsageLocation"] = $row.UsageLocation }

                Update-MgUser -UserId $existingUser.Id -BodyParameter $updateParams
                $status = "Success"
                $message = "User updated."
            }

            "deprovision" {
                $existingUser = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

                Update-MgUser -UserId $existingUser.Id -AccountEnabled:$false
                Revoke-MgUserSignInSession -UserId $existingUser.Id | Out-Null

                $status = "Success"
                $message = "User disabled and sessions revoked."
            }

            default {
                $status = "Skipped"
                $message = "Unrecognized action value: $($row.Action)"
            }
        }
    }
    catch {
        $status = "Failed"
        $message = $_.Exception.Message
    }

    $results.Add([PSCustomObject]@{
        UserPrincipalName = $upn
        Action            = $row.Action
        Status            = $status
        Message           = $message
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null


Step-by-step explanation

Parameters block — the script takes two inputs: -CsvPath (required, points to your input file) and -LogPath (optional, auto-generates a timestamped filename if you don't provide one). This means you run the script like:

powershell
.\Bulk-UserProvisioning.ps1 -CsvPath ".\users.csv"

Connecting to Graph — Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All" opens an interactive sign-in (or uses a cached token) with exactly the permissions this script needs — nothing broader. -NoWelcome just suppresses the banner text Graph normally prints.

Results collection — $results is an empty list that will hold one record per user processed, so we can review a full report at the end instead of just watching text scroll by.

CSV validation — before doing anything else, it checks the CSV file actually exists at the path you gave it, and stops immediately with a clear error if not — better than failing halfway through 200 users.

The main loop — foreach ($row in $users) walks through every row in your CSV one at a time. Your CSV needs (at minimum) these columns: Action, UserPrincipalName, DisplayName, MailNickname, Password, Department, JobTitle, UsageLocation — not every column is required for every action, but the script reads whichever ones are present.

The switch statement — this is the core logic, branching on the Action column value:

new — builds a password profile (forces a password change on first sign-in, which is best practice) and creates the user with New-MgUser.
update — first looks up the existing user by UPN, then only updates the fields that actually have a value in that CSV row (so you can leave columns blank for users you're not changing).
deprovision — looks up the user, disables their account (AccountEnabled:$false), and immediately revokes their active sign-in sessions with Revoke-MgUserSignInSession — this is important: disabling an account alone doesn't kill an already-active session/token, so this line forces them out right away.
default — catches typos or unexpected values in the Action column and marks that row "Skipped" rather than silently failing.

Try/catch per user — each row is wrapped in its own try/catch, so if one user fails (e.g. duplicate UPN, bad password policy), the script logs the error and keeps going to the next user instead of stopping the entire batch.

Logging every result — after each row, a record is added to $results capturing the UPN, action, status (Success/Failed/Skipped), any error message, and a timestamp.

Final output — once the loop finishes, results are exported to a CSV log file (so you have a permanent audit trail) and also printed to the screen as a formatted table for a quick glance.

Disconnecting — Disconnect-MgGraph cleanly ends the session at the end.

Sample CSV structure your file needs
csv
Action,UserPrincipalName,DisplayName,MailNickname,Password,Department,JobTitle,UsageLocation
new,jdoe@contoso.com,John Doe,jdoe,TempP@ss123!,Engineering,Developer,US
update,asmith@contoso.com,Alice Smith,,,,Sales Manager,
deprovision,bwilson@contoso.com,,,,,,
