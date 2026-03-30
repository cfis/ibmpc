# Part 10: Installing the 3COM NIC

With all the required software transferred to the IBM PC via serial ([Part 9](part9-tcp-ip.md)), it was time to install the 3COM Etherlink III 3C509B-TPO network card.

## 3ccfg.exe Works After All

In Part 9, `3ccfg.exe` (the NESTOR configuration utility) failed with "Program too big to fit in memory." This turned out to be caused by the [CR/LF bug](part9-tcp-ip.md#bug-record-count-protocol-corruption) in the serial transfer — the file was corrupted during transfer, not actually too large. After fixing the sender to transmit `\r` only (no `\n`), `3ccfg.exe` transferred correctly and ran fine on the PC.

## Custom Configuration Utility

Before discovering that `3ccfg.exe` worked, a lightweight replacement was written in 8086 assembly: `3c5x9cfg.com` (under 3KB vs 234KB for `3ccfg.exe`). It reads and writes the 3C509B's EEPROM to configure IRQ, I/O base, and transceiver type. It uses the ID port (0x110) for card discovery and Window 0 registers for EEPROM access. The source is at `src/3c5x9cfg.asm` with a C reference implementation at `src/3c5x9cfg.c`.

**Important:** The custom utility turned out to have an EEPROM write issue — it correctly sets IRQ, I/O, and transceiver, but leaves other EEPROM words in an inconsistent state that the 3C509 packet driver rejects. The `3ccfg.exe` utility writes a complete, valid EEPROM image and should be used for configuration instead. The custom utility is still useful for reading current settings.

## First Install Attempt: Machine Won't Boot

After removing the serial card from slot 2 and installing the NIC, the IBM PC refused to boot. Symptoms:

- Power on, hard drive spins, floppy spins
- Green cursor appears in the top-left corner
- BIOS POST hangs — never reaches a DOS prompt
- No error messages

Removing the NIC and the PC booted normally, confirming the card was the problem.

## The Fix: Swap Slots

The IBM PC 5150 has 5 ISA slots, all occupied:

| Slot | Card |
|------|------|
| 1 | Video (MDA) |
| 2 | Serial card (being replaced) / Floppy controller |
| 3 | Floppy controller / NIC |
| 4 | Hard drive controller |
| 5 | 256KB RAM expansion |

The NIC wouldn't boot in slot 2 (the serial card's old slot). The theory was either a slot-specific conflict or a PnP negotiation issue with the adjacent card.

The solution: swap the floppy controller and NIC slots. Move the floppy controller from slot 3 to slot 2, and install the NIC in slot 3.

This worked — the PC booted with all cards installed (minus the serial card).

## Disabling PnP

The 3C509B supports Plug and Play, but the IBM PC 5150's BIOS (1981) predates PnP by over a decade. Some BIOS implementations get stuck in a PnP negotiation loop when they encounter the card. Even though the slot swap fixed the immediate boot issue, PnP was disabled as a precaution:

```
3CCFG.EXE configure /pnp:disabled
```

The program reported success and required a reboot.

## Initial Card Settings

After disabling PnP and rebooting, `3c5x9cfg.com` reported:

```
Found 3C509B at 0300h

  MAC:    00:50:04:CE:43:0F
  I/O:    0300h
  IRQ:    10
  Xcvr:   TP (10baseT)
  Cksum:  D603 (ERROR)
```

Two problems:

### Wrong IRQ

The card defaulted to IRQ 10, but the IBM PC 5150 only has IRQs 0-7. The 5150 uses a single Intel 8259 PIC (Programmable Interrupt Controller). IRQs 8-15 require a second cascaded PIC, which was introduced with the IBM AT (1984). IRQ 10 will never fire on the 5150.

The correct setting for the 5150 is IRQ 3 (typically used for COM2, which is not installed).

### Checksum Error

The EEPROM checksum doesn't match. This may be from a previous incomplete configuration or factory defaults that were never finalized.

## Configuring the Card

First attempt was with the custom utility:

```
3C5X9CFG /IRQ:3 /IO:340 /XCVR:TP
```

The utility reported success and the checksum verified OK after reboot. However, the 3C509 packet driver refused to initialize with these settings — it could read the EEPROM but failed during board initialization. The `3ccfg.exe` utility also reported "NIC configuration is unreadable."

The fix was to use `3ccfg.exe` to do a full PnP reset and write a complete configuration:

```
3CCFG /PNPRST
3CCFG configure /int:3 /iobase:300 /xcvr:tp /pnp:disabled /optimize:dos /modem:none
```

Note: `3ccfg` auto-detects which I/O addresses are in use. Several addresses (including 340h) were reported as in use. The final configuration ended up at I/O 300h.

After rebooting, the packet driver loaded successfully:

```
3C509 0x60
```

A follow-up plan for making `3c5x9cfg.com` reliable enough to replace this path is tracked in [3C5X9CFG Plan](3c5x9cfg-plan.md).

## Setting Up mTCP

### Configuration File

The `sample.cfg` from the mTCP package was transferred but had Unix line endings (LF only), which EDLIN corrupted when trying to edit. A minimal config was created from scratch using `COPY CON`:

```
COPY CON C:\BAS\MTCP.CFG
PACKETINT 0x60
HOSTNAME PC5150
FTPSRV_PASSWORD_FILE C:\BAS\FTPPASS.TXT
^Z
```

An FTP password file was also created:

```
COPY CON C:\BAS\FTPPASS.TXT
anonymous [email] [none] [any] all
^Z
```

### Getting an IP Address

```
SET MTCPCFG=C:\BAS\MTCP.CFG
DHCP
```

DHCP initially timed out but succeeded on retry, assigning **10.0.0.201** to the PC. The PC was on the network.

### Testing Internet Connectivity

FTP to a public server confirmed the mTCP stack was fully functional:

```
FTP ftp.cs.brown.edu
```

Connected and logged in successfully with anonymous FTP.

## The Networking Problem: Local Traffic Blocked

While the PC can reach the internet (FTP to Brown University works), the PC and laptop **cannot communicate with each other**. Symptoms:

- Laptop cannot ping the PC (10.0.0.201)
- PC cannot connect to FTP server on the laptop
- FTPSRV on the PC accepts TCP connections from the laptop, but no data flows (hangs after "Connected")

### Root Cause

The Xfinity router appears to be isolating devices — preventing direct communication between clients on the network. This is common with consumer routers as a security feature. The WiFi extender connects to the router wirelessly, and the PC is on the extender's wired port. The router treats them as separate clients and blocks traffic between them.

### Workaround: Direct Ethernet Connection

Connecting the PC directly to the laptop with an Ethernet cable (bypassing the router and extender entirely) works. The laptop has a USB Ethernet adapter (`enp0s13f0u1c2`) with auto-MDI/X, so a standard Ethernet cable works — no crossover cable needed.

Setup:
1. Connect Ethernet cable directly between PC and laptop
2. Assign a static IP on the laptop's Ethernet interface:
   ```
   sudo ip addr add 10.0.0.100/24 dev enp0s13f0u1c2
   ```
3. On the PC, DHCP won't work without a router, so the MTCP.CFG would need static IP settings
4. The mTCP FTP client successfully connected to a Python FTP server on the laptop:
   ```
   # Laptop:
   python3 -m pyftpdlib -w -p 2121

   # PC:
   FTP -port 2121 10.0.0.100
   ```

### Outstanding Issue

The preferred setup is to use the WiFi extender so the PC has internet access (for future use) and can also communicate with the laptop. This requires either:

1. Disabling client isolation on the Xfinity router (unable to find this setting in the Xfinity app)
2. Using a small Ethernet switch so both the PC and laptop are on the wired side of the extender
3. Continuing with the direct Ethernet connection as a workaround

---

**Next:** Transfer files off the IBM PC and investigate the Xfinity router isolation issue.
