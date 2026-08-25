# Bluetooth — Pairing & Audio (Sony WH-1000XM4)

**Machine:** Acer Predator PT516-52s (`triton500se`) · **Last verified:** 2026-08-20
**Controller:** `F4:26:79:D0:27:07` (hci0, `usb:v1D6Bp0246d0557`)
**Device:** Sony WH-1000XM4 — `F8:4E:17:4C:12:DF`
**Stack:** `bluez` 5.87-2.1 · `blueman` 2.4.6-2.1 · PipeWire 1.6.8 + WirePlumber 0.5.15

> **fish-shell note.** The multi-command pairing block in §3 uses a brace group (`{ … } | bluetoothctl`),
> which is bash/zsh syntax. **fish uses `begin; … ; end` instead** — the fish-native version is given
> inline. Every other command in this doc runs identically in fish and bash.

This doc exists because the XM4 hit a failure mode that looks like "still paired, just won't
connect" and is **not** fixable by clicking Connect in blueman. Recorded after the 2026-08-20 fix.

---

## 0. TL;DR — the recovery, start to finish

```bash
bluetoothctl remove F8:4E:17:4C:12:DF
# → headset OFF, then hold power ~7s until "Bluetooth pairing" + double-flashing blue LED
# → then run the pairing block in §3, then:
bluetoothctl trust F8:4E:17:4C:12:DF
bluetoothctl connect F8:4E:17:4C:12:DF
```

Three things that make this fail if skipped: the headset must be in **real pairing mode** (not just
powered on), `pair` needs **discovery live in the same `bluetoothctl` session**, and `trust` must be
re-applied after pairing or nothing auto-reconnects.

---

## 1. The failure mode — `br-connection-key-missing`

**Symptom.** `bluetoothctl info` reports the device as fully bonded:

```
Paired: yes
Bonded: yes
Trusted: yes
Connected: no
```

…yet every connection attempt dies immediately:

```bash
bluetoothctl connect F8:4E:17:4C:12:DF
# Attempting to connect to F8:4E:17:4C:12:DF
# [CHG] Device F8:4E:17:4C:12:DF Connected: yes
# Failed to connect: org.bluez.Error.Failed br-connection-key-missing
```

**Cause.** The bond is **one-sided**. This PC still holds the link key; the headphones no longer do.
BlueZ therefore offers a key the headset cannot match, and the BR/EDR link is torn down.

**Why it happens on the XM4 specifically.** The WH-1000XM4 stores only **8 pairings** and silently
evicts the oldest when a 9th device pairs. Pair enough phones/tablets/TVs to the headset and this PC
gets dropped from its table — without any notification on either side. A headset factory reset does
the same thing.

**This is not repairable.** There is no way to re-negotiate a half-bond; the stale key must be
deleted on the host and the pairing redone from scratch.

**Red herring.** While the bond is broken, `journalctl -u bluetooth.service` also logs:

```
src/profile.c:ext_connect() Hands-Free Voice gateway failed connect to F8:4E:17:4C:12:DF: Permission denied (13)
```

That is **downstream of the dead bond**, not a separate fault. It disappeared on its own after
re-pairing. Don't chase it unless it persists *after* a successful pair.

---

## 2. Diagnosis — confirm before you delete anything

Removing a bond is destructive (it forces the physical pairing-mode dance), so verify the stack is
otherwise healthy first.

```bash
# Stack present and running?
pacman -Q bluez bluez-utils blueman pipewire pipewire-pulse wireplumber
systemctl is-enabled bluetooth.service; systemctl is-active bluetooth.service
rfkill list                          # all three must show "Soft blocked: no / Hard blocked: no"

# Controller and known devices
bluetoothctl list                    # adapters
bluetoothctl show                    # Powered / Discovering / UUIDs
bluetoothctl devices Paired
bluetoothctl info F8:4E:17:4C:12:DF  # Paired / Bonded / Trusted / Connected

# Audio side — is there a bluez card at all?
pactl list cards short
pactl list sinks short
pactl get-default-sink

# The logs that tell the story
journalctl -b -u bluetooth.service --no-pager | tail -40
```

**The command that produces the actual diagnosis** is the connect attempt itself — the error string
is the whole case:

```bash
bluetoothctl connect F8:4E:17:4C:12:DF
```

| Error | Meaning |
|---|---|
| `br-connection-key-missing` | One-sided bond → **full re-pair required** (this doc) |
| `Device ... not available` | Not in the discovery cache → scan first (§3) |
| `org.bluez.Error.ConnectionAttemptFailed` | Headset not in pairing mode, or discovery not live |
| `org.bluez.Error.AlreadyConnected` | Already up; check PipeWire routing instead (§4) |

Healthy signs to confirm *before* blaming the bond: `bluetoothd` logs `Endpoint registered:
.../A2DPSource/{sbc,aac,ldac,…}` at startup (WirePlumber offered its codecs), and `rfkill` shows
nothing blocked.

---

## 3. The fix

### a. Clear the dead bond

```bash
bluetoothctl disconnect F8:4E:17:4C:12:DF   # it can sit in a half-connected state
bluetoothctl remove F8:4E:17:4C:12:DF
bluetoothctl devices                        # XM4 should no longer be listed
```

### b. Put the XM4 into real pairing mode — manual step

**Powering the headphones on is not enough.** A powered-on XM4 retries the dead bond and fails
identically. It must advertise as pairable:

1. **Power the headphones OFF.**
2. **Hold the power button ~7 seconds** — past the normal power-on chime — until you hear
   **"Bluetooth pairing"** and the blue LED **double-flashes** repeatedly.
3. Keep them near the laptop.

> **Turn Bluetooth off on your phone first.** If the XM4 re-grabs the phone it leaves pairing mode
> early, and the window is only ~5 minutes. This is the single most common reason the sequence below
> fails on the first try.

### c. Pair — discovery must be live in the same session

The obvious approach **does not work**:

```bash
# ✗ FAILS — discovery stops, the device ages out of the cache before `pair` runs
bluetoothctl scan on &
bluetoothctl pair F8:4E:17:4C:12:DF
#   → "Device F8:4E:17:4C:12:DF not available"
#   → or "Failed to pair: org.bluez.Error.ConnectionAttemptFailed"
```

`pair` needs `scan on` **active inside the same `bluetoothctl` session**. Feed one interactive
session instead — bash/zsh:

```bash
{ echo "power on"
  echo "agent on"
  echo "default-agent"
  echo "scan on"
  sleep 15                          # let discovery actually find it
  echo "pair F8:4E:17:4C:12:DF"
  sleep 25                          # let the handshake finish
  echo "quit"
} | bluetoothctl
```

fish-native equivalent:

```fish
begin
  echo "power on"
  echo "agent on"
  echo "default-agent"
  echo "scan on"
  sleep 15
  echo "pair F8:4E:17:4C:12:DF"
  sleep 25
  echo "quit"
end | bluetoothctl
```

Look for **`Pairing successful`**. The device disconnecting right after pairing is normal.

### d. Trust and connect — both required

```bash
bluetoothctl trust F8:4E:17:4C:12:DF     # ← removal cleared this; without it, NO auto-reconnect
bluetoothctl connect F8:4E:17:4C:12:DF
```

`trust` is the step that makes the headset reconnect by itself on power-on. Skipping it leaves a
working-but-manual pairing that looks fine until the next power cycle.

---

## 4. Verification

```bash
bluetoothctl info F8:4E:17:4C:12:DF | grep -E 'Paired|Bonded|Trusted|Connected'

# PipeWire must have built a bluez card and sink
pactl list cards short | grep bluez           # bluez_card.F8_4E_17_4C_12_DF
pactl list sinks short | grep bluez           # bluez_output.F8_4E_17_4C_12_DF.1 ... RUNNING
pactl get-default-sink

# Active profile and negotiated codec
pactl list cards | awk '/bluez_card/{f=1} f&&/Active Profile/{print; exit}'
pactl list sinks | awk '/bluez_output/,0' | grep -a codec

# Battery — works on a STOCK /etc/bluetooth/main.conf (no Experimental=true needed on BlueZ 5.87)
busctl get-property org.bluez /org/bluez/hci0/dev_F8_4E_17_4C_12_DF \
       org.bluez.Battery1 Percentage
```

**Verified good state (2026-08-20):**

| Check | Result |
|---|---|
| Bond | `Paired: yes` · `Bonded: yes` · `Trusted: yes` · `Connected: yes` |
| Card | `bluez_card.F8_4E_17_4C_12_DF` |
| Sink | `bluez_output.F8_4E_17_4C_12_DF.1` — RUNNING, and the default sink |
| Active profile | `a2dp-sink` — High Fidelity Playback |
| Codec | **AAC** (`api.bluez5.codec = "aac"`) |
| Battery | `org.bluez.Battery1` live — read 70% |

**The real acceptance test** — the one that proves the bond is healthy on *both* sides, which is
exactly what was broken: **power the XM4 off and on, and confirm it reconnects unattended.**
Confirmed working 2026-08-20.

---

## 5. Codecs — why there is no LDAC

The A2DP profiles this machine negotiated with the XM4:

```
a2dp-sink-sbc      High Fidelity Playback (A2DP Sink, codec SBC)
a2dp-sink-sbc_xq   High Fidelity Playback (A2DP Sink, codec SBC-XQ)
a2dp-sink          High Fidelity Playback (A2DP Sink, codec AAC)   ← active
headset-head-unit  Headset Head Unit (HSP/HFP, codec MSBC)
```

**No LDAC — and that is the headset's doing, not a missing package.** The PC side is complete:
`/usr/lib/spa-0.2/bluez5/libspa-codec-bluez5-ldac.so` is installed, and `bluetoothd` registers
`/MediaEndpoint/A2DPSource/ldac` at startup. The PC offered LDAC; **the XM4 never advertised it.**

On the WH-1000XM4, LDAC is disabled by the headset when either:

- **"Priority on Stable Connection"** is selected instead of *Priority on Sound Quality*, or
- **multipoint** ("connect to 2 devices simultaneously") is enabled.

Both live in the **Sony Headphones Connect** app. Nothing on this machine can change it — do not go
editing WirePlumber configs looking for it. AAC is a good result and is what this setup runs.

> Switching profile manually if ever needed:
> `pactl set-card-profile bluez_card.F8_4E_17_4C_12_DF a2dp-sink`
> Use `headset-head-unit` only when you need the **microphone** — HFP drops playback to
> narrow/wideband voice quality.

---

## 6. Notes on this system

- **No `main.conf` changes were needed.** `/etc/bluetooth/main.conf` is entirely stock (all lines
  commented). In particular `Experimental = true` is **not** required for battery reporting on BlueZ
  5.87 — `org.bluez.Battery1` is exposed without it. Don't add it cargo-cult.
- **`AutoEnable=true`** is the BlueZ default (commented at `main.conf:397`), so the controller powers
  on at boot without intervention.
- **Waybar** already renders this: the `bluetooth` module in `~/.config/waybar/config.jsonc` uses
  `format-connected-battery = " {device_battery_percentage}%"`, click → `blueman-manager`,
  right-click → `rfkill toggle bluetooth`.
- **The compositor is irrelevant here.** Nothing about this fix touches Hyprland, and none of it is
  affected by the `env.conf` caveat about Walker-launched apps — `bluetoothd` is a system service.

---

## 7. If it happens again

It likely will, since the trigger is the XM4's 8-device eviction. Straight to §0. The tell is
`br-connection-key-missing` — if you see any *other* error, re-read §2 before removing the bond,
because a removal you didn't need costs you the pairing-mode dance for nothing.
