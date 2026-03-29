' ============================================================================
' RECEIVE.BAS - Binary File Receiver for IBM PC
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
'   Use with send.rb on the sending computer. The sender must
'   pad files to a multiple of 128 bytes.
'
' HARDWARE REQUIREMENTS:
'   - IBM PC or compatible with serial port (COM1)
'   - RS-232 serial card with 8250 UART
'   - Null modem cable connection to sending computer
'
' USAGE:
'   1. RUN this program on the IBM PC
'   2. Enter the output filename when prompted (e.g., 3CCFG.EXE)
'   3. Start the Ruby sender: ruby send_binary.rb /dev/ttyUSB0 FILE.EXE 4800
'   4. The sender transmits the record count, then the data
'   5. The receiver exits automatically when all records are received
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
'     LSET F$ = LEFT$(B$,128)
'     Copies data into the field buffer, left-justified.
'
'   ACCUMULATION BUFFER:
'     Data may arrive from the serial port in chunks smaller than
'     128 bytes. B$ accumulates incoming data until a full record
'     is available. Any leftover bytes beyond 128 are carried over
'     to the next record via MID$(B$,129).
'
'   RECORD COUNT PROTOCOL:
'     The sender transmits the total number of 128-byte records as
'     a text line (e.g., "1447\r\n") before the binary data. The
'     receiver reads this with LINE INPUT and uses it to know when
'     to stop. VAL() converts the string to a number.
'
'   WHY 128 BYTES:
'     - Matches common disk sector sizes
'     - File must be padded to multiple of 128 on sender side
'     - Ensures every record is complete
'
' ERROR HANDLING:
'   ERR=24 : Device timeout
'   ERR=57 : Device I/O error (buffer overrun - try lower baud rate)
'   ERR=75 : Path/file access error (add RS to COM open string)
'
' ============================================================================

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
' Line 25: INPUT "File";N$
'   Prompts the user for the output filename (e.g., 3CCFG.EXE).
'
' Line 30: OPEN N$ FOR RANDOM AS #2 LEN=128
'   Opens the output file in random access mode:
'   - FOR RANDOM: Random access (not text mode!)
'   - LEN=128: Each record is 128 bytes
'
' Line 40: FIELD #2, 128 AS F$
'   Creates the record buffer:
'   - Links F$ to file #2's record buffer
'   - F$ is exactly 128 bytes
'   - All PUT operations write F$ to disk
'
' Line 45: LINE INPUT #1, T$: TOTAL = VAL(T$)
'   Reads the record count from the sender:
'   - LINE INPUT reads a text line (up to CR) from the serial port
'   - The sender transmits e.g., "1447\r\n" before the binary data
'   - VAL() converts the string to a number
'   - TOTAL is used on line 105 to know when to stop
'
' Line 50: RECORD = 1: B$ = "": NEED = 128
'   Initialize variables:
'   - RECORD: Current record number (1-based)
'   - B$: Accumulation buffer for incoming data
'   - NEED: Bytes to request from serial port
'
' Line 60: B$ = B$ + INPUT$(NEED, #1)
'   Read bytes from serial port and append to buffer.
'   Data may arrive in chunks smaller than 128 bytes.
'
' Line 70: IF LEN(B$) < 128 THEN 60
'   If we don't have a full record yet, keep reading.
'
' Line 80: LSET F$ = LEFT$(B$,128)
'   Copy first 128 bytes of the buffer into the field buffer.
'
' Line 90: PUT #2, RECORD
'   Write the record to disk:
'   - Writes F$ (128 bytes) to record number RECORD
'   - File position = (RECORD-1) * 128
'
' Line 100: B$ = MID$(B$,129)
'   Remove the 128 bytes we just wrote, keeping any leftover
'   bytes for the next record.
'
' Line 105: IF RECORD > TOTAL THEN 910
'   If we've received all expected records, jump to CLOSE/END.
'
' Line 110: RECORD = RECORD + 1
'   Advance to next record number.
'
' Line 120: GOTO 60
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
'
' Line 930: END
'   Program termination.
'
' ============================================================================
' WHY THE SENDER MUST PAD:
' ============================================================================
'
' The receiver writes fixed 128-byte records. If the file is not a
' multiple of 128 bytes, the last partial block would never complete
' and the receiver would hang.
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
' N$      - Output filename, entered by user at startup (string)
' T$      - Record count string received from sender (string)
' TOTAL   - Total number of records to receive (integer)
' RECORD  - Current record number being written (integer)
' NEED    - Bytes to request from serial port, always 128 (integer)
' B$      - Accumulation buffer, may hold more than 128 bytes (string)
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
'   Check that the sender is running and baud rates match.
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
' ============================================================================
