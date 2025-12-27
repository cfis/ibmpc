' ============================================================================
' RECEIVE-BINARY.BAS - Binary File Receiver for IBM PC
' ============================================================================
'
' DESCRIPTION:
'   A GW-BASIC program for receiving binary files (including executables)
'   over a serial connection. Uses random access file mode to write raw
'   bytes without text-mode corruption.
'
' AUTHOR:
'   Created during IBM PC file recovery project, December 2024
'
' WHY THIS EXISTS:
'   GW-BASIC's FOR OUTPUT opens files in text mode, which corrupts binary
'   files. This program uses FOR RANDOM with FIELD/LSET/PUT to write raw
'   bytes, enabling transfer of .EXE, .COM, and other binary files.
'
' COMPANION PROGRAM:
'   Use with send_binary.rb on the sending computer. The sender must
'   pad files to a multiple of 128 bytes.
'
' HARDWARE REQUIREMENTS:
'   - IBM PC or compatible with serial port (COM1)
'   - RS-232 serial card with 8250 UART
'   - Null modem cable connection to sending computer
'
' USAGE:
'   1. Modify line 30 to specify the output filename
'   2. Start the Ruby sender: ruby send_binary.rb COM3 FILE.EXE 4800
'   3. RUN this program on the IBM PC
'   4. Wait for transfer to complete (sender will show 100%)
'   5. Press Ctrl+Break on the PC
'
' SERIAL PORT CONFIGURATION:
'   - COM1 at 4800 baud, 8N1, no flow control
'   - Must match sender configuration exactly
'
' KEY CONCEPTS:
'
'   RANDOM ACCESS FILES:
'     GW-BASIC random access files consist of fixed-length records.
'     Each PUT writes one complete record. This is different from
'     text mode which writes variable-length lines.
'
'   FIELD STATEMENT:
'     FIELD #2, 128 AS F$
'     Creates a 128-byte buffer (F$) linked to file #2.
'     All PUT operations write this buffer.
'
'   LSET STATEMENT:
'     LSET F$ = B$
'     Copies data into the field buffer, left-justified.
'     Since we read exactly 128 bytes, no padding occurs.
'
'   INPUT$ ON COM PORTS:
'     INPUT$(128, #1) blocks until exactly 128 bytes arrive.
'     This simplifies the receive loop - no accumulation needed.
'
'   WHY 128 BYTES:
'     - Matches common disk sector sizes
'     - File must be padded to multiple of 128 on sender side
'     - Ensures every record is complete
'
' ERROR HANDLING:
'   ERR=24 : Device timeout (normal at end of transfer)
'   ERR=57 : Device I/O error (buffer overrun - try lower baud rate)
'   ERR=75 : Path/file access error (add RS to COM open string)
'
' ============================================================================

10 ON ERROR GOTO 900
20 OPEN "COM1:4800,N,8,1,RS,CS0,DS0,CD0" AS #1
30 OPEN "MSKERMIT.EXE" FOR RANDOM AS #2 LEN=128
40 FIELD #2, 128 AS F$
50 RECORD = 1: COUNT = 128
60 B$ = INPUT$(COUNT, #1)
70 LSET F$ = B$
80 PUT #2, RECORD
90 RECORD = RECORD + 1
100 GOTO 60
900 PRINT "ERR=";ERR;" ERL=";ERL
910 CLOSE
920 PRINT "Received"; RECORD-1; "records"
930 END

' ============================================================================
' LINE-BY-LINE EXPLANATION:
' ============================================================================
'
' Line 10: ON ERROR GOTO 900
'   Error handler setup. All errors jump to line 900.
'
' Line 20: OPEN "COM1:4800,N,8,1,RS,CS0,DS0,CD0" AS #1
'   Opens serial port:
'   - COM1: First serial port
'   - 4800: Baud rate (must match sender)
'   - N: No parity
'   - 8: 8 data bits
'   - 1: 1 stop bit
'   - RS: Suppress RTS (prevents ERR=75)
'   - CS0,DS0,CD0: Disable hardware flow control signals
'
' Line 30: OPEN "MSKERMIT.EXE" FOR RANDOM AS #2 LEN=128
'   Opens output file in random access mode:
'   - FOR RANDOM: Random access (not text mode!)
'   - LEN=128: Each record is 128 bytes
'   - Change filename here for different target file
'
' Line 40: FIELD #2, 128 AS F$
'   Creates the record buffer:
'   - Links F$ to file #2's record buffer
'   - F$ is exactly 128 bytes
'   - All PUT operations write F$ to disk
'
' Line 50: RECORD = 1: COUNT = 128
'   Initialize variables:
'   - RECORD: Current record number (1-based)
'   - COUNT: Bytes to read per record
'
' Line 60: B$ = INPUT$(COUNT, #1)
'   Read bytes from serial port:
'   - INPUT$(count, filenum) blocks until 'count' bytes arrive
'   - Returns exactly 128 bytes
'
' Line 70: LSET F$ = B$
'   Copy to the field buffer:
'   - LSET copies B$ into F$, the FIELD buffer
'   - Since B$ is exactly 128 bytes, no padding occurs
'
' Line 80: PUT #2, RECORD
'   Write the record to disk:
'   - Writes F$ (128 bytes) to record number RECORD
'   - File position = (RECORD-1) * 128
'
' Line 90: RECORD = RECORD + 1
'   Advance to next record number.
'
' Line 100: GOTO 60
'   Loop back to read more data.
'
' Line 900: PRINT "ERR=";ERR;" ERL=";ERL
'   Error handler - display error info.
'
' Line 910: CLOSE
'   Close all open files.
'   - Essential: file not properly saved without this!
'
' Line 920: PRINT "Received"; RECORD-1; "records"
'   Show how many records were written.
'   - Subtract 1 because RECORD was incremented before error
'
' Line 930: END
'   Program termination.
'
' ============================================================================
' WHY THE SENDER MUST PAD:
' ============================================================================
'
' INPUT$(128, #1) blocks until exactly 128 bytes arrive. If the file is
' not a multiple of 128 bytes, the receiver will hang waiting for the
' final partial block to complete.
'
' Solution: The sender pads the file with null bytes (0x00) to reach
' a multiple of 128. This ensures every block is complete.
'
' Example:
'   Original file: 185,123 bytes
'   185,123 / 128 = 1446.27 records (incomplete last record!)
'   Padded to: 185,216 bytes (1447 records x 128 bytes)
'   Extra 93 null bytes at end don't affect .EXE execution
'
' ============================================================================
' VARIABLE REFERENCE:
' ============================================================================
'
' RECORD  - Current record number being written (integer)
' COUNT   - Bytes to read per record, always 128 (integer)
' B$      - Input buffer, holds exactly 128 bytes per iteration (string)
' F$      - Field buffer, linked to file #2, always 128 bytes (string)
'
' File Handles:
' #1      - Serial port (COM1)
' #2      - Output file
'
' ============================================================================
' TROUBLESHOOTING:
' ============================================================================
'
' ERROR 24 (Device timeout):
'   Normal at end of transfer. Press Ctrl+Break, file should be complete.
'
' ERROR 57 (Device I/O error):
'   Buffer overrun - data arriving faster than PC can process.
'   Try lower baud rate (2400 instead of 4800).
'
' ERROR 75 (Path/file access error):
'   Add RS to COM port open string if not present.
'
' File wrong size:
'   Make sure sender is padding to 128-byte boundary.
'   File should be slightly larger than original.
'
' File corrupted:
'   Check baud rates match on both sides.
'   Try lower baud rate (2400 instead of 4800).
'
' Program hangs:
'   INPUT$ blocks until data arrives. Make sure sender is running.
'   If sender finished but receiver is waiting, the file wasn't
'   padded to a multiple of 128 bytes.
'
' ============================================================================
