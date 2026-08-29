[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [switch]$AuditMfaStatus,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\MFA-Management-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("UserAuthenticationMethod.ReadWrite.All", "Reports.Read.All", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) {
        throw "CSV file not found at path: $CsvPath"
    }

    $requests = Import-Csv -Path $CsvPath

    foreach ($row in $requests) {

        $action = $row.Action.Trim().ToLower()
        $upn = $row.UserUPN.Trim()
        $status = "Unknown"
        $message = ""

        try {
            $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

            switch ($action) {

                "checkstatus" {
                    $regDetail = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails/$($user.Id)"

                    $status = "Success"
                    $message = "MFA Registered: $($regDetail.isMfaRegistered) | MFA Capable: $($regDetail.isMfaCapable) | Methods: $($regDetail.methodsRegistered -join ', ') | Default Method: $($regDetail.defaultMfaMethod)"
                }

                "listmethods" {
                    $allMethods = Get-MgUserAuthenticationMethod -UserId $user.Id
                    $methodTypes = $allMethods | ForEach-Object { $_.AdditionalProperties["@odata.type"] -replace "#microsoft.graph.", "" }

                    $status = "Success"
                    $message = "Registered methods: $($methodTypes -join ', ')"
                }

                "removemethod" {
                    $methodType = $row.MethodType.Trim().ToLower()

                    switch ($methodType) {
                        "phone" {
                            $items = Get-MgUserAuthenticationPhoneMethod -UserId $user.Id
                            foreach ($item in $items) { Remove-MgUserAuthenticationPhoneMethod -UserId $user.Id -PhoneAuthenticationMethodId $item.Id }
                        }
                        "email" {
                            $items = Get-MgUserAuthenticationEmailMethod -UserId $user.Id
                            foreach ($item in $items) { Remove-MgUserAuthenticationEmailMethod -UserId $user.Id -EmailAuthenticationMethodId $item.Id }
                        }
                        "microsoftauthenticator" {
                            $items = Get-MgUserAuthenticationMicrosoftAuthenticatorMethod -UserId $user.Id
                            foreach ($item in $items) { Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod -UserId $user.Id -MicrosoftAuthenticatorAuthenticationMethodId $item.Id }
                        }
                        "fido2" {
                            $items = Get-MgUserAuthenticationFido2Method -UserId $user.Id
                            foreach ($item in $items) { Remove-MgUserAuthenticationFido2Method -UserId $user.Id -Fido2AuthenticationMethodId $item.Id }
                        }
                        default {
                            throw "Unsupported MethodType: $($row.MethodType). Use phone, email, microsoftAuthenticator, or fido2."
                        }
                    }

                    $status = "Success"
                    $message = "Removed all '$methodType' method(s) for $upn. Count: $($items.Count)"
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
            UserUPN   = $upn
            Action    = $row.Action
            Status    = $status
            Message   = $message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }
}

if ($AuditMfaStatus) {
    Write-Host "Retrieving MFA registration details for all users..."
    $allRegDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails"
    $allRecords = $allRegDetails.value

    while ($allRegDetails.'@odata.nextLink') {
        $allRegDetails = Invoke-MgGraphRequest -Method GET -Uri $allRegDetails.'@odata.nextLink'
        $allRecords += $allRegDetails.value
    }

    $notCapable = $allRecords | Where-Object { $_.isMfaCapable -eq $false }
    $notRegistered = $allRecords | Where-Object { $_.isMfaRegistered -eq $false }

    Write-Host "`nTotal users evaluated: $($allRecords.Count)"
    Write-Host "Not MFA capable: $($notCapable.Count)"
    Write-Host "Not MFA registered: $($notRegistered.Count)"

    foreach ($record in $notCapable) {
        $results.Add([PSCustomObject]@{
            UserUPN   = $record.userPrincipalName
            Action    = "auditstatus"
            Status    = "NotMfaCapable"
            Message   = "User is not MFA capable. Registered methods: $($record.methodsRegistered -join ', ')"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
