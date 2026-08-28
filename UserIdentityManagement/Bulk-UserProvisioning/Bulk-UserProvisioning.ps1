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
