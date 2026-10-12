# Device-Association-Management.ps1 — Explanation

## What this script does
Manages three distinct relationships a device can have: its single **registered owner**, its (potentially multiple) **registered users**, and its **group memberships** — used for scenarios like targeting device-based Conditional Access policies or Intune configuration profiles at specific device groups.

## Three different relationships, briefly

- **Registered owner** — as covered in the Graph API toolkit's `Devices.md`, a device can have **at most one** registered owner, typically set automatically when someone cloud-joins the device. This script's `setowner` action respects that constraint by explicitly clearing any existing owner before adding the new one.
- **Registered users** — a separate, **multi-value** collection — everyone who has signed into or registered with the device, distinct from ownership. A shared device might have several registered users but only one (or zero) owner.
- **Group membership** — devices, like users, can be members of security groups — commonly used to scope Conditional Access policies or Intune configuration/compliance profiles to specific sets of devices rather than applying tenant-wide.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `Device.ReadWrite.All`, `Directory.ReadWrite.All`, and `Group.ReadWrite.All` — covering all three relationship types this script touches.

**Looking up the device once per row**
The device lookup by `DeviceDisplayName` happens before the switch statement, since every action needs it.

**The switch statement (core logic)**

- **`setowner`** — this is the most careful action here, specifically because ownership is meant to be single-valued. It first retrieves **any** existing owners (there's normally zero or one, but the code handles a list defensively), removes each one, and only then adds the new owner. This "clear first, then set" pattern avoids ending up with a device that technically has multiple registered owners, which would be an inconsistent state even though the API wouldn't necessarily stop you from creating it via a naive `addowner`-only approach.

- **`removeowner`** — removes whatever owner(s) currently exist, with a clear error if there isn't one to remove in the first place.

- **`addregistereduser`** — adds a user to the device's registered users collection via `New-MgDeviceRegisteredUserByRef`. Unlike ownership, this is additive — a device can accumulate several registered users over time as different people sign in.

- **`removeregistereduser`** — removes one specific user from that collection, leaving any others untouched.

- **`addtogroup`** — adds the device itself (using its own directory object ID) as a member of a group, using the same `New-MgGroupMemberByRef` pattern seen in the earlier group and AU scripts — devices are just another type of directory object that can belong to a group's membership collection.

- **`removefromgroup`** — the mirror action, removing the device from the group.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,DeviceDisplayName,UserUPN,GroupName
setowner,LAPTOP-JDOE01,jdoe@contoso.com,
addregistereduser,SHARED-KIOSK-01,asmith@contoso.com,
addregistereduser,SHARED-KIOSK-01,bwilson@contoso.com,
addtogroup,LAPTOP-JDOE01,,Engineering Managed Devices
removefromgroup,OLD-LAPTOP-02,,Engineering Managed Devices
removeowner,DECOMMISSIONED-01,,
```

## Notes
- **Device group membership is a common building block for Conditional Access and Intune targeting** — if you're setting up policies scoped to "only company-owned laptops" or similar, the device needs to be a group member first, which is exactly what `addtogroup` provides for bulk onboarding of many devices at once.
- **`setowner`'s "clear existing owner first" behavior is deliberate**, not an oversight — if you only want to add an owner to a device that definitely has none yet, you could technically skip straight to the `New-MgDeviceRegisteredOwnerByRef` call, but keeping the clear-then-set pattern makes this action safe to run repeatedly and idempotently against any device, regardless of its current state.
- Registered users accumulate over time on shared/kiosk-style devices — periodically reviewing and trimming that list (removing people who've moved teams or left, similar in spirit to the group membership cleanup script from `GroupAccessManagement`) is worth doing rather than letting it grow indefinitely.
