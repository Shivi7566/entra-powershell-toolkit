[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$DefaultRedirectUrl = "https://myapps.microsoft.com",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\GuestB2BLifecycle-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("User.Invite.All", "User.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$guests = Import-Csv -Path $CsvPath

foreach ($row in $guests) {

    $action = $row.Action.Trim().ToLower()
    $email = $row.Email.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "invite" {
                $redirectUrl = if ($row.RedirectUrl) { $row.RedirectUrl } else { $DefaultRedirectUrl }

                $invitationParams = @{
                    InvitedUserEmailAddress = $email
                    InvitedUserDisplayName  = $row.DisplayName
                    InviteRedirectUrl       = $redirectUrl
                    SendInvitationMessage   = $true
                }

                if ($row.InviteMessage) {
                    $invitationParams["InvitedUserMessageInfo"] = @{
                        CustomizedMessageBody = $row.InviteMessage
                    }
                }

                $invitation = New-MgInvitation -BodyParameter $invitationParams
                $status = "Success"
                $message = "Invitation sent. Guest ObjectId: $($invitation.InvitedUser.Id)"
            }

            "resend" {
                $redirectUrl = if ($row.RedirectUrl) { $row.RedirectUrl } else { $DefaultRedirectUrl }

                $existingGuest = Get-MgUser -Filter "mail eq '$email' and userType eq 'Guest'" -ErrorAction Stop

                if (-not $existingGuest) {
                    throw "No existing guest found with email $email — cannot resend."
                }

                $invitationParams = @{
                    InvitedUserEmailAddress = $email
                    InvitedUserDisplayName  = $existingGuest.DisplayName
                    InviteRedirectUrl       = $redirectUrl
                    SendInvitationMessage   = $true
                }

                New-MgInvitation -BodyParameter $invitationParams | Out-Null
                $status = "Success"
                $message = "Invitation resent."
            }

            "checkstatus" {
                $existingGuest = Get-MgUser -Filter "mail eq '$email' and userType eq 'Guest'" -Property "displayName,externalUserState,externalUserStateChangeDateTime" -ErrorAction Stop

                if (-not $existingGuest) {
                    $status = "NotFound"
                    $message = "No guest user found with this email."
                }
                else {
                    $status = "Success"
                    $message = "State: $($existingGuest.ExternalUserState) | Changed: $($existingGuest.ExternalUserStateChangeDateTime)"
                }
            }

            "remove" {
                $existingGuest = Get-MgUser -Filter "mail eq '$email' and userType eq 'Guest'" -ErrorAction Stop

                if (-not $existingGuest) {
                    throw "No existing guest found with email $email — cannot remove."
                }

                Remove-MgUser -UserId $existingGuest.Id
                $status = "Success"
                $message = "Guest user removed."
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
        Email     = $email
        Action    = $row.Action
        Status    = $status
        Message   = $message
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
