;
; 3C5X9CFG.COM - Lightweight 3C509B NIC Configuration Utility
;
; Copyright (c) 2026 Charlie Savage
; BSD 2-Clause License (see below)
;
; A replacement for 3ccfg.exe that doesn't need the MEWEL GUI
; library (250-300KB overhead). Runs on 8088 with minimal memory.
;
; Based on:
;   - 3c5x9setup by Donald Becker (Linux configuration tool)
;   - 3C509B-nestor packet driver
;   - Linux 3c509 kernel driver
;
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions
; are met:
;
; 1. Redistributions of source code must retain the above copyright
;    notice, this list of conditions and the following disclaimer.
; 2. Redistributions in binary form must reproduce the above copyright
;    notice, this list of conditions and the following disclaimer in
;    the documentation and/or other materials provided with the
;    distribution.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
; FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
; COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
; BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
; ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
; POSSIBILITY OF SUCH DAMAGE.
;
; Assemble:
;   nasm -f bin -o 3c5x9cfg.com 3c5x9cfg.asm
;
; Usage:
;   3C5X9CFG                  Show current settings
;   3C5X9CFG /IRQ:3           Set IRQ to 3
;   3C5X9CFG /IO:300          Set I/O base to 300h
;   3C5X9CFG /XCVR:TP         Set transceiver (TP, BNC, AUI)
;   3C5X9CFG /P:300           Specify I/O base (skip autodetect)
;   3C5X9CFG /?               Show help
;
; Architecture:
;   The 3C509B stores its configuration in a 16-word EEPROM.
;   This program reads and writes those words to change settings.
;
;   Before the card is activated (e.g., fresh install), it is
;   discovered via the "ID port" at 0x110. A 255-byte LFSR pattern
;   wakes the card, after which EEPROM can be read bit-by-bit.
;
;   Once activated, the card responds at its configured I/O base.
;   EEPROM access then goes through Window 0 registers:
;     base+0x0A = command register
;     base+0x0C = data register
;
;   EEPROM word layout (16-bit words):
;     Word 0-2:  MAC address (3 words, big-endian byte pairs)
;     Word 3:    Model ID and version
;     Word 8:    Transceiver type (bits 15:14) + I/O base (bits 4:0)
;     Word 9:    IRQ (bits 15:12) + resource config (bits 11:0)
;     Word 13:   Driver tuning options
;     Word 15:   Checksum (split fixed/variable XOR)
;
;   The checksum has two independent parts so changing user settings
;   (words 8, 9, 13) doesn't require knowing the fixed data, and
;   vice versa.
;

; ---- Target: 8086 real mode, DOS .COM flat binary ----
[BITS 16]
[CPU 8086]
org 0x100                       ; .COM files load at offset 0x100

; ============================================================
; Constants
; ============================================================

; The ID port is used to discover unactivated 3C509B cards.
; The default address is 0x110 (configurable 0x100-0x1E0).
ID_PORT     equ 0x110

; EEPROM commands written to Window 0, offset 0x0A.
; Each command is OR'd with the word index (0-15).
EE_READ     equ 0x80            ; Read word: result appears at offset 0x0C
EE_WRITE    equ 0x40            ; Write word: data must be at offset 0x0C first
EE_ERASE    equ 0xC0            ; Erase word (required before write)
EE_EWENB    equ 0x30            ; Enable erase/write (expires after ~10ms)

; Commands written to the ID port (0x110) before card activation.
ID_RESET    equ 0xC0            ; Global reset: all untagged cards return to idle
ID_TAG      equ 0xD0            ; Tag card so it ignores future ID sequences
ID_ACTIVATE equ 0xFF            ; Activate card at its EEPROM-configured I/O base

; Window 0 register offsets, relative to the card's I/O base address.
; The 3C509B has 8 register "windows" selected via the command register.
; Window 0 contains setup/EEPROM registers.
W0_MFG      equ 0x00            ; Manufacturer ID: reads 0x6D50 for 3Com
W0_EECMD    equ 0x0A            ; EEPROM command register (write cmd here)
W0_EEDATA   equ 0x0C            ; EEPROM data register (read/write data here)
W0_CMD      equ 0x0E            ; Command/Status register (present in all windows)

CMD_SELWIN0 equ 0x0800          ; Command: select Window 0

MFG_3COM    equ 0x6D50          ; Expected manufacturer ID for 3Com cards

; EEPROM word indices (each word is 16 bits).
EE_NODE0    equ 0               ; MAC address bytes 0-1 (big-endian)
EE_NODE1    equ 1               ; MAC address bytes 2-3
EE_NODE2    equ 2               ; MAC address bytes 4-5
EE_MODEL    equ 3               ; Model number (low byte) + version (bits 11:8)
EE_IFXCVR   equ 8               ; Bits 15:14 = transceiver, bits 4:0 = I/O encoding
EE_IRQLINE  equ 9               ; Bits 15:12 = IRQ number, bits 11:0 = resource cfg
EE_TUNE     equ 13              ; Driver tuning (duplex, link beat, etc.)
EE_CKSUM    equ 15              ; Checksum: high byte = fixed, low byte = variable


; ============================================================
; Main program
;
; Flow:
;   1. Parse command line
;   2. Find card (ID port autodetect or user-specified /P:)
;   3. Read all 16 EEPROM words
;   4. Display current settings
;   5. If changes requested: write EEPROM, update checksum
;   6. Display new settings
; ============================================================

main:
    call prepare_cmdline        ; Uppercase + null-terminate command tail

    ; Check for /? help flag
    mov si, flag_help
    call find_flag
    jc .no_help                 ; CF=1 means not found
    jmp .show_help
.no_help:

    mov dx, msg_banner
    call print_str

    call parse_flags            ; Parse /P:, /IRQ:, /IO:, /XCVR:
    call check_unknown_flags    ; Reject unrecognized flags (e.g., /IRG:3)

    ; ---- Find the card ----
    ; If the user specified /P:xxx, use that I/O base directly.
    ; Otherwise, auto-detect via the ID port.
    cmp word [user_iobase], 0
    jne .user_specified

    mov dx, msg_searching
    call print_str
    call detect_card            ; Sets [iobase] from EEPROM word 8
    jmp .card_ready

.user_specified:
    mov ax, [user_iobase]
    mov [iobase], ax

.card_ready:
    ; Select Window 0 so we can access EEPROM registers.
    ; Write CMD_SELWIN0 (0x0800) to the command register at base+0x0E.
    mov dx, [iobase]
    add dx, W0_CMD
    mov ax, CMD_SELWIN0
    out dx, ax
    call delay_1ms

    ; Verify the card is present by reading the manufacturer ID
    ; from Window 0, offset 0x00. Should be 0x6D50 for 3Com.
    mov dx, [iobase]
    in ax, dx
    cmp ax, MFG_3COM
    jne .not_found

    mov dx, msg_found
    call print_str
    mov ax, [iobase]
    call print_hex4
    mov dx, msg_h_nl
    call print_str

    ; Read all 16 EEPROM words into the ee_words[] buffer.
    call read_all_eeprom
    jc .read_failed             ; Abort if any read timed out

    mov dx, msg_current
    call print_str
    call show_config            ; Display MAC, I/O, IRQ, xcvr, checksum

    ; If no /IRQ:, /IO:, or /XCVR: flags were given, we're done.
    cmp byte [do_write], 0
    je .done

    ; Apply the requested changes to EEPROM.
    mov dx, msg_writing
    call print_str
    call write_settings
    test al, al                 ; AL=0 success, AL=1 failure
    jnz .write_failed

    ; Re-read EEPROM and display the new settings to confirm.
    call read_all_eeprom
    jc .read_failed
    mov dx, msg_newcfg
    call print_str
    call show_config
    mov dx, msg_reboot
    call print_str

.done:
    mov ax, 0x4C00              ; DOS exit, return code 0
    int 0x21

.show_help:
    mov dx, msg_usage
    call print_str
    mov ax, 0x4C00
    int 0x21

.not_found:
    mov dx, msg_notfound
    call print_str
    mov ax, 0x4C01              ; DOS exit, return code 1
    int 0x21

.write_failed:
    mov dx, msg_wfail
    call print_str
    mov ax, 0x4C01
    int 0x21

.read_failed:
    mov dx, msg_rfail
    call print_str
    mov ax, 0x4C01
    int 0x21


; ============================================================
; prepare_cmdline
;
; DOS stores the command tail in the PSP (Program Segment Prefix):
;   [0x80] = byte: length of command tail
;   [0x81..] = the characters, terminated by CR (0x0D)
;
; This routine null-terminates the tail and converts it to
; uppercase so flag matching is case-insensitive.
; ============================================================

prepare_cmdline:
    mov si, 0x80
    xor ch, ch
    mov cl, [si]                ; CX = length of command tail
    inc si                      ; SI = 0x81 (start of tail)
    mov di, si
    add di, cx
    mov byte [di], 0            ; Replace CR with null terminator

    mov si, 0x81
.loop:
    mov al, [si]
    test al, al
    jz .done
    cmp al, 'a'
    jb .next
    cmp al, 'z'
    ja .next
    sub al, 0x20                ; Convert lowercase to uppercase
    mov [si], al
.next:
    inc si
    jmp .loop
.done:
    ret


; ============================================================
; parse_flags
;
; Scan the command line for recognized flags and store their
; values in global variables. Each flag is a substring like
; "/IRQ:" followed by a value. find_flag locates the substring
; and returns DI pointing to the value.
;
; Validation:
;   /P:    - hex, 200h-3F0h, 16-byte aligned
;   /IRQ:  - decimal, whitelist {3,5,7,9,10,11,12,15}
;   /IO:   - hex, 200h-3E0h, 16-byte aligned
;   /XCVR: - exact match: "TP", "BNC", or "AUI"
;
; All values must end at a delimiter (space, null, or /).
; On validation failure, prints an error and exits immediately.
; ============================================================

parse_flags:
    ; ---- /P:xxx - card's current I/O base (skip autodetect) ----
    mov si, flag_p
    call find_flag
    jc .no_p                    ; Not found, skip
    mov si, di                  ; SI = value string after "/P:"
    call parse_hex              ; AX = parsed hex value
    jc .bad_p                   ; Overflow (>4 hex digits)
    push ax
    mov al, [si]                ; Check character after the number
    call is_delim               ; Must be space, null, or /
    pop ax
    jne .bad_p                  ; Trailing junk
    cmp ax, 0x200               ; Minimum valid I/O base
    jb .bad_p
    cmp ax, 0x3F0               ; Maximum valid I/O base
    ja .bad_p
    test ax, 0x0F               ; Must be 16-byte aligned
    jnz .bad_p
    mov [user_iobase], ax
    jmp .no_p
.bad_p:
    mov dx, msg_bad_p
    call print_str
    jmp .parse_err
.no_p:

    ; ---- /IRQ:n - set IRQ number ----
    mov si, flag_irq
    call find_flag
    jc .no_irq
    mov si, di
    call parse_dec              ; AX = parsed decimal value
    jc .bad_irq                 ; Overflow
    push ax
    mov al, [si]
    call is_delim               ; Must end at delimiter
    pop ax
    jne .bad_irq
    ; Whitelist: only these IRQs are valid for the 3C509B
    cmp ax, 3
    je .irq_ok
    cmp ax, 5
    je .irq_ok
    cmp ax, 7
    je .irq_ok
    cmp ax, 9
    je .irq_ok
    cmp ax, 10
    je .irq_ok
    cmp ax, 11
    je .irq_ok
    cmp ax, 12
    je .irq_ok
    cmp ax, 15
    je .irq_ok
    jmp .bad_irq
.irq_ok:
    mov [new_irq], ax
    mov byte [do_write], 1      ; Mark that we need to write EEPROM
    jmp .no_irq
.bad_irq:
    mov dx, msg_bad_irq
    call print_str
    jmp .parse_err
.no_irq:

    ; ---- /IO:xxx - set I/O base address in EEPROM ----
    mov si, flag_io
    call find_flag
    jc .no_io
    mov si, di
    call parse_hex
    jc .bad_io
    push ax
    mov al, [si]
    call is_delim
    pop ax
    jne .bad_io
    cmp ax, 0x200
    jb .bad_io
    cmp ax, 0x3E0
    ja .bad_io
    test ax, 0x0F               ; Must be 16-byte aligned
    jnz .bad_io
    mov [new_iobase], ax
    mov byte [do_write], 1
    jmp .no_io
.bad_io:
    mov dx, msg_bad_io
    call print_str
    jmp .parse_err
.no_io:

    ; ---- /XCVR:xx - set transceiver type ----
    ; Must be an exact match for "TP", "BNC", or "AUI",
    ; followed by a delimiter. No prefix matching.
    mov si, flag_xcvr
    call find_flag
    jc .no_xcvr
    ; Check for "TP" + delimiter
    cmp byte [di], 'T'
    jne .not_tp
    cmp byte [di+1], 'P'
    jne .bad_xcvr
    mov al, [di+2]
    call is_delim
    jne .bad_xcvr
    mov word [new_xcvr], 0      ; TP = transceiver type 0
    mov byte [do_write], 1
    jmp .no_xcvr
.not_tp:
    ; Check for "BNC" + delimiter
    cmp byte [di], 'B'
    jne .not_bnc
    cmp byte [di+1], 'N'
    jne .bad_xcvr
    cmp byte [di+2], 'C'
    jne .bad_xcvr
    mov al, [di+3]
    call is_delim
    jne .bad_xcvr
    mov word [new_xcvr], 3      ; BNC = transceiver type 3
    mov byte [do_write], 1
    jmp .no_xcvr
.not_bnc:
    ; Check for "AUI" + delimiter
    cmp byte [di], 'A'
    jne .bad_xcvr
    cmp byte [di+1], 'U'
    jne .bad_xcvr
    cmp byte [di+2], 'I'
    jne .bad_xcvr
    mov al, [di+3]
    call is_delim
    jne .bad_xcvr
    mov word [new_xcvr], 1      ; AUI = transceiver type 1
    mov byte [do_write], 1
    jmp .no_xcvr
.bad_xcvr:
    mov dx, msg_bad_xcvr
    call print_str
    jmp .parse_err
.no_xcvr:
    ret

.parse_err:
    mov ax, 0x4C01              ; Exit with error
    int 0x21


; ============================================================
; check_unknown_flags
;
; Scan the command line for any '/' that doesn't start a known
; flag. This catches typos like /IRG:3 or /XCVR:TP (extra space
; issues) that would otherwise be silently ignored.
;
; For each '/' found, tries to match against all known flags
; (/?  /P:  /IRQ:  /IO:  /XCVR:). If none match, prints an
; error and exits.
; ============================================================

check_unknown_flags:
    mov di, 0x81                ; Start of command line

.scan:
    mov al, [di]
    test al, al
    jz .ok                      ; End of command line, all clear

    cmp al, '/'
    jne .skip                   ; Not a flag start, advance

    ; Found '/'. Check if it matches any known flag prefix.
    mov si, flag_help
    call starts_with
    jnc .skip                   ; Matched /?
    mov si, flag_p
    call starts_with
    jnc .skip                   ; Matched /P:
    mov si, flag_irq
    call starts_with
    jnc .skip                   ; Matched /IRQ:
    mov si, flag_io
    call starts_with
    jnc .skip                   ; Matched /IO:
    mov si, flag_xcvr
    call starts_with
    jnc .skip                   ; Matched /XCVR:

    ; No known flag matched — this is an unrecognized option.
    mov dx, msg_unknown
    call print_str
    mov ax, 0x4C01
    int 0x21

.skip:
    inc di
    jmp .scan

.ok:
    ret


; ============================================================
; starts_with
;
; Check if the string at [DI] begins with the null-terminated
; string at [SI].
;
; Input:  DI = string to test, SI = prefix to match
; Output: CF = 0 if [DI] starts with [SI], CF = 1 if not
; Preserves: DI, SI
; ============================================================

starts_with:
    push si
    push di
.loop:
    lodsb                       ; AL = next char from prefix
    test al, al
    jz .match                   ; End of prefix = full match
    cmp al, [di]
    jne .nomatch
    inc di
    jmp .loop
.match:
    pop di
    pop si
    clc
    ret
.nomatch:
    pop di
    pop si
    stc
    ret


; ============================================================
; find_flag
;
; Substring search: find a null-terminated string in the
; command line (starting at 0x81).
;
; Input:  SI = pointer to search string (e.g., "/IRQ:\0")
; Output: DI = pointer to first char after the match
;         CF = 0 if found, CF = 1 if not found
; Clobbers: AX
;
; Example: if cmdline is " /IRQ:3 /XCVR:TP" and search is
; "/IRQ:", DI will point to "3 /XCVR:TP".
; ============================================================

find_flag:
    push bx
    push si
    mov bx, si                  ; BX = search string start (preserved)
    mov di, 0x81                ; DI scans the command line

.scan:
    mov al, [di]
    test al, al
    jz .notfound                ; Reached end of command line

    ; Attempt to match the search string starting at [di]
    mov si, bx                  ; Reset search pointer to start
    push di                     ; Save current scan position

.match:
    lodsb                       ; AL = next char from search string (advances SI)
    test al, al
    jz .matched                 ; Null terminator = entire search string matched

    mov ah, [di]
    test ah, ah
    jz .nomatch                 ; Command line ended before search string

    cmp al, ah                  ; Compare search char with command line char
    jne .nomatch

    inc di
    jmp .match

.matched:
    pop ax                      ; Discard saved scan position (don't need it)
    pop si
    pop bx
    clc                         ; CF=0: found
    ret

.nomatch:
    pop di                      ; Restore scan position
    inc di                      ; Advance to next position and try again
    jmp .scan

.notfound:
    pop si
    pop bx
    stc                         ; CF=1: not found
    ret


; ============================================================
; detect_card
;
; Find a 3C509B card using the ISA ID port mechanism:
;   1. Send the 255-byte LFSR pattern + global reset
;   2. Re-send the pattern (card enters ID_CMD state)
;   3. Read EEPROM word 8 via ID port to get I/O base
;   4. Tag and activate the card
;
; After this, the card responds at its configured I/O base.
; Sets: [iobase]
; ============================================================

detect_card:
    ; Phase 1: Global reset to ensure a clean state.
    ; Must send ID pattern first to enter ID_CMD state.
    call send_id_pattern
    mov dx, ID_PORT
    mov al, ID_RESET            ; Reset all untagged cards
    out dx, al
    call delay_5ms              ; Wait for reset to complete

    ; Phase 2: Re-send pattern to re-enter ID_CMD state.
    call send_id_pattern

    ; Phase 3: Read the I/O base from EEPROM word 8.
    ; Word 8 bits 4:0 encode the I/O base:
    ;   I/O base = (value << 4) + 0x200
    ; Example: value 0x10 -> (0x10 << 4) + 0x200 = 0x300
    mov al, EE_IFXCVR           ; Word index 8
    call id_read_eeprom         ; AX = word 8
    and ax, 0x1F                ; Mask bits 4:0
    mov cl, 4
    shl ax, cl                  ; Shift left 4 (multiply by 16)
    add ax, 0x200               ; Add base offset
    mov [iobase], ax

    ; Phase 4: Tag the card so it won't respond to future
    ; ID sequences, then activate it at the I/O base.
    mov dx, ID_PORT
    mov al, ID_TAG              ; Tag with value 0
    out dx, al
    mov al, ID_ACTIVATE         ; Activate at EEPROM I/O base
    out dx, al
    call delay_5ms

    ret


; ============================================================
; send_id_pattern
;
; The 3C509B requires a specific 255-byte pattern to be written
; to the ID port before it will respond to commands. The pattern
; is generated by a Linear Feedback Shift Register (LFSR) with
; polynomial 0xCF.
;
; Algorithm:
;   1. Write 0x00 to reset the card's pattern generator
;   2. Start with value 0xFF
;   3. For 255 iterations:
;      a. Write current value to ID port
;      b. If bit 7 is set: shift left, XOR with 0xCF
;         Otherwise: just shift left
;
; The card simultaneously runs the same LFSR. When all 255
; bytes match, the card transitions to ID_CMD state.
; ============================================================

send_id_pattern:
    push cx
    mov dx, ID_PORT
    xor al, al
    out dx, al                  ; Reset hardware pattern generator

    mov al, 0xFF                ; Initial LFSR value
    mov cx, 255                 ; 255 iterations
.loop:
    out dx, al                  ; Write current value
    test al, 0x80               ; Is bit 7 (MSB) set?
    jz .noxor
    shl al, 1                   ; Shift left (bit 7 goes to carry)
    xor al, 0xCF                ; Apply LFSR polynomial feedback
    jmp .next
.noxor:
    shl al, 1                   ; Just shift, no feedback
.next:
    loop .loop

    pop cx
    ret


; ============================================================
; id_read_eeprom
;
; Read one EEPROM word via the ID port. This only works before
; the card has been activated. After activation, use
; reg_read_eeprom instead.
;
; The ID port returns data one bit at a time (LSB of each byte
; read). 16 reads are needed to clock in a full word, MSB first.
;
; Input:  AL = word index (0-15)
; Output: AX = 16-bit word value
; ============================================================

id_read_eeprom:
    push bx
    push cx
    push dx

    or al, EE_READ              ; Command byte = 0x80 | index
    mov dx, ID_PORT
    out dx, al                  ; Issue read command

    call delay_1ms
    call delay_1ms              ; Wait ~2ms for EEPROM read to complete

    ; Clock in 16 bits. Each read from the ID port returns the
    ; next bit in bit 0. Bits arrive MSB first.
    xor bx, bx                  ; BX accumulates the result
    mov cx, 16
.loop:
    in al, dx                   ; Read one bit from ID port
    and al, 0x01                ; Isolate bit 0
    shl bx, 1                   ; Make room for new bit
    or bl, al                   ; Insert it
    loop .loop

    mov ax, bx                  ; Return result in AX

    pop dx
    pop cx
    pop bx
    ret


; ============================================================
; read_all_eeprom
;
; Read all 16 EEPROM words into the ee_words[] buffer using
; register-based access (card must be activated, Window 0
; selected).
;
; Output: CF = 0 success, CF = 1 if any read timed out
; ============================================================

read_all_eeprom:
    push bx
    push cx

    mov bx, ee_words            ; BX = destination pointer
    xor cx, cx                  ; CX = word index (0-15)
.loop:
    mov al, cl
    call reg_read_eeprom        ; AX = EEPROM word [cl]
    jc .read_fail               ; Abort on timeout
    mov [bx], ax                ; Store in buffer
    add bx, 2                   ; Advance to next word (16-bit)
    inc cl
    cmp cl, 16
    jb .loop

    pop cx
    pop bx
    clc
    ret

.read_fail:
    pop cx
    pop bx
    stc
    ret


; ============================================================
; reg_read_eeprom
;
; Read one EEPROM word via Window 0 registers.
;
; Sequence:
;   1. Wait for EEPROM not busy (bit 15 of command register)
;   2. Write (EE_READ | index) to command register
;   3. Wait for read to complete
;   4. Read result from data register
;
; Input:  AL = word index (0-15)
; Output: AX = word value, CF = 0 success
;         AX = 0xFFFF, CF = 1 on timeout
; ============================================================

reg_read_eeprom:
    push dx
    push cx

    xor ah, ah
    or al, EE_READ              ; Build command: 0x80 | index
    push ax                     ; Save command on stack

    ; Wait for EEPROM controller not busy.
    ; Bit 15 of the command register = busy flag.
    mov dx, [iobase]
    add dx, W0_EECMD
    mov cx, 2000                ; Timeout counter
.wait1:
    in ax, dx
    test ah, 0x80               ; Test bit 15 (busy)
    jz .rdy1
    loop .wait1
    jmp .fail                   ; Timed out waiting
.rdy1:
    pop ax                      ; Retrieve command
    out dx, ax                  ; Issue read command

    call delay_1ms
    call delay_1ms              ; Wait ~2ms for EEPROM read

    ; Wait for read to complete
    mov cx, 2000
.wait2:
    in ax, dx
    test ah, 0x80
    jz .rdy2
    loop .wait2
    jmp .fail2                  ; Timed out (command already popped)
.rdy2:
    ; Read the result from the data register
    mov dx, [iobase]
    add dx, W0_EEDATA
    in ax, dx

    pop cx
    pop dx
    clc                         ; Success
    ret

.fail:
    pop ax                      ; Discard saved command
.fail2:
    mov ax, 0xFFFF              ; Error sentinel
    pop cx
    pop dx
    stc                         ; Failure
    ret


; ============================================================
; reg_write_eeprom
;
; Write one EEPROM word via Window 0 registers.
; Based on write_eeprom() from 3c5x9setup by Donald Becker.
;
; The EEPROM requires a specific sequence:
;   1. Wait for not busy
;   2. Send EWENB (enable erase/write, valid for ~10ms)
;   3. Send ERASE | index (erase the target location)
;   4. Wait for erase to complete
;   5. Send EWENB again (enable expired after erase)
;   6. Write data to the data register
;   7. Send WRITE | index
;   8. Wait for write to complete
;
; Input:  AL = word index (0-15), BX = value to write
; Output: CF = 0 success, CF = 1 failure (timeout)
; ============================================================

reg_write_eeprom:
    push dx
    push cx
    push ax

    xor ah, ah
    push ax                     ; Save index on stack

    mov dx, [iobase]
    add dx, W0_EECMD            ; DX = command register address

    ; Step 1: Wait for not busy
    mov cx, 2000
.w0:
    in ax, dx
    test ah, 0x80
    jz .r0
    loop .w0
    jmp .fail
.r0:
    ; Step 2: Enable erase/write
    mov ax, EE_EWENB
    out dx, ax
    call delay_100us

    ; Step 3: Erase the target location
    pop ax                      ; Get index
    push ax                     ; Keep it for later
    or ax, EE_ERASE             ; Command = 0xC0 | index
    out dx, ax
    call delay_100us

    ; Step 4: Wait for erase to complete
    mov cx, 16000               ; Longer timeout for erase
.w1:
    in ax, dx
    test ah, 0x80
    jz .r1
    loop .w1
    jmp .fail
.r1:
    ; Step 5: Re-enable writes (EWENB expired after erase)
    mov ax, EE_EWENB
    out dx, ax
    call delay_100us

    ; Step 6: Write the data value to the data register
    push dx                     ; Save command register address
    mov dx, [iobase]
    add dx, W0_EEDATA           ; Switch to data register
    mov ax, bx                  ; BX = value to write
    out dx, ax
    pop dx                      ; Restore command register address

    ; Step 7: Issue the write command
    pop ax                      ; Get index
    push ax                     ; Keep it for stack cleanup
    or ax, EE_WRITE             ; Command = 0x40 | index
    out dx, ax

    ; Step 8: Wait for write to complete
    mov cx, 16000
.w2:
    in ax, dx
    test ah, 0x80
    jz .r2
    loop .w2
    jmp .fail
.r2:
    pop ax                      ; Clean up: discard index
    pop ax                      ; Restore original AX
    pop cx
    pop dx
    clc                         ; Success
    ret

.fail:
    pop ax                      ; Clean up stack (index)
    pop ax                      ; Restore original AX
    pop cx
    pop dx
    stc                         ; Failure
    ret


; ============================================================
; write_settings
;
; Apply user-requested changes to the EEPROM. Only modifies
; words that the user specified via command-line flags.
;
; Word 8 (EE_IFXCVR) encodes both transceiver and I/O base:
;   Bits 15:14 = transceiver type (0=TP, 1=AUI, 3=BNC)
;   Bits 4:0   = I/O encoding: base = (value << 4) + 0x200
;
; Word 9 (EE_IRQLINE) encodes the IRQ:
;   Bits 15:12 = IRQ number
;   Bits 11:0  = resource config (preserved when changing IRQ)
;
; After modifying any words, the checksum (word 15) is
; recalculated and written.
;
; Output: AL = 0 success, AL = 1 failure
; ============================================================

write_settings:
    ; ---- Check if word 8 needs modification ----
    cmp word [new_xcvr], 0xFFFF     ; 0xFFFF = no change requested
    jne .do_word8
    cmp word [new_iobase], 0xFFFF
    jne .do_word8
    jmp .check_irq                  ; Skip word 8

.do_word8:
    mov ax, [ee_words + EE_IFXCVR * 2]  ; Load current word 8

    ; Apply new transceiver type if requested
    cmp word [new_xcvr], 0xFFFF
    je .no_xcvr
    and ax, 0x3FFF              ; Clear bits 15:14 (transceiver)
    mov bx, [new_xcvr]          ; BX = new transceiver type (0, 1, or 3)
    mov cl, 14
    shl bx, cl                  ; Shift to bits 15:14
    or ax, bx                   ; Merge in
.no_xcvr:

    ; Apply new I/O base if requested
    cmp word [new_iobase], 0xFFFF
    je .no_io
    and ax, 0xFFE0              ; Clear bits 4:0 (I/O encoding)
    mov bx, [new_iobase]        ; BX = new I/O base (e.g., 0x300)
    sub bx, 0x200               ; Subtract base offset
    mov cl, 4
    shr bx, cl                  ; Shift right 4 to get encoding
    and bx, 0x1F                ; Mask to 5 bits
    or ax, bx                   ; Merge in
.no_io:

    ; Write modified word 8 to EEPROM
    mov [ee_words + EE_IFXCVR * 2], ax  ; Update local copy
    mov bx, ax                  ; BX = value to write
    mov al, EE_IFXCVR           ; AL = word index 8
    push dx
    mov dx, msg_wio
    call print_str
    pop dx
    call reg_write_eeprom
    jc .failed
    push dx
    mov dx, msg_ok
    call print_str
    pop dx

.check_irq:
    ; ---- Check if word 9 needs modification ----
    cmp word [new_irq], 0xFFFF
    je .do_cksum                ; Skip if no IRQ change

    mov ax, [ee_words + EE_IRQLINE * 2]  ; Load current word 9
    and ax, 0x0FFF              ; Clear bits 15:12 (IRQ number)
    mov bx, [new_irq]           ; BX = new IRQ number
    mov cl, 12
    shl bx, cl                  ; Shift to bits 15:12
    or ax, bx                   ; Merge in (preserves bits 11:0)

    ; Write modified word 9 to EEPROM
    mov [ee_words + EE_IRQLINE * 2], ax
    mov bx, ax
    mov al, EE_IRQLINE          ; Word index 9
    push dx
    mov dx, msg_wirq
    call print_str
    pop dx
    call reg_write_eeprom
    jc .failed
    push dx
    mov dx, msg_ok
    call print_str
    pop dx

.do_cksum:
    ; Always recalculate and write the checksum after any changes
    call calc_checksum          ; AX = new checksum
    mov [ee_words + EE_CKSUM * 2], ax
    mov bx, ax
    mov al, EE_CKSUM            ; Word index 15
    push dx
    mov dx, msg_wcksum
    call print_str
    pop dx
    call reg_write_eeprom
    jc .failed
    push dx
    mov dx, msg_ok
    call print_str
    pop dx

    xor al, al                  ; AL = 0: success
    ret

.failed:
    push dx
    mov dx, msg_fail
    call print_str
    pop dx
    mov al, 1                   ; AL = 1: failure
    ret


; ============================================================
; calc_checksum
;
; The 3C509B EEPROM checksum (word 15) is split into two
; independent parts:
;
;   "Fixed" words: 0-7, 10-12, 14 (MAC address, model, etc.)
;   "Variable" words: 8, 9, 13 (I/O, IRQ, driver tuning)
;
; Each set is XOR'd together, then combined:
;   High byte = fixed_hi XOR fixed_lo
;   Low byte  = var_lo XOR var_hi
;
; This design lets the card independently validate the
; factory-set data and the user-configurable settings.
;
; Input:  ee_words[0..14] must be populated
; Output: AX = checksum value for word 15
; ============================================================

calc_checksum:
    push bx
    push cx
    push si
    push dx

    xor bx, bx                 ; BX = fixed checksum accumulator
    xor cx, cx                  ; CX = variable checksum accumulator
    mov si, ee_words            ; SI walks the EEPROM buffer
    xor dx, dx                  ; DX = word index counter

.loop:
    mov ax, [si]                ; Load current EEPROM word

    ; Is this a "variable" word? (8, 9, or 13)
    cmp dx, EE_IFXCVR
    je .var
    cmp dx, EE_IRQLINE
    je .var
    cmp dx, EE_TUNE
    je .var

    xor bx, ax                 ; Fixed: accumulate into BX
    jmp .next
.var:
    xor cx, ax                  ; Variable: accumulate into CX
.next:
    add si, 2                   ; Next word (16-bit = 2 bytes)
    inc dx
    cmp dx, 15                  ; Process words 0 through 14
    jb .loop

    ; Compute high byte: (fixed ^ (fixed << 8)) & 0xFF00
    ; This XORs the high and low bytes of the fixed checksum,
    ; placing the result in the high byte.
    mov ax, bx
    mov cl, 8
    shl ax, cl                  ; AX = fixed << 8
    xor ax, bx                 ; AX = fixed ^ (fixed << 8)
    and ax, 0xFF00              ; Keep only high byte
    push ax                     ; Save high byte part

    ; Compute low byte: (var ^ (var >> 8)) & 0x00FF
    ; Same idea for the variable checksum, result in low byte.
    mov ax, cx
    mov cl, 8
    shr ax, cl                  ; AX = var >> 8
    xor ax, cx                 ; AX = var ^ (var >> 8)
    and ax, 0x00FF              ; Keep only low byte

    pop bx                      ; Retrieve high byte part
    or ax, bx                   ; Combine into final checksum

    pop dx
    pop si
    pop cx
    pop bx
    ret


; ============================================================
; show_config
;
; Display current card settings from the ee_words[] buffer.
; Prints: MAC address, I/O base, IRQ, transceiver type,
; and checksum with validity check.
; ============================================================

show_config:
    ; ---- MAC address (6 bytes from words 0, 1, 2) ----
    ; Each EEPROM word stores two bytes in big-endian order:
    ; high byte first, then low byte. So word 0 high byte = MAC[0].
    mov dx, msg_mac
    call print_str

    mov ax, [ee_words + EE_NODE0 * 2]
    xchg al, ah                 ; Print high byte (MAC[0]) first
    call print_hex2
    mov dl, ':'
    call print_char
    mov ax, [ee_words + EE_NODE0 * 2]
    call print_hex2             ; Print low byte (MAC[1])
    mov dl, ':'
    call print_char

    mov ax, [ee_words + EE_NODE1 * 2]
    xchg al, ah
    call print_hex2
    mov dl, ':'
    call print_char
    mov ax, [ee_words + EE_NODE1 * 2]
    call print_hex2
    mov dl, ':'
    call print_char

    mov ax, [ee_words + EE_NODE2 * 2]
    xchg al, ah
    call print_hex2
    mov dl, ':'
    call print_char
    mov ax, [ee_words + EE_NODE2 * 2]
    call print_hex2
    mov dx, msg_nl
    call print_str

    ; ---- I/O base address ----
    ; Decoded from word 8 bits 4:0: base = (value << 4) + 0x200
    mov dx, msg_iobase
    call print_str
    mov ax, [ee_words + EE_IFXCVR * 2]
    and ax, 0x1F
    mov cl, 4
    shl ax, cl
    add ax, 0x200
    call print_hex4
    mov dx, msg_h_nl
    call print_str

    ; ---- IRQ number ----
    ; From word 9 bits 15:12
    mov dx, msg_irq
    call print_str
    mov ax, [ee_words + EE_IRQLINE * 2]
    mov cl, 12
    shr ax, cl
    and ax, 0x0F
    call print_dec
    mov dx, msg_nl
    call print_str

    ; ---- Transceiver type ----
    ; From word 8 bits 15:14: 0=TP, 1=AUI, 2=undefined, 3=BNC
    mov dx, msg_xcvr
    call print_str
    mov ax, [ee_words + EE_IFXCVR * 2]
    mov cl, 14
    shr ax, cl
    and ax, 0x03
    cmp ax, 0
    je .xtp
    cmp ax, 1
    je .xaui
    cmp ax, 3
    je .xbnc
    mov dx, str_unk
    jmp .xprint
.xtp:
    mov dx, str_tp
    jmp .xprint
.xaui:
    mov dx, str_aui
    jmp .xprint
.xbnc:
    mov dx, str_bnc
.xprint:
    call print_str

    ; ---- Checksum ----
    ; Display stored checksum and verify against computed value
    mov dx, msg_cksum
    call print_str
    mov ax, [ee_words + EE_CKSUM * 2]
    call print_hex4

    push ax                     ; Save stored checksum
    call calc_checksum          ; AX = computed checksum
    pop bx                      ; BX = stored checksum
    cmp ax, bx
    je .ckok
    mov dx, str_ckerr           ; Mismatch!
    call print_str
    ret
.ckok:
    mov dx, str_ckok
    call print_str
    ret


; ============================================================
; Delay routines
;
; On the ISA bus, each I/O port read takes approximately 1-2
; microseconds. Reading from port 0x80 (POST diagnostic port)
; is safe and serves as a portable delay mechanism.
; ============================================================

delay_100us:
    push cx
    mov cx, 100
.lp:
    in al, 0x80                 ; ~1-2us per read
    loop .lp
    pop cx
    ret

delay_1ms:
    push cx
    mov cx, 1000
.lp:
    in al, 0x80
    loop .lp
    pop cx
    ret

delay_5ms:
    call delay_1ms
    call delay_1ms
    call delay_1ms
    call delay_1ms
    call delay_1ms
    ret


; ============================================================
; Print routines
;
; All output uses DOS INT 21h services:
;   AH=09h: Print '$'-terminated string (address in DX)
;   AH=02h: Print single character (character in DL)
; ============================================================

; print_str: Print '$'-terminated string at address DX
print_str:
    push ax
    mov ah, 0x09
    int 0x21
    pop ax
    ret

; print_char: Print single character in DL
print_char:
    push ax
    mov ah, 0x02
    int 0x21
    pop ax
    ret

; print_hex4: Print 16-bit AX as 4 hex digits (e.g., "03F8")
print_hex4:
    push ax
    xchg al, ah                 ; Print high byte first
    call print_hex2
    pop ax
    call print_hex2             ; Then low byte
    ret

; print_hex2: Print 8-bit AL as 2 hex digits (e.g., "3F")
print_hex2:
    push ax
    push cx
    mov ah, al                  ; Save original in AH
    mov cl, 4
    shr al, cl                  ; High nibble
    call .nib
    mov al, ah
    and al, 0x0F                ; Low nibble
    call .nib
    pop cx
    pop ax
    ret
.nib:
    add al, '0'                 ; Convert 0-9 to '0'-'9'
    cmp al, '9'
    jbe .d
    add al, 7                   ; Convert 10-15 to 'A'-'F'
.d:
    mov dl, al
    jmp print_char              ; Tail call

; print_dec: Print 16-bit AX as unsigned decimal, no leading zeros
; Uses repeated division by 10; digits are pushed onto the stack
; in reverse order, then popped and printed.
print_dec:
    push ax
    push bx
    push cx
    push dx

    xor cx, cx                  ; CX = digit count
    mov bx, 10
.div:
    xor dx, dx                  ; Zero DX for 16-bit division
    div bx                      ; AX = quotient, DX = remainder
    push dx                     ; Save digit (remainder)
    inc cx
    test ax, ax                 ; More digits?
    jnz .div
.pr:
    pop dx                      ; Retrieve digits in correct order
    add dl, '0'
    call print_char
    loop .pr

    pop dx
    pop cx
    pop bx
    pop ax
    ret


; ============================================================
; Number parsing
;
; Both parsers advance SI past the consumed digits. After
; returning, [SI] points to the first non-digit character.
; Callers check this character with is_delim to reject
; trailing junk (e.g., "/IRQ:3XYZ").
;
; Both return CF=1 on overflow to prevent wrap-around values
; from silently passing validation.
; ============================================================

; parse_hex: Parse hex number from string at [SI]
; Output: AX = value, CF=0 success
;         CF=1 if more than 4 hex digits (overflow)
parse_hex:
    push bx
    push cx
    xor ax, ax                  ; Accumulator
    xor ch, ch                  ; Digit count
.loop:
    mov bl, [si]
    cmp bl, '0'
    jb .done
    cmp bl, '9'
    jbe .dig
    cmp bl, 'A'
    jb .done                    ; Not a hex digit
    cmp bl, 'F'
    ja .done
    sub bl, 'A' - 10            ; Convert 'A'-'F' to 10-15
    jmp .add
.dig:
    sub bl, '0'                 ; Convert '0'-'9' to 0-9
.add:
    inc ch
    cmp ch, 4                   ; Max 4 hex digits (0000-FFFF)
    ja .overflow
    mov cl, 4
    shl ax, cl                  ; Make room for new nibble
    xor bh, bh
    or ax, bx                   ; Insert digit
    inc si                      ; Advance past consumed digit
    jmp .loop
.done:
    pop cx
    pop bx
    clc
    ret
.overflow:
    pop cx
    pop bx
    stc
    ret

; parse_dec: Parse decimal number from string at [SI]
; Output: AX = value, CF=0 success
;         CF=1 if value exceeds 65535
; Note: leading zeros are accepted (e.g., "003" parses as 3).
; Overflow is detected via DX after mul and carry after add.
parse_dec:
    push bx
    push cx
    push dx
    xor ax, ax                  ; Accumulator
.loop:
    mov bl, [si]
    cmp bl, '0'
    jb .done
    cmp bl, '9'
    ja .done
    mov cx, 10
    mul cx                      ; DX:AX = AX * 10
    test dx, dx                 ; Did result overflow into DX?
    jnz .overflow
    xor bh, bh
    sub bl, '0'
    add ax, bx                  ; Add new digit
    jc .overflow                ; Carry means result > 65535
    inc si
    jmp .loop
.done:
    pop dx
    pop cx
    pop bx
    clc
    ret
.overflow:
    pop dx
    pop cx
    pop bx
    stc
    ret

; is_delim: Check if AL is a token delimiter
; A delimiter marks the end of a command-line value.
; Valid delimiters: null (end of line), space, / (next flag)
; Output: ZF=1 if delimiter, ZF=0 if not
is_delim:
    test al, al                 ; Null terminator?
    jz .yes
    cmp al, ' '                 ; Space?
    je .yes
    cmp al, '/'                 ; Start of next flag?
    je .yes
    or al, 1                    ; Clear ZF (not a delimiter)
    ret
.yes:
    xor al, al                  ; Set ZF (is a delimiter)
    ret


; ============================================================
; Data - Strings and messages
;
; DOS INT 21h function 09h prints strings terminated by '$'.
; CR (13) + LF (10) = newline on DOS.
; ============================================================

; Flag strings for command-line matching (null-terminated)
flag_help   db '/?', 0
flag_p      db '/P:', 0
flag_irq    db '/IRQ:', 0
flag_io     db '/IO:', 0
flag_xcvr   db '/XCVR:', 0

; Status messages
msg_banner  db '3C5X9CFG - 3C509B Configuration Utility', 13, 10, 13, 10, '$'
msg_searching db 'Searching via ID port...', 13, 10, '$'
msg_found   db 'Found 3C509B at $'
msg_h_nl    db 'h', 13, 10, '$'
msg_nl      db 13, 10, '$'
msg_current db 13, 10, 'Current settings:', 13, 10, '$'
msg_writing db 13, 10, 'Writing EEPROM:', 13, 10, '$'
msg_newcfg  db 13, 10, 'New settings:', 13, 10, '$'
msg_reboot  db 13, 10, 'Reboot for changes to take effect.', 13, 10, '$'

; Error messages
msg_notfound db 'ERROR: 3C509B not found', 13, 10, '$'
msg_wfail   db 'ERROR: EEPROM write failed', 13, 10, '$'
msg_rfail   db 'ERROR: EEPROM read failed (timeout)', 13, 10, '$'
msg_bad_irq db 'ERROR: Invalid IRQ. Valid: 3,5,7,9,10,11,12,15', 13, 10, '$'
msg_bad_io  db 'ERROR: Invalid I/O. Valid: 200-3E0, 16-byte aligned', 13, 10, '$'
msg_bad_xcvr db 'ERROR: Invalid xcvr. Valid: TP, BNC, AUI', 13, 10, '$'
msg_bad_p   db 'ERROR: Invalid /P: address. Valid: 200-3F0, 16-byte aligned', 13, 10, '$'
msg_unknown db 'ERROR: Unrecognized option. Use /? for help.', 13, 10, '$'

; Config display labels
msg_mac     db '  MAC:    $'
msg_iobase  db '  I/O:    $'
msg_irq     db '  IRQ:    $'
msg_xcvr    db '  Xcvr:   $'
msg_cksum   db '  Cksum:  $'

; EEPROM write progress messages
msg_wio     db '  I/O config...$'
msg_wirq    db '  IRQ config...$'
msg_wcksum  db '  Checksum...$'
msg_ok      db ' OK', 13, 10, '$'
msg_fail    db ' FAILED', 13, 10, '$'

; Transceiver type names
str_tp      db 'TP (10baseT)', 13, 10, '$'
str_aui     db 'AUI', 13, 10, '$'
str_bnc     db 'BNC (10base2)', 13, 10, '$'
str_unk     db 'Unknown', 13, 10, '$'

; Checksum status
str_ckok    db ' (OK)', 13, 10, '$'
str_ckerr   db ' (ERROR)', 13, 10, '$'

; Help text (displayed for /?)
msg_usage:
    db '3C5X9CFG - 3C509B NIC Configuration Utility', 13, 10
    db 13, 10
    db 'Usage: 3C5X9CFG [/P:base] [/IRQ:n] [/IO:nnn] [/XCVR:type]', 13, 10
    db 13, 10
    db '  /P:base      I/O base in hex (skip autodetect)', 13, 10
    db '  /IRQ:n       Set IRQ (3,5,7,9,10,11,12,15)', 13, 10
    db '  /IO:nnn      Set I/O base in hex (200-3E0)', 13, 10
    db '  /XCVR:type   Set transceiver (TP, BNC, AUI)', 13, 10
    db '  /?           Show this help', 13, 10
    db 13, 10
    db 'Examples:', 13, 10
    db '  3C5X9CFG                  Show current settings', 13, 10
    db '  3C5X9CFG /IRQ:3 /XCVR:TP Set IRQ 3, twisted pair', 13, 10
    db '$'


; ============================================================
; Variables
;
; These are initialized with default values. 0xFFFF means
; "no change requested" for the new_* variables.
; ============================================================

iobase      dw 0                ; Card's active I/O base (set by detect_card)
user_iobase dw 0                ; User-specified via /P: (0 = autodetect)
new_irq     dw 0xFFFF           ; Requested new IRQ (0xFFFF = no change)
new_iobase  dw 0xFFFF           ; Requested new I/O base (0xFFFF = no change)
new_xcvr    dw 0xFFFF           ; Requested new transceiver (0xFFFF = no change)
do_write    db 0                ; Nonzero if any EEPROM writes are needed

; Buffer for all 16 EEPROM words (read from card)
ee_words:   times 16 dw 0
