# IBM PC File Recovery Project

## Overview

Back in 1981 my parents bought an [IBM PC 5150](https://en.wikipedia.org/wiki/IBM_Personal_Computer). The specs of the machine:

| Component | Specification                                        |
|-----------|------------------------------------------------------|
| CPU | Intel 8088 (16-bit internal, 8-bit external bus)     |
| RAM | 512 KB (has a 256 expansion card)                    |
| Storage | 5.25" floppy drives, later a 10MB hard drive was added |
| Bus | ISA (Industry Standard Architecture)                 |
| Ports | Parallel (Centronics), Keyboard                      |
| Video | IBM Monochrome Display and Printer Adapter (MDA) |
| OS | MS-DOS 3.3                                           |
 
I started programming on this machine, writing a horse handicapping program using [dBase](https://en.wikipedia.org/wiki/DBase). That didn't go anyplace, but it did lead to my eventual career in the software industry.

It was also my mom's working computer through the 1980's. She was a journalist and used it to write a number of articles. In addition, she used it to write several unpublished books including *Black Pearl*, *The Bear* and a three part book entitled *Flight of the Cranes.* I have partial print outs of some of them, but not the original digital files.

After all these years, she still had the machine - boxed away in the garage. So I recently pulled it out, set it up, and amazingly it booted right up. I forgot how noisy it was! And so primitive - no command history, no command completion, no copy/paste, etc. But at least it had a 10MB hard drive - added a few years later - which makes it a lot easier to use that with a single 5.25 inch floppy drive.

It took me a few minutes to remember how to navigate the machine and refamiliarize myself with the programs of the time (Norton Commander, Fastwire II, etc). After a bit of poking around I found one of the books on the hard drive and a couple more on 5 1/4 floppy drives. The books were written using a word processor called [Leading Edge](https://en.wikipedia.org/wiki/Leading_Edge_Products), which was pretty great for the time but eventually got annihilated by [WordStar](https://en.wikipedia.org/wiki/WordStar) and then [WordPerfect](https://en.wikipedia.org/wiki/WordPerfect).

Now that I found what I was looking for, how should I copy the files from the IBM PC to my laptop.  My laptop is a Thinkpad that dual boots Windows 11 and Fedora 43. Either operating system will work.

## Data Transfer Options
Modern computers have almost no overlap with the 1981 IBM PC. The PC predates:

- 3.5" floppy drives (1982 for the format, mid-1980s for PC adoption)
- CD-ROM drives (late 1980s)
- Ethernet on consumer PCs (mid-1980s for cards, late 1990s for onboard)
- USB (1996)

### Option 1: Floppy Disk Sneakernet

One obvious solution is to copy the files to 5.25 floppy drives and then buy a USB 5.25 inch drive. The problem is USB 5.25 floppy drives don't actually exist. However, you can buy a USB 3.5 inch drive.

Thus you can buy a 386 or 486 era machine that has both a 5.25 and 3.5 drive. You can then copy the files from a 5.25 floppy drive to a 3.5 floppy drive and then to the laptop. This solution of course requires acquiring another old machine - which I wasn't very enthusiastic about.

### Option 2: Parallel Port Transfer

Use the parallel port on the IBM PC to transfer data to my laptop. However, laptops and desktops stopped including the parallel port around 2005. You can buy USB-to-parallel cables, but they are designed for printers and do not support bidirectional file transfer.

To remedy this, Petr Stehlík has an amazing project, [PARCP-USB](https://joy.sophics.cz/parcp/parcp-usb.html). He builds a special adapter that enables bidirectional data transfer using the parallel port using an open source program called [PARCP](https://github.com/joysfera/parcp). 

I reached out to him and he was very helpful. He let me know the hardware is compatible with the IBM PC. However, PARCP is not because it is compiled for DOS with [DJGPP](https://www.delorie.com/djgpp/) which requires a 32-bit CPU (so [386](https://en.wikipedia.org/wiki/I386) or higher). Petr mentioned it would be possible to port it to 8086 DOS with some effort.

### Option 3: Serial Port Transfer (works)

The IBM supports an RS-232 serial port - a standard that is still with us today! This approach has many advantages, including:

- RS-232 is electrically simple and well-documented
- No CPU requirements  -  works on any PC with a serial port
- Lots of software options, including terminal programs, Kermit, XMODEM, or raw BASIC
- USB-to-serial adapters are cheap and common

One downside is serial communications are slow. On old hardware it runs at 1200-9600 baud. At 4800 baud, a 185 KB file would take a bit over 5 minutes to transfer. But for copying old documents that is fast enough.

To get this working requires:

- Installing an 8-bit ISA COM card in the IBM PC
- A null modem cable (TX/RX crossed)
- A USB-to-serial adapter
- A bootstrap program to copy a file transfer program from my laptop to the PC

Petr also cautioned that I might run into issues with voltage levels. RS-232 uses +/-12 V for signals, while current USB to UART/serial converters often only use 5V/0V. Thus the IBM PC might not work with the low voltage levels. 

However, this is the path I chose.

## The Plan

So my plan was:

1. Install a serial card in the IBM PC
2. Connect the IBM PC to my laptop via a null modem cable and a USB-serial adapter
3. Bootstrap a file receiver using GW-BASIC
4. Transfer a proper file transfer program (MS-Kermit)
5. Use Kermit to copy all files from the PC

| Part | Title | Summary |
|------|-------|---------|
| 1 | [Install Serial Card](part1-install-serial-card.md) | Installing an ISA serial card |
| 2 | [Serial Connection](part2-serial-connection.md) | Connecting the IBM PC to a modern laptop |
| 3 | [Bootstrap Text Receiver](part3-text-receiver.md) | Writing a minimal GW-BASIC program to receive text files |
| 4 | [Kermit](part4-kermit.md) | Trying to use KERMIT.BAS for file transfer protocol |
| 5 | [Bootstrap Binary Receiver](part5-binary-receiver.md) | Creating a custom binary transfer system |
| 6 | [Can't Send Files!](part6-mskermit.md) | Discovering the one-way communication issue |
| 7 | [Debugging](part7-debugging.md) | Diagnosing the line driver failure with loopback tests |
| 8 | [Next Steps](part8-next-steps.md) | Checking the -12V rail and fixing the PSU |

## Current Status

**Working:** Laptop -> PC file transfer at 4800 baud (185 KB in ~7 minutes)

**Blocked:** PC -> laptop transfer fails due to line driver or PSU issue

**Next Steps:** Check the -12V rail and replace serial card or PSU if needed


