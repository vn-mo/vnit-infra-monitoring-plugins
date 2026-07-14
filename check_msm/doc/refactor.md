# Refactoring Plan: check_hp_msm.sh — SNMPv1 → SNMPv3

## Motivation

SNMPv1 transmits community strings in cleartext and provides no authentication or encryption. SNMPv3 adds:
- **Authentication** (HMAC-MD5 or HMAC-SHA)
- **Privacy/Encryption** (DES or AES)
- **Per-user access control**

---

## 1. New CLI Parameters

Remove `-C community` and replace with the following SNMPv3 options:

| Flag | Meaning | SNMPv1 equivalent |
|------|---------|-------------------|
| `-u <user>` | SNMPv3 security name | `-C community` |
| `-l <level>` | Security level: `noAuthNoPriv` / `authNoPriv` / `authPriv` | implicit in v1 |
| `-a <proto>` | Auth protocol: `MD5` or `SHA` | — |
| `-A <pass>` | Auth passphrase | — |
| `-x <proto>` | Privacy protocol: `DES` or `AES` | — |
| `-X <pass>` | Privacy passphrase | — |

Keep all existing flags: `-H`, `-t`, `-w`, `-c`, `-D`, `-l` (large).

> **Conflict**: `-l` is currently used for the "large structure" tweak. Rename that flag to `-L` to free up `-l` for the SNMPv3 security level.

---

## 2. Changes to `check_param`

- Make `-u` (security user) mandatory (exit `STATE_UNKNOWN` if missing).
- Default security level to `authPriv` if not supplied.
- Validate that `-a`/`-A` are present when level is `authNoPriv` or `authPriv`.
- Validate that `-x`/`-X` are present when level is `authPriv`.

---

## 3. Changes to `get_snmp`

Current call:
```bash
snmpget -v1 -c $community -mALL $host $oid
```

Replace with:
```bash
snmpget -v3 -u "$secuser" -l "$seclevel" \
        -a "$authproto" -A "$authpass" \
        -x "$privproto" -X "$privpass" \
        -mALL "$host" "$oid"
```

Same pattern applies to every `snmpwalk` call inside `apstatus`.

---

## 4. Changes to `apstatus` — `snmpwalk`

Current call:
```bash
snmpwalk -v1 -c $community $host -Osq $APBASE.1.2.1.1.5
```

Replace with:
```bash
snmpwalk -v3 -u "$secuser" -l "$seclevel" \
         -a "$authproto" -A "$authpass" \
         -x "$privproto" -X "$privpass" \
         "$host" -Osq $APBASE.1.2.1.1.5
```

---

## 5. Updated Help Text

Reflect the new flags and remove any reference to community string.

---

## 6. Backward Compatibility

SNMPv1 support is intentionally dropped. If the target controller does not support SNMPv3, that is a prerequisite to resolve on the network side before deploying the updated plugin.

---

## 7. Implementation Order

1. Rename `-l` (large) → `-L` everywhere in the script.
2. Add new variable declarations: `secuser`, `seclevel`, `authproto`, `authpass`, `privproto`, `privpass`.
3. Extend `getopts` string: `H:u:l:a:A:x:X:t:w:c:o:DL`.
4. Update `check_param` with new validations.
5. Update `get_snmp` function.
6. Update all `snmpwalk` calls in `apstatus`.
7. Update help string.
8. Test each check type (`msmuptime`, `msmcpuuse`, `msmramuse`, `msmpermstorage`, `msmtempstorage`, `apstatus`) against a live or simulated SNMPv3 agent.

---

## 8. Example Invocation After Refactoring

```bash
./check_hp_msm.sh \
  -H 192.168.1.1 \
  -u monitoruser \
  -l authPriv \
  -a SHA \
  -A "authSecret123" \
  -x AES \
  -X "privSecret456" \
  -t apstatus \
  -w 1 -c 2
```
