/*
 * 3C5X9CFG.C - Lightweight 3C509B NIC Configuration Utility
 *
 * Copyright (c) 2026 Charlie Savage
 * BSD 2-Clause License (see 3c5x9cfg.asm for full text)
 *
 * NOTE: This is a C reference implementation that mirrors the
 * logic of 3c5x9cfg.asm. The actual program shipped to the IBM
 * PC is assembled from the .asm file using NASM. This C version
 * exists as readable documentation for anyone who finds 8086
 * assembly hard to follow. The two versions aim to implement the
 * same algorithm but may diverge in minor details.
 *
 * This file has NOT been compiled or tested. It targets OpenWatcom
 * for DOS (16-bit, 8086-compatible) but no DOS C compiler was
 * available during development. The assembly version is the
 * authoritative implementation.
 *
 * Build (hypothetical, untested):
 *   wcl -0 -ms -bt=dos -fe=3c5x9cfg.exe 3c5x9cfg.c
 *
 * Based on:
 *   - 3c5x9setup by Donald Becker (Linux configuration tool)
 *   - 3C509B-nestor packet driver by Gabor Gaal & Nestor
 *   - Linux 3c509 kernel driver
 *
 * Usage:
 *   3C5X9CFG                     Show current settings
 *   3C5X9CFG /IRQ:3              Set IRQ to 3
 *   3C5X9CFG /IO:300             Set I/O base to 300h
 *   3C5X9CFG /XCVR:TP            Set transceiver (TP, BNC, AUI)
 *   3C5X9CFG /P:300              Specify I/O base (skip autodetect)
 *   3C5X9CFG /?                  Show help
 *
 * Architecture:
 *   The 3C509B stores its configuration in a 16-word EEPROM.
 *   This program reads and writes those words to change settings.
 *
 *   Before the card is activated (e.g., fresh install), it is
 *   discovered via the "ID port" at 0x110. A 255-byte LFSR pattern
 *   wakes the card, after which EEPROM can be read bit-by-bit.
 *
 *   Once activated, the card responds at its configured I/O base.
 *   EEPROM access then goes through Window 0 registers:
 *     base+0x0A = command register
 *     base+0x0C = data register
 *
 *   EEPROM word layout (16-bit words):
 *     Word 0-2:  MAC address (3 words, big-endian byte pairs)
 *     Word 3:    Model ID and version
 *     Word 8:    Transceiver type (bits 15:14) + I/O base (bits 4:0)
 *     Word 9:    IRQ (bits 15:12) + resource config (bits 11:0)
 *     Word 13:   Driver tuning options
 *     Word 15:   Checksum (split fixed/variable XOR)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <conio.h>      /* OpenWatcom: inp(), outp(), inpw(), outpw() */

/* ================================================================
 * Constants
 * ================================================================ */

/* The ID port is used to discover unactivated 3C509B cards.
 * Default address is 0x110 (configurable 0x100-0x1E0). */
#define ID_PORT         0x110

/* EEPROM commands written to Window 0, offset 0x0A.
 * Each is OR'd with the target word index (0-15). */
#define EE_READ         0x80    /* Read: result at offset 0x0C */
#define EE_WRITE        0x40    /* Write: data must be at 0x0C first */
#define EE_ERASE        0xC0    /* Erase word (required before write) */
#define EE_EWENB        0x30    /* Enable erase/write (valid ~10ms) */
#define EE_BUSY         0x8000  /* Bit 15 of command reg = busy flag */

/* Commands written to the ID port before activation. */
#define ID_RESET        0xC0    /* Global reset: cards return to idle */
#define ID_SET_TAG      0xD0    /* Tag card: ignores future ID sequences */
#define ID_ACTIVATE     0xFF    /* Activate at EEPROM I/O base */

/* Window 0 register offsets from the card's I/O base.
 * The 3C509B has 8 register "windows" selected via the command reg.
 * Window 0 contains setup and EEPROM registers. */
#define W0_MFG_ID       0x00    /* Manufacturer ID (0x6D50 for 3Com) */
#define W0_EE_CMD       0x0A    /* EEPROM command register */
#define W0_EE_DATA      0x0C    /* EEPROM data register */
#define W0_CMD          0x0E    /* Command/Status (all windows) */

#define CMD_SELECT_WIN  0x0800  /* Select register window (OR with #) */

#define MFG_ID_3COM     0x6D50  /* Expected manufacturer ID */

/* EEPROM word indices. */
#define EE_NODE0        0       /* MAC address bytes 0-1 (big-endian) */
#define EE_NODE1        1       /* MAC address bytes 2-3 */
#define EE_NODE2        2       /* MAC address bytes 4-5 */
#define EE_MODEL_ID     3       /* Model (low byte) + version (bits 11:8) */
#define EE_IFXCVR_IO    8       /* Bits 15:14=xcvr, bits 4:0=I/O encoding */
#define EE_IRQ_LINE     9       /* Bits 15:12=IRQ, bits 11:0=resource cfg */
#define EE_DRIVER_TUNE  13      /* Driver tuning (duplex, link beat, etc.) */
#define EE_CHECKSUM     15      /* Checksum: high=fixed, low=variable */

/*
 * EEPROM word 8 (EE_IFXCVR_IO) bit layout:
 *   Bits 15-14: Transceiver type (00=TP, 01=AUI, 11=BNC)
 *   Bits  4-0:  I/O base encoding: base = (value << 4) + 0x200
 *
 * EEPROM word 9 (EE_IRQ_LINE) bit layout:
 *   Bits 15-12: IRQ number
 *   Bits 11-0:  Resource configuration (preserve when changing IRQ)
 */

/* Transceiver types stored in bits 15:14 of word 8.
 * TP  = twisted pair (RJ45) - the only option on the 3C509B-TPO.
 * AUI = thick Ethernet (15-pin D-sub with external transceiver).
 * BNC = thin coax (10base2). */
#define XCVR_TP         0
#define XCVR_AUI        1
#define XCVR_BNC        3

/* Valid IRQs for the 3C509B. Other values must be rejected. */
static const int valid_irqs[] = {3, 5, 7, 9, 10, 11, 12, 15};
#define NUM_VALID_IRQS  (sizeof(valid_irqs) / sizeof(valid_irqs[0]))


/* ================================================================
 * Delay functions
 *
 * On the ISA bus, each I/O port read takes ~1-2 microseconds.
 * Reading port 0x80 (POST diagnostic port) is safe and serves
 * as a portable delay mechanism on 8088-class hardware.
 * ================================================================ */

static void delay_us(unsigned int us)
{
    while (us--)
        inp(0x80);
}

static void delay_ms(unsigned int ms)
{
    while (ms--)
        delay_us(1000);
}


/* ================================================================
 * ID port functions
 *
 * The 3C509B uses an "ID port" mechanism for ISA card discovery.
 * Before the card is activated at its I/O base, you communicate
 * with it by writing a specific 255-byte LFSR pattern to port
 * 0x110. When the card's internal pattern generator matches, it
 * enters ID_CMD state and accepts commands.
 * ================================================================ */

/*
 * Send the 255-byte LFSR pattern to wake up unactivated cards.
 *
 * The pattern is generated by a Linear Feedback Shift Register
 * with polynomial 0xCF:
 *   1. Write 0x00 to reset the card's pattern generator.
 *   2. Start with value 0xFF.
 *   3. For 255 iterations:
 *      a. Write current value to ID port.
 *      b. If bit 7 set: shift left, XOR with 0xCF (feedback).
 *         Otherwise: just shift left.
 *
 * The card runs the same LFSR internally. When all 255 bytes
 * match, it transitions to ID_CMD state.
 */
static void send_id_pattern(void)
{
    unsigned char val;
    int i;

    outp(ID_PORT, 0x00);       /* Reset hardware pattern generator */

    val = 0xFF;
    for (i = 0; i < 255; i++) {
        outp(ID_PORT, val);
        if (val & 0x80)
            val = (unsigned char)((val << 1) ^ 0xCF);
        else
            val = (unsigned char)(val << 1);
    }
}

/*
 * Read one EEPROM word via the ID port (before activation).
 *
 * Sends a read command (EE_READ | index), waits for the EEPROM,
 * then clocks in 16 bits one at a time. Each read from the ID
 * port returns the next bit in bit 0, MSB first.
 *
 * Returns the 16-bit word value.
 */
static unsigned int id_read_eeprom(int index)
{
    unsigned int value = 0;
    int i;

    outp(ID_PORT, EE_READ | index);
    delay_ms(2);                /* Wait for EEPROM read to complete */

    for (i = 0; i < 16; i++)
        value = (value << 1) | (inp(ID_PORT) & 0x01);

    return value;
}


/* ================================================================
 * Register-based EEPROM functions
 *
 * After the card is activated, EEPROM access goes through
 * Window 0 registers at the card's I/O base address:
 *   base+0x0A = EEPROM command register (write commands here)
 *   base+0x0C = EEPROM data register (read/write data here)
 *
 * Bit 15 of the command register is the busy flag. Poll it
 * before issuing commands and before reading results.
 * ================================================================ */

/*
 * Read one EEPROM word via Window 0 registers.
 *
 * Returns the word value, or 0xFFFF on timeout.
 *
 * LIMITATION: 0xFFFF is used as an in-band sentinel, so a
 * legitimate 0xFFFF EEPROM value would be misreported as a
 * timeout. In practice, no standard 3C509B EEPROM word holds
 * 0xFFFF. The assembly version avoids this by using the carry
 * flag to signal errors out-of-band.
 */
static unsigned int reg_read_eeprom(unsigned int iobase, int index)
{
    int timer;

    /* Wait for EEPROM not busy */
    for (timer = 2000; inpw(iobase + W0_EE_CMD) & EE_BUSY; )
        if (--timer < 0)
            return 0xFFFF;      /* Timeout */

    /* Issue read command */
    outpw(iobase + W0_EE_CMD, EE_READ | index);
    delay_ms(2);                /* Wait for EEPROM read */

    /* Wait for completion */
    for (timer = 2000; inpw(iobase + W0_EE_CMD) & EE_BUSY; )
        if (--timer < 0)
            return 0xFFFF;

    /* Read result from data register */
    return inpw(iobase + W0_EE_DATA);
}

/*
 * Write one EEPROM word via Window 0 registers.
 * Based on write_eeprom() from 3c5x9setup by Donald Becker.
 *
 * The EEPROM requires a specific sequence:
 *   1. Wait for not busy
 *   2. Send EWENB (enable erase/write, valid ~10ms)
 *   3. Send ERASE | index (erase the target location)
 *   4. Wait for erase to complete
 *   5. Send EWENB again (enable expired after erase)
 *   6. Write data to the data register
 *   7. Send WRITE | index
 *   8. Wait for write to complete
 *
 * Returns 0 on success, -1 on timeout.
 */
static int reg_write_eeprom(unsigned int iobase, int index, unsigned int value)
{
    int timer;

    /* Step 1: Wait for not busy */
    for (timer = 2000; inpw(iobase + W0_EE_CMD) & EE_BUSY; )
        if (--timer < 0) return -1;

    /* Step 2: Enable erase/write */
    outpw(iobase + W0_EE_CMD, EE_EWENB);
    delay_us(100);

    /* Step 3: Erase the target location (required before write) */
    outpw(iobase + W0_EE_CMD, EE_ERASE | index);
    delay_us(100);

    /* Step 4: Wait for erase to complete */
    for (timer = 16000; inpw(iobase + W0_EE_CMD) & EE_BUSY; )
        if (--timer < 0) return -1;

    /* Step 5: Re-enable writes (EWENB expired after erase) */
    outpw(iobase + W0_EE_CMD, EE_EWENB);
    delay_us(100);

    /* Step 6: Write data to data register */
    outpw(iobase + W0_EE_DATA, value);

    /* Step 7: Issue write command */
    outpw(iobase + W0_EE_CMD, EE_WRITE | index);

    /* Step 8: Wait for write to complete */
    for (timer = 16000; inpw(iobase + W0_EE_CMD) & EE_BUSY; )
        if (--timer < 0) return -1;

    return 0;
}


/* ================================================================
 * EEPROM checksum
 *
 * The 3C509B EEPROM checksum (word 15) is split into two
 * independent parts so the card can verify factory-set data
 * and user-configurable settings separately:
 *
 *   "Fixed" words: 0-7, 10-12, 14 (MAC address, model, etc.)
 *   "Variable" words: 8, 9, 13 (I/O, IRQ, driver tuning)
 *
 * Each set is XOR'd together, then combined:
 *   High byte = fixed_hi XOR fixed_lo
 *   Low byte  = var_lo XOR var_hi
 * ================================================================ */

static unsigned int calc_checksum(unsigned int *ee)
{
    unsigned int fixed_cksum = 0, var_cksum = 0;
    int i;

    for (i = 0; i <= 14; i++) {
        if (i == EE_IFXCVR_IO || i == EE_IRQ_LINE || i == EE_DRIVER_TUNE)
            var_cksum ^= ee[i];
        else
            fixed_cksum ^= ee[i];
    }

    return ((fixed_cksum ^ (fixed_cksum << 8)) & 0xFF00) |
           ((var_cksum ^ (var_cksum >> 8)) & 0x00FF);
}


/* ================================================================
 * Display and decode helpers
 * ================================================================ */

/* Decode I/O base from word 8 bits 4:0.
 * Encoding: base = (value << 4) + 0x200.
 * Example: value 0x10 -> (0x10 << 4) + 0x200 = 0x300. */
static unsigned int decode_iobase(unsigned int word8)
{
    return ((word8 & 0x1F) << 4) + 0x200;
}

/* Decode IRQ from word 9 bits 15:12. */
static unsigned int decode_irq(unsigned int word9)
{
    return (word9 >> 12) & 0x0F;
}

/* Decode transceiver type from word 8 bits 15:14. */
static unsigned int decode_xcvr(unsigned int word8)
{
    return (word8 >> 14) & 0x03;
}

/* Map transceiver type code to human-readable name.
 * TP  = Twisted Pair (RJ45), the only option on 3C509B-TPO.
 * AUI = Attachment Unit Interface (thick Ethernet, 15-pin D-sub).
 * BNC = 10base2 thin coax with bayonet connector. */
static const char *xcvr_name(unsigned int xcvr)
{
    switch (xcvr) {
        case XCVR_TP:  return "TP (10baseT)";
        case XCVR_AUI: return "AUI";
        case 2:        return "undefined";
        case XCVR_BNC: return "BNC (10base2)";
    }
    return "unknown";
}

/* Check if an IRQ value is in the valid set for the 3C509B. */
static int is_valid_irq(int irq)
{
    int i;
    for (i = 0; i < NUM_VALID_IRQS; i++)
        if (valid_irqs[i] == irq)
            return 1;
    return 0;
}

/* Display the current card settings from the EEPROM buffer.
 * MAC bytes are stored big-endian in each word (high byte first). */
static void show_config(unsigned int *ee)
{
    unsigned int cksum;

    printf("  MAC:          %02X:%02X:%02X:%02X:%02X:%02X\n",
           (ee[EE_NODE0] >> 8) & 0xFF, ee[EE_NODE0] & 0xFF,
           (ee[EE_NODE1] >> 8) & 0xFF, ee[EE_NODE1] & 0xFF,
           (ee[EE_NODE2] >> 8) & 0xFF, ee[EE_NODE2] & 0xFF);
    printf("  I/O Base:     %03Xh\n", decode_iobase(ee[EE_IFXCVR_IO]));
    printf("  IRQ:          %d\n", decode_irq(ee[EE_IRQ_LINE]));
    printf("  Transceiver:  %s\n", xcvr_name(decode_xcvr(ee[EE_IFXCVR_IO])));
    printf("  Model:        3C%02X%X (ver %X)\n",
           ee[EE_MODEL_ID] & 0xFF,
           ee[EE_MODEL_ID] >> 12,
           (ee[EE_MODEL_ID] >> 8) & 0x0F);

    cksum = calc_checksum(ee);
    if (cksum == ee[EE_CHECKSUM])
        printf("  Checksum:     %04X (OK)\n", ee[EE_CHECKSUM]);
    else
        printf("  Checksum:     %04X (ERROR, expected %04X)\n",
               ee[EE_CHECKSUM], cksum);
}

static void show_usage(void)
{
    printf("3C5X9CFG - 3C509B NIC Configuration Utility\n\n");
    printf("Usage: 3C5X9CFG [/P:base] [/IRQ:n] [/IO:nnn] [/XCVR:type]\n\n");
    printf("  /P:base      I/O base in hex (skip autodetect)\n");
    printf("  /IRQ:n       Set IRQ (3,5,7,9,10,11,12,15)\n");
    printf("  /IO:nnn      Set I/O base in hex (200-3E0)\n");
    printf("  /XCVR:type   Set transceiver (TP, BNC, AUI)\n");
    printf("  /?           Show this help\n\n");
    printf("Examples:\n");
    printf("  3C5X9CFG                  Show current settings\n");
    printf("  3C5X9CFG /IRQ:3 /XCVR:TP Set IRQ 3, twisted pair\n");
}


/* ================================================================
 * Main
 *
 * Flow:
 *   1. Parse and validate command-line flags
 *   2. Find the card (ID port autodetect or /P: override)
 *   3. Read all 16 EEPROM words
 *   4. Display current settings
 *   5. If changes requested: modify words, write EEPROM, update
 *      checksum, display new settings
 * ================================================================ */

int main(int argc, char *argv[])
{
    unsigned int ee[16];        /* All 16 EEPROM words */
    unsigned int iobase;        /* Card's active I/O base */
    long new_irq = 0;          /* Requested IRQ */
    long new_iobase = 0;       /* Requested I/O base */
    int new_xcvr = 0;          /* Requested transceiver */
    long user_iobase = 0;      /* /P: override */
    int set_irq = 0;           /* Nonzero if /IRQ: was specified */
    int set_iobase = 0;        /* Nonzero if /IO: was specified */
    int set_xcvr = 0;          /* Nonzero if /XCVR: was specified */
    int set_user_iobase = 0;   /* Nonzero if /P: was specified */
    int do_write = 0;          /* Nonzero if any EEPROM writes needed */
    int i;

    /* ---- Parse command line ---- */
    for (i = 1; i < argc; i++) {
        if (stricmp(argv[i], "/?") == 0 || stricmp(argv[i], "/HELP") == 0) {
            show_usage();
            return 0;
        }
        else if (strnicmp(argv[i], "/P:", 3) == 0) {
            char *end;
            user_iobase = strtol(argv[i] + 3, &end, 16);
            if (*end != '\0' || end == argv[i] + 3 || user_iobase < 0) {
                printf("ERROR: Invalid /P: value\n");
                return 1;
            }
            set_user_iobase = 1;
        }
        else if (strnicmp(argv[i], "/IRQ:", 5) == 0) {
            char *end;
            new_irq = strtol(argv[i] + 5, &end, 10);
            if (*end != '\0' || end == argv[i] + 5 || new_irq < 0) {
                printf("ERROR: Invalid /IRQ: value\n");
                return 1;
            }
            set_irq = 1;
            do_write = 1;
        }
        else if (strnicmp(argv[i], "/IO:", 4) == 0) {
            char *end;
            new_iobase = strtol(argv[i] + 4, &end, 16);
            if (*end != '\0' || end == argv[i] + 4 || new_iobase < 0) {
                printf("ERROR: Invalid /IO: value\n");
                return 1;
            }
            set_iobase = 1;
            do_write = 1;
        }
        else if (strnicmp(argv[i], "/XCVR:", 6) == 0) {
            /* Exact match only: TP, BNC, or AUI */
            if (stricmp(argv[i] + 6, "TP") == 0)
                new_xcvr = XCVR_TP;
            else if (stricmp(argv[i] + 6, "BNC") == 0)
                new_xcvr = XCVR_BNC;
            else if (stricmp(argv[i] + 6, "AUI") == 0)
                new_xcvr = XCVR_AUI;
            else {
                printf("ERROR: Invalid xcvr. Valid: TP, BNC, AUI\n");
                return 1;
            }
            set_xcvr = 1;
            do_write = 1;
        }
        else {
            printf("Unknown option: %s\n", argv[i]);
            show_usage();
            return 1;
        }
    }

    /* ---- Validate /P: (I/O base range and alignment) ---- */
    if (set_user_iobase) {
        if (user_iobase < 0x200 || user_iobase > 0x3F0 ||
            (user_iobase & 0x0F) != 0) {
            printf("ERROR: Invalid /P: address. Valid: 200-3F0, 16-byte aligned\n");
            return 1;
        }
    }

    /* ---- Validate /IRQ: (whitelist check) ---- */
    if (set_irq && !is_valid_irq((int)new_irq)) {
        printf("ERROR: Invalid IRQ %d. Valid: 3,5,7,9,10,11,12,15\n", new_irq);
        return 1;
    }

    /* ---- Validate /IO: (range and alignment) ---- */
    if (set_iobase) {
        if (new_iobase < 0x200 || new_iobase > 0x3E0 ||
            (new_iobase & 0x0F) != 0) {
            printf("ERROR: Invalid I/O %03Xh. Valid: 200-3E0, 16-byte aligned\n",
                   new_iobase);
            return 1;
        }
    }

    /* ---- Find the card ---- */
    printf("3C5X9CFG - 3C509B Configuration Utility\n\n");

    if (set_user_iobase) {
        /* User specified /P: — card is already active at this address. */
        iobase = (unsigned int)user_iobase;
    } else {
        /*
         * Auto-detect via ID port:
         *   1. Send LFSR pattern + global reset (clean slate)
         *   2. Re-send pattern (card enters ID_CMD state)
         *   3. Read I/O base from EEPROM word 8
         *   4. Tag and activate the card
         */
        printf("Searching via ID port...\n");

        send_id_pattern();
        outp(ID_PORT, ID_RESET);
        delay_ms(5);

        send_id_pattern();

        ee[EE_IFXCVR_IO] = id_read_eeprom(EE_IFXCVR_IO);
        iobase = decode_iobase(ee[EE_IFXCVR_IO]);

        outp(ID_PORT, ID_SET_TAG);
        outp(ID_PORT, ID_ACTIVATE);
        delay_ms(5);
    }

    /* ---- Select Window 0 and verify card is present ---- */
    outpw(iobase + W0_CMD, CMD_SELECT_WIN);
    delay_ms(1);

    if (inpw(iobase + W0_MFG_ID) != MFG_ID_3COM) {
        printf("ERROR: 3C509B not found at %03Xh (read %04Xh)\n",
               iobase, inpw(iobase + W0_MFG_ID));
        return 1;
    }
    printf("Found 3C509B at %03Xh\n\n", iobase);

    /* ---- Read all 16 EEPROM words ---- */
    for (i = 0; i < 16; i++) {
        ee[i] = reg_read_eeprom(iobase, i);
        if (ee[i] == 0xFFFF) {
            printf("ERROR: EEPROM read failed (timeout) at word %d\n", i);
            return 1;
        }
    }

    printf("Current settings:\n");
    show_config(ee);

    if (!do_write)
        return 0;

    /* ---- Apply changes to EEPROM ---- */
    printf("\nWriting EEPROM:\n");

    /* Modify word 8 if transceiver or I/O base changed.
     * Word 8 bits 15:14 = transceiver, bits 4:0 = I/O encoding.
     * Only the changed bits are modified; the rest are preserved. */
    if (set_xcvr || set_iobase) {
        unsigned int word8 = ee[EE_IFXCVR_IO];

        if (set_xcvr)
            word8 = (word8 & 0x3FFF) | ((unsigned int)new_xcvr << 14);
        if (set_iobase)
            word8 = (word8 & 0xFFE0) |
                    (((unsigned int)(new_iobase - 0x200) >> 4) & 0x1F);

        printf("  I/O config...");
        if (reg_write_eeprom(iobase, EE_IFXCVR_IO, word8) < 0) {
            printf(" FAILED\n");
            return 1;
        }
        ee[EE_IFXCVR_IO] = word8;
        printf(" OK\n");
    }

    /* Modify word 9 if IRQ changed.
     * Bits 15:12 = IRQ number. Bits 11:0 preserved. */
    if (set_irq) {
        unsigned int word9 = (ee[EE_IRQ_LINE] & 0x0FFF) |
                             ((unsigned int)new_irq << 12);

        printf("  IRQ config...");
        if (reg_write_eeprom(iobase, EE_IRQ_LINE, word9) < 0) {
            printf(" FAILED\n");
            return 1;
        }
        ee[EE_IRQ_LINE] = word9;
        printf(" OK\n");
    }

    /* Always recalculate and write the checksum after changes. */
    {
        unsigned int cksum = calc_checksum(ee);
        printf("  Checksum...");
        if (reg_write_eeprom(iobase, EE_CHECKSUM, cksum) < 0) {
            printf(" FAILED\n");
            return 1;
        }
        ee[EE_CHECKSUM] = cksum;
        printf(" OK\n");
    }

    /* ---- Confirm new settings ---- */
    /* Re-read from EEPROM to verify the writes took effect. */
    for (i = 0; i < 16; i++) {
        ee[i] = reg_read_eeprom(iobase, i);
        if (ee[i] == 0xFFFF) {
            printf("ERROR: EEPROM re-read failed (timeout) at word %d\n", i);
            return 1;
        }
    }

    printf("\nNew settings:\n");
    show_config(ee);
    printf("\nReboot for changes to take effect.\n");

    return 0;
}
