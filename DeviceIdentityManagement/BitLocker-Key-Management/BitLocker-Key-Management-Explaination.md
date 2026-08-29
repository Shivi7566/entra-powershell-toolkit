# BitLocker-Key-Management.ps1 — Explanation

## What this script does
Retrieves a specific device's BitLocker recovery key when someone is locked out, and separately audits the whole tenant's Windows device fleet to find devices that **should** have an escrowed recovery key but don't — a gap that could mean genuinely unrecoverable data if that device ever gets locked out.

## Step-by-step breakdown

**Parameters block**
Two independent modes:
- `-CsvPath` (optional) — for retrieving specific keys, one device per row.
- `-AuditEscrowGaps` (optional switch) — a tenant-wide scan for missing escrow, independent of the CSV.

**Connecting to Graph**
Requests `BitlockerKey.Read.All` (needed specifically to retrieve the actual key value), `BitlockerKey.ReadBasic.All` (metadata-only access, sufficient for the gap audit), and `Device.Read.All`.

**Part 1 — Retrieving a specific recovery key (`-CsvPath`)**

This uses `Invoke-MgGraphRequest` directly rather than a dedicated cmdlet, and it's a deliberate **two-step process**, matching exactly how the Graph API toolkit's `Devices.md` describes this endpoint:

1. **First call** — lists recovery key metadata filtered by `deviceId`, to find the key's own internal `id` (this is *not* the same as the device's ID — recovery keys have their own object identity).
2. **Second call** — fetches that specific key by its ID, explicitly adding `?$select=key` to the URL. This is the step that actually returns the real recovery key string — and, as documented in the Graph API toolkit, **this specific call always generates a mandatory audit log entry**, by design, with no way to retrieve the actual key value silently. That's intentional on Microsoft's part: BitLocker keys are sensitive enough that every retrieval should be traceable.

The retrieved key is written into the log message, carrying the same "protect this immediately" handling as every other credential-bearing script in this repo.

**Part 2 — Escrow gap audit (`-AuditEscrowGaps`)**

This runs independently of the CSV, and is arguably the more valuable long-term use of this script:

1. Fetches every device where `operatingSystem eq 'Windows'` (BitLocker is a Windows-specific feature — no point checking macOS/iOS/Android devices here).
2. Fetches **all** BitLocker recovery key metadata across the tenant in one call, then builds a simple list of every `deviceId` that has at least one key on file.
3. For every Windows device **not** appearing in that list, flags it as a `Gap` — meaning: if that specific device ever gets BitLocker-locked (a common outcome after certain firmware updates, hardware changes, or forgotten passwords), **there may be no way to recover the data on it**, since nothing is backed up to Entra ID to unlock it.

## Sample CSV structure (for key retrieval)

```csv
DeviceId
a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

## Sample escrow audit usage

```powershell
.\BitLocker-Key-Management.ps1 -AuditEscrowGaps
```

## Notes
- **The retrieved recovery key value is genuinely one-time-sensitive and always audit-logged on Microsoft's side too** — there's no way around that audit trail, and there shouldn't be; it's a legitimate security control, not a script limitation. Handle the log output from this script with the same discipline as the break-glass and credential scripts elsewhere in this repo.
- **The escrow gap audit is the more proactive, preventative half of this script** — running it regularly (e.g. monthly) catches devices that were encrypted without their key ever making it to Entra ID, often due to a policy misconfiguration or a device that went through initial setup outside normal provisioning. Better to find that gap during routine review than during an actual lockout emergency.
- A device appearing in the escrow gap list doesn't necessarily mean it's unencrypted — it might genuinely not have BitLocker enabled at all, which is a separate (and also worth investigating) condition from "encrypted but key not backed up." This script doesn't currently distinguish between the two; cross-referencing against your organization's encryption policy/compliance reporting would be the next step to tell them apart.
