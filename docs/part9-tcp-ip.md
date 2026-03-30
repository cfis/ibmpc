# Part 9: Switching to TCP/IP

Rather than continue debugging the serial card's transmit failure (see [Part 8](part8-next-steps.md)), I decided to try a completely different approach: TCP/IP networking using an ISA network card.

This approach is based on [voidstar's guide to setting up a NIC and mTCP on a 5150](https://voidstar.blog/5150-setting-up-nic-network-interface-card-and-mtcp/).

## The Plan

1. Transfer all required NIC and mTCP files to the IBM PC via serial (while the serial card is still installed)
2. Remove the serial card (the only available ISA slot)
3. Install a 3COM Etherlink III 3C509B-TPO NIC
4. Configure the NIC and mTCP
5. Run an FTP server on the IBM PC
6. Connect from the laptop and copy all the files

## Hardware

| Component | Description |
|-----------|-------------|
| NIC | [3COM Etherlink III 3C509B-TPO](https://www.ebay.com/itm/205385887590) (16-bit ISA, works in 8-bit slots) |
| Connector | RJ45 (twisted pair) |

## Software

The NIC requires a packet driver and configuration utility. These are 8088-compatible versions from the NESTOR project:

| Software | Size | Purpose | Source |
|----------|------|---------|--------|
| 3ccfg.exe | 234 KB | NIC configuration utility (GUI) | [3C509B-nestor](https://github.com/hackerb9/3C509B-nestor) |
| 3c509.com | 8 KB | Packet driver (8088-compatible) | [3C509B-nestor](https://github.com/hackerb9/3C509B-nestor) |

Initially, `3ccfg.exe` appeared to fail with "Program too big to fit in memory." This was actually caused by the [CR/LF bug](#bug-record-count-protocol-corruption) corrupting the transferred file. After fixing the sender, `3ccfg.exe` worked fine. A lightweight replacement (`3c5x9cfg.com`, 3KB) was also written in 8086 assembly as a backup — see [Part 10](part10-3com-nic.md).

For TCP/IP, [mTCP](http://www.brutman.com/mTCP/) by Michael Brutman provides command-line networking tools for DOS. mTCP officially supports 8088 processors. The IBM PC also has `PKUNZIP.EXE` installed, so the entire mTCP zip can be transferred and extracted on the PC rather than sending individual files.

| Software | Size | Purpose |
|----------|------|---------|
| mTCP_2025-01-10.zip | ~400 KB | Full mTCP package |
| 3c509.com | 8 KB | Packet driver |
| 3c5x9cfg.com | 2 KB | NIC configuration utility (custom) |

## Bootstrap Problem

There is a catch-22: the serial card must be removed to make room for the NIC, but the serial card is the only way to transfer files to the PC. So everything needed for networking must be transferred via serial *before* swapping cards.

The transfer uses the same binary bootstrap system from [Part 5](part5-binary-receiver.md): `receive.bas` on the IBM PC and `send.rb` on the laptop.

## Transferring the Files

The receiver was updated to prompt for the filename (instead of hardcoding it) and to exit cleanly after the transfer completes. The sender transmits the record count first, so the receiver knows when to stop.

On the IBM PC, the updated `receive.bas`:

```basic
10 ON ERROR GOTO 900
20 OPEN "COM1:4800,N,8,1,RS,CS0,DS0,CD0" AS #1
25 INPUT "File";N$
30 OPEN N$ FOR RANDOM AS #2 LEN=128
40 FIELD #2, 128 AS F$
45 LINE INPUT #1, T$: TOTAL = VAL(T$)
50 RECORD = 1: B$ = "": NEED = 128
60 B$ = B$ + INPUT$(NEED, #1)
70 IF LEN(B$) < 128 THEN 60
80 LSET F$ = LEFT$(B$,128)
90 PUT #2, RECORD
100 B$ = MID$(B$,129)
105 IF RECORD >= TOTAL THEN 910
110 RECORD = RECORD + 1
120 GOTO 60
900 PRINT "ERR=";ERR;" ERL=";ERL
910 CLOSE
920 PRINT "Received";RECORD-1;"records"
930 END
```

On the laptop, each file is sent with:

```bash
ruby src/send.rb /dev/ttyUSB0 <filename> 4800
```

### Bug: Record Count Protocol Corruption

!!! warning "CR/LF Bug"
    The original sender transmitted the record count with `\r\n` (CR+LF). GW-BASIC's `LINE INPUT` reads until CR but leaves the LF (`0x0A`) in the serial buffer. This LF becomes the first byte of the binary data, shifting the entire file by one byte.

    The result: corrupted EXE headers. DOS fails to recognize the MZ signature and either reports "Program too big to fit in memory" (trying to load as .COM) or crashes with a divide-by-zero error (executing garbage code).

    The fix: send only `\r` (no `\n`) after the record count:
    ```ruby
    sp.write("#{record_count}\r")
    ```

### Bug: Off-by-One in Exit Condition

The original exit check was `IF RECORD > TOTAL`, but `RECORD` hasn't been incremented yet at line 105. After writing the last record, `RECORD` equals `TOTAL`, and `TOTAL > TOTAL` is false — so the receiver loops back and blocks forever waiting for data.

The fix: `IF RECORD >= TOTAL THEN 910`.

## Hard Drive Boot Failure

During file transfers, the hard drive's boot sector was somehow damaged. The PC reported "Disk boot failure" on startup.

### Recovery

1. Booted from a 5.25" DOS floppy disk
2. Verified the hard drive was still accessible: `DIR C:\` showed all files intact
3. Attempted `SYS C:` but `SYS.COM` was not on the floppy (only files A-M were present)
4. Since C: was accessible, ran `SYS.COM` from the hard drive itself:
   ```
   A:
   C:\DOS\SYS C:
   ```
   This works because `SYS` copies system files from the **default drive** (A:, the bootable floppy) to the target drive (C:). The key insight: `SYS.COM` can be run from any location, but the hidden system files (`IBMBIO.COM`, `IBMDOS.COM`) are copied from whichever drive is the current default.
5. Removed the floppy and rebooted — hard drive booted successfully.

!!! tip "Always Have a Boot Floppy"
    Working with 40-year-old hardware means things can fail at any time. Keep a DOS boot floppy handy. Even if it doesn't have every utility, as long as it boots and you can access C:, you can recover using tools on the hard drive.

---

**Next:** [Part 10: Configuring the 3COM NIC](part10-3com-nic.md)
