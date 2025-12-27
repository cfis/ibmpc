# Part 1: Install Serial Card

The IBM PC 5150 didn't come with a serial port - it was an optional add-on. To transfer files to a modern computer, I first needed to install an ISA serial card that implements the RS-232 interface. This provides a common communication protocol that USB-to-serial adapters can speak, bridging the 40+ year gap between the IBM PC and my laptop.

## IBM 1501485-XM

I first tried an IBM 1501485-XM, which I purchased from [eBay](https://www.ebay.com/itm/157150188353).

## BIOS COM Port Check (DEBUG)

After installing the card, I used the DEBUG program to verify that BIOS was correctly recognizing it. From the DOS prompt:

```
DEBUG
d 40:0
```

Output:

```
0040:0000  F8 03 00 00 00 00 00 00
```

Interpretation (little-endian words):

- Bytes 0-1 = COM1 base address (03F8 if present)
- Bytes 2-3 = COM2 base address (02F8 if present)

So:

- `F8 03` = COM1 at 0x03F8
- `00 00` = no COM2

This was correct. However, additional checks did not work. 

At the command prompt I tried:

```dosint
MODE COM1
```

This returned *Invalid parameter*. Then in GW-BASIC, I tried:

```basic
OPEN "COM1:"
OPEN "COM1:9600,N,8,1"
```

Unfortunately, the command repeatedly failed with the error message `Device Unavailable` / `Error 24` which is a device timeout. It seemed that the call to the UART timed out even though the BDA reported COM1.

I'm not sure if this was the wrong type of board or if this was just a bad board. Either way it didn't work.

## IBM 1503236-XM

I then bought a second card, this time an IBM 1503236-XM, once again using [eBay](https://www.ebay.com/itm/306639359181).

The card also passed the BIOS check, which reported COM1 at 0x03F8.

Even better, this time GW-BASIC could open `COM1:9600,N,8,1` without device errors.

With a working serial card installed, the next step was connecting the IBM PC to a laptop.

---

**Next:** [Part 2: Serial Connection](part2-serial-connection.md)
