[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\DeviceAssociation-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Device.ReadWrite.All", "Directory.ReadWrite.All", "Group.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $deviceName = $row.DeviceDisplayName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $device = Get-MgDevice -Filter "displayName eq '$deviceName'" -ErrorAction Stop

        switch ($action) {

            "setowner" {
                $newOwner = Get-MgUser -Filter "userPrincipalName eq '$($row.UserUPN.Trim())'" -ErrorAction Stop

                $currentOwners = Get-MgDeviceRegisteredOwner -DeviceId $device.Id
                foreach ($currentOwner in $currentOwners) {
                    Remove-MgDeviceRegisteredOwnerByRef -DeviceId $device.Id -DirectoryObjectId $currentOwner.Id
                }

                New-MgDeviceRegisteredOwnerByRef -DeviceId $device.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($newOwner.Id)"
                }

                $status = "Success"
                $message = "Set $($row.UserUPN) as registered owner of '$deviceName' (previous owner(s) removed: $($currentOwners.Count))."
            }

            "removeowner" {
                $currentOwners = Get-MgDeviceRegisteredOwner -DeviceId $device.Id

                if ($currentOwners.Count -eq 0) {
                    throw "Device '$deviceName' has no registered owner to remove."
                }

                foreach ($currentOwner in $currentOwners) {
                    Remove-MgDeviceRegisteredOwnerByRef -DeviceId $device.Id -DirectoryObjectId $currentOwner.Id
                }

                $status = "Success"
                $message = "Removed $($currentOwners.Count) registered owner(s) from '$deviceName'."
            }

            "addregistereduser" {
                $userToAdd = Get-MgUser -Filter "userPrincipalName eq '$($row.UserUPN.Trim())'" -ErrorAction Stop

                New-MgDeviceRegisteredUserByRef -DeviceId $device.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($userToAdd.Id)"
                }

                $status = "Success"
                $message = "Added $($row.UserUPN) as a registered user of '$deviceName'."
            }

            "removeregistereduser" {
                $userToRemove = Get-MgUser -Filter "userPrincipalName eq '$($row.UserUPN.Trim())'" -ErrorAction Stop
                Remove-MgDeviceRegisteredUserByRef -DeviceId $device.Id -DirectoryObjectId $userToRemove.Id

                $status = "Success"
                $message = "Removed $($row.UserUPN) as a registered user of '$deviceName'."
            }

            "addtogroup" {
                $targetGroup = Get-MgGroup -Filter "displayName eq '$($row.GroupName.Trim())'" -ErrorAction Stop

                New-MgGroupMemberByRef -GroupId $targetGroup.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($device.Id)"
                }

                $status = "Success"
                $message = "Added '$deviceName' to group '$($row.GroupName)'."
            }

            "removefromgroup" {
                $targetGroup = Get-MgGroup -Filter "displayName eq '$($row.GroupName.Trim())'" -ErrorAction Stop
                Remove-MgGroupMemberByRef -GroupId $targetGroup.Id -DirectoryObjectId $device.Id

                $status = "Success"
                $message = "Removed '$deviceName' from group '$($row.GroupName)'."
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
        DeviceDisplayName = $deviceName
        Action            = $row.Action
        Status            = $status
        Message           = $message
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
