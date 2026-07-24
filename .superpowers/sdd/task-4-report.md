# Task 4 Report: dnsmasq / GRUB / PXELINUX Templates

## Summary

Successfully created 3 pure template files for PXE boot configuration. All templates are ready for consumption by Task 5 (`pxe-serve.sh`) via `envsubst`.

## Files Created

1. `scripts/pxe-server/templates/dnsmasq.conf.tmpl` (17 lines)
   - ProxyDHCP configuration for dnsmasq
   - References: `${PXE_IFACE}`, `${PXE_SUBNET}`, `${PXE_NETMASK}`, `${TFTP_ROOT}`

2. `scripts/pxe-server/templates/grub.cfg.tmpl` (12 lines)
   - GRUB boot menu for UEFI clients
   - References: `${AI_VERSION}`, `${OPERATOR_IP}`, `${HTTP_PORT}`, `${AI_ISO_FILENAME}`
   - Note: Quoted `"ds=nocloud-net;s=..."` to prevent GRUB's command-line parser from splitting on `;`

3. `scripts/pxe-server/templates/pxelinux.cfg.default.tmpl` (14 lines)
   - PXELINUX boot menu for legacy BIOS clients
   - References: `${AI_VERSION}`, `${OPERATOR_IP}`, `${HTTP_PORT}`, `${AI_ISO_FILENAME}`
   - Note: Unquoted `APPEND` line (PXELINUX passes it through unparsed)

## Step 4 Verification: Variable Names

**Command:**
```bash
grep -oE '\$\{[A-Z_]+\}' scripts/pxe-server/templates/dnsmasq.conf.tmpl scripts/pxe-server/templates/grub.cfg.tmpl scripts/pxe-server/templates/pxelinux.cfg.default.tmpl | sort -u
```

**Output:**
```
${AI_ISO_FILENAME}
${AI_VERSION}
${HTTP_PORT}
${OPERATOR_IP}
${PXE_IFACE}
${PXE_NETMASK}
${PXE_SUBNET}
${TFTP_ROOT}
```

**Expected (from brief):**
- `PXE_IFACE` ✓
- `PXE_SUBNET` ✓
- `PXE_NETMASK` ✓
- `TFTP_ROOT` ✓
- `AI_VERSION` ✓
- `OPERATOR_IP` ✓
- `HTTP_PORT` ✓
- `AI_ISO_FILENAME` ✓

**Result:** EXACT MATCH ✓

## envsubst Dry-Render Verification

**Test Variables:**
```bash
PXE_IFACE=eth0
PXE_SUBNET=192.168.1.0
PXE_NETMASK=255.255.255.0
TFTP_ROOT=/srv/tftp
AI_VERSION=24.04
OPERATOR_IP=192.168.1.100
HTTP_PORT=8080
AI_ISO_FILENAME=ubuntu-24.04-server.iso
```

### dnsmasq.conf.tmpl Output
```ini
# Rendered by scripts/pxe-server/pxe-serve.sh — ProxyDHCP mode only.
# Does NOT hand out IP addresses; the existing router's DHCP server keeps
# doing that. This only answers PXE-specific DHCP options.
interface=eth0
bind-interfaces
dhcp-range=eth0,192.168.1.0,proxy,255.255.255.0

pxe-prompt="dotfiles-core autoinstall PXE", 5
pxe-service=x86PC,"Ubuntu Autoinstall (BIOS)",pxelinux.0
pxe-service=BC_EFI,"Ubuntu Autoinstall (UEFI)",bootx64.efi

enable-tftp
tftp-root=/srv/tftp

log-dhcp
no-daemon
```
✓ Valid dnsmasq syntax, all variables substituted

### grub.cfg.tmpl Output
```
set default="0"
set timeout=10

menuentry 'Ubuntu 24.04 Server (dotfiles-core autoinstall)' {
    linux /vmlinuz ip=dhcp url=http://192.168.1.100:8080/ubuntu-24.04-server.iso "autoinstall" "ds=nocloud-net;s=http://192.168.1.100:8080/autoinstall/" cloud-config-url=/dev/null ---
    initrd /initrd
}

menuentry 'Boot from local disk' {
    exit 1
}
```
✓ Valid GRUB syntax, all variables substituted, quoted ds= parameter preserved

### pxelinux.cfg.default.tmpl Output
```
DEFAULT autoinstall
TIMEOUT 100
PROMPT 0

LABEL autoinstall
  MENU LABEL Ubuntu 24.04 Server (dotfiles-core autoinstall)
  KERNEL vmlinuz
  INITRD initrd
  APPEND ip=dhcp url=http://192.168.1.100:8080/ubuntu-24.04-server.iso autoinstall ds=nocloud-net;s=http://192.168.1.100:8080/autoinstall/ cloud-config-url=/dev/null

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0
```
✓ Valid PXELINUX syntax, all variables substituted

## Commit

```
3ff94f6 feat: dnsmasq/GRUB/PXELINUXのPXEブート設定テンプレートを追加
```

**Files changed:** 3 files, 40 insertions(+)

## Self-Review

✓ All 3 template files created exactly as specified in brief
✓ Variable names match expected list (8 variables, all present)
✓ envsubst renders without errors
✓ Output syntax is valid for each tool (dnsmasq, GRUB, PXELINUX)
✓ Quoted `ds=` parameter in grub.cfg.tmpl per brief note
✓ Unquoted APPEND in pxelinux.cfg.default.tmpl per brief note
✓ Commit message in Japanese Conventional Commits format
✓ No linting issues (templates are config files, not code)

## Concerns

None. Task is complete and ready for Task 5 integration.

## Fix Round 1 (cosmetic dhcp-range cleanup)

**Issue:** Reviewer flagged `dhcp-range=${PXE_IFACE},${PXE_SUBNET},proxy,${PXE_NETMASK}` as a critical bug, theorizing that dnsmasq's IPv4 dhcp-range grammar has no interface field.

**Verification:** Controller independently tested with dnsmasq 2.93 and confirmed the original syntax is functionally correct (dnsmasq treats bare `${PXE_IFACE}` as legacy shorthand for `set:eth0`, not a parse error). However, the line IS legitimately confusing — readers can mistake the bare token for either "the interface this range applies to" (it isn't) or a match-restricting tag (it isn't).

**Fix:** Removed the redundant/confusing implicit tag from `dhcp-range` line. Interface scoping is already fully handled by the existing `interface=${PXE_IFACE}` + `bind-interfaces` lines.

**Changed:**
```
dhcp-range=${PXE_IFACE},${PXE_SUBNET},proxy,${PXE_NETMASK}
```
**to:**
```
dhcp-range=${PXE_SUBNET},proxy,${PXE_NETMASK}
```

**dnsmasq --test Output:**
```
dnsmasq: syntax check OK.
```

**Variable Check:** `PXE_IFACE` still present in `interface=` line (verified via grep).
