[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\CredentialRotation-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Application.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $appName = $row.AppDisplayName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $app = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction Stop

        switch ($action) {

            "listcredentials" {
                $secretSummary = $app.PasswordCredentials | ForEach-Object {
                    $daysLeft = ([datetime]$_.EndDateTime - (Get-Date)).Days
                    "$($_.DisplayName) [KeyId: $($_.KeyId)] expires $($_.EndDateTime) ($daysLeft days left)"
                }

                $certSummary = $app.KeyCredentials | ForEach-Object {
                    $daysLeft = ([datetime]$_.EndDateTime - (Get-Date)).Days
                    "$($_.DisplayName) [KeyId: $($_.KeyId)] expires $($_.EndDateTime) ($daysLeft days left)"
                }

                $status = "Success"
                $message = "Secrets: [$($secretSummary -join ' | ')] Certificates: [$($certSummary -join ' | ')]"
            }

            "addsecret" {
                $expiryMonths = if ($row.ExpiryMonths) { [int]$row.ExpiryMonths } else { 6 }
                $description = if ($row.SecretDescription) { $row.SecretDescription } else { "Added via automation $(Get-Date -Format 'yyyy-MM-dd')" }

                $passwordCredential = @{
                    DisplayName = $description
                    EndDateTime = (Get-Date).AddMonths($expiryMonths)
                }

                $newSecret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential $passwordCredential

                $status = "Success"
                $message = "New secret added, expires in $expiryMonths month(s). SECRET VALUE (store immediately, visible only once): $($newSecret.SecretText)"
            }

            "removesecret" {
                $matchingSecret = $app.PasswordCredentials | Where-Object { $_.DisplayName -eq $row.SecretDescription.Trim() }

                if (-not $matchingSecret) {
                    throw "No secret found on '$appName' matching description '$($row.SecretDescription)'."
                }

                foreach ($secretToRemove in $matchingSecret) {
                    Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $secretToRemove.KeyId
                }

                $status = "Success"
                $message = "Removed secret(s) matching '$($row.SecretDescription)' from '$appName'."
            }

            "rotatesecret" {
                $expiryMonths = if ($row.ExpiryMonths) { [int]$row.ExpiryMonths } else { 6 }
                $description = "Rotated $(Get-Date -Format 'yyyy-MM-dd')"

                $oldKeyIds = $app.PasswordCredentials | ForEach-Object { $_.KeyId }

                $newSecret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{
                    DisplayName = $description
                    EndDateTime = (Get-Date).AddMonths($expiryMonths)
                }

                foreach ($oldKeyId in $oldKeyIds) {
                    Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $oldKeyId
                }

                $status = "Success"
                $message = "Rotated: added new secret, removed $($oldKeyIds.Count) old secret(s). NEW SECRET VALUE (store immediately, visible only once): $($newSecret.SecretText)"
            }

            "addcertificate" {
                if (-not (Test-Path $row.CertFilePath)) {
                    throw "Certificate file not found at path: $($row.CertFilePath)"
                }

                $certBytes = [System.IO.File]::ReadAllBytes($row.CertFilePath)
                $certBase64 = [System.Convert]::ToBase64String($certBytes)
                $certObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($row.CertFilePath)

                $newKeyCredential = @{
                    Type      = "AsymmetricX509Cert"
                    Usage     = "Verify"
                    Key       = [System.Convert]::FromBase64String($certBase64)
                    DisplayName = if ($row.SecretDescription) { $row.SecretDescription } else { "Certificate added $(Get-Date -Format 'yyyy-MM-dd')" }
                }

                $updatedKeyCredentials = @($app.KeyCredentials) + $newKeyCredential

                Update-MgApplication -ApplicationId $app.Id -KeyCredentials $updatedKeyCredentials

                $status = "Success"
                $message = "Certificate added. Thumbprint: $($certObject.Thumbprint), expires $($certObject.NotAfter)."
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
        AppDisplayName = $appName
        Action         = $row.Action
        Status         = $status
        Message        = $message
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
