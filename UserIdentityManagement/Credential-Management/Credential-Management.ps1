[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\CredentialManagement-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("UserAuthenticationMethod.ReadWrite.All", "User.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $upn = $row.UserPrincipalName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

        switch ($action) {

            "resetpassword" {
                $newPassword = if ($row.NewPassword) {
                    $row.NewPassword
                } else {
                    [System.Guid]::NewGuid().ToString("N").Substring(0, 16) + "!Aa1"
                }

                $passwordProfile = @{
                    Password = $newPassword
                    ForceChangePasswordNextSignIn = $true
                }

                Update-MgUser -UserId $user.Id -PasswordProfile $passwordProfile
                $status = "Success"
                $message = "Password reset. Temporary password: $newPassword"
            }

            "issuetap" {
                $lifetime = if ($row.TapLifetimeMinutes) { [int]$row.TapLifetimeMinutes } else { 60 }
                $usableOnce = if ($row.TapIsUsableOnce) { [System.Convert]::ToBoolean($row.TapIsUsableOnce) } else { $true }

                $tapParams = @{
                    LifetimeInMinutes = $lifetime
                    IsUsableOnce      = $usableOnce
                }

                $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $user.Id -BodyParameter $tapParams
                $status = "Success"
                $message = "TAP issued: $($tap.TemporaryAccessPass) | Expires in $lifetime minutes | UsableOnce: $usableOnce"
            }

            "listmethods" {
                $methods = Get-MgUserAuthenticationMethod -UserId $user.Id
                $methodTypes = $methods | ForEach-Object { $_.AdditionalProperties["@odata.type"] -replace "#microsoft.graph.", "" }
                $status = "Success"
                $message = "Registered methods: $($methodTypes -join ', ')"
            }

            "removemethod" {
                $methodType = $row.MethodType.Trim().ToLower()

                switch ($methodType) {
                    "phone" {
                        $phoneMethods = Get-MgUserAuthenticationPhoneMethod -UserId $user.Id
                        foreach ($phone in $phoneMethods) {
                            Remove-MgUserAuthenticationPhoneMethod -UserId $user.Id -PhoneAuthenticationMethodId $phone.Id
                        }
                        $message = "Removed $($phoneMethods.Count) phone authentication method(s)."
                    }
                    "email" {
                        $emailMethods = Get-MgUserAuthenticationEmailMethod -UserId $user.Id
                        foreach ($emailMethod in $emailMethods) {
                            Remove-MgUserAuthenticationEmailMethod -UserId $user.Id -EmailAuthenticationMethodId $emailMethod.Id
                        }
                        $message = "Removed $($emailMethods.Count) email authentication method(s)."
                    }
                    default {
                        throw "Unsupported MethodType: $($row.MethodType). Use 'phone' or 'email'."
                    }
                }
                $status = "Success"
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
