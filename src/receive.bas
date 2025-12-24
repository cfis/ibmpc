' ============================================================================
' RECEIVE.BAS - Simple Serial Text File Receiver for IBM PC
' ============================================================================
'
' DESCRIPTION:
'   A minimal GW-BASIC program for receiving text files over a serial
'   connection. Designed for bootstrapping - type this in manually to
'   establish initial file transfer capability on an IBM PC.
'
' AUTHOR:
'   Created during IBM PC file recovery project, December 2024
'
' HARDWARE REQUIREMENTS:
'   - IBM PC or compatible with serial port (COM1)
'   - RS-232 serial card with 8250 UART
'   - Null modem cable connection to sending computer
'
' USAGE:
'   1. Start GW-BASIC on the IBM PC
'   2. Type in this program (or LOAD if previously saved)
'   3. Modify line 30 to specify the output filename
'   4. RUN
'   5. Send the text file from the remote computer
'   6. Press Ctrl+Break when transfer is complete
'
' SERIAL PORT CONFIGURATION:
'   The OPEN statement on line 20 configures:
'   - COM1     : Serial port 1 (I/O address 0x3F8)
'   - 2400     : Baud rate (bits per second)
'   - N        : No parity
'   - 8        : 8 data bits
'   - 1        : 1 stop bit
'   - CS0      : Ignore Clear To Send signal
'   - DS0      : Ignore Data Set Ready signal
'   - CD0      : Ignore Carrier Detect signal
'
'   The CS0, DS0, CD0 parameters are essential for null modem cables
'   that may not have hardware handshaking lines connected.
'
' LIMITATIONS:
'   - TEXT MODE ONLY: Uses FOR OUTPUT which does CR/LF translation
'   - Binary files will be corrupted (use BINARY-RECEIVE.BAS instead)
'   - Ctrl-Z (0x1A) in data will be interpreted as EOF
'   - No progress indication during transfer
'   - Manual termination required
'
' ERROR HANDLING:
'   Line 900-910 catches errors, prints the error code and line number,
'   then resumes waiting for more data. Common errors:
'   - ERR=24: Device timeout (normal at end of transfer)
'   - ERR=57: Device I/O error
'   - ERR=68: Device unavailable
'
' TO MODIFY BAUD RATE:
'   Change "2400" in line 20 to: 1200, 2400, 4800, or 9600
'   Higher rates may be unreliable with interpreted BASIC
'
' TO CHANGE OUTPUT FILENAME:
'   Modify line 30: OPEN "YOURFILE.EXT" FOR OUTPUT AS #2
'
' ============================================================================

10 ON ERROR GOTO 900
20 OPEN "COM1:2400,N,8,1,CS0,DS0,CD0" AS #1
30 OPEN "C:\KERMIT.BAS" FOR OUTPUT AS #2
40 IF LOC(1)=0 THEN 40
50 N = LOC(1): IF N > 32 THEN N = 32
60 A$ = INPUT$(N, #1)
70 PRINT #2, A$;
80 GOTO 40
900 PRINT "ERR=";ERR;" ERL=";ERL
910 RESUME 40

' ============================================================================
' LINE-BY-LINE EXPLANATION:
' ============================================================================
'
' Line 10: ON ERROR GOTO 900
'   Sets up error handling. When any error occurs, execution jumps to line 900.
'   This prevents the program from crashing on timeouts or I/O errors.
'
' Line 20: OPEN "COM1:2400,N,8,1,CS0,DS0,CD0" AS #1
'   Opens the serial port for communication.
'   - File handle #1 is assigned to the serial port
'   - Parameters are: port:baud,parity,databits,stopbits,options
'   - CS0/DS0/CD0 disable hardware flow control checking
'
' Line 30: OPEN "C:\KERMIT.BAS" FOR OUTPUT AS #2
'   Opens the output file in text mode.
'   - File handle #2 is assigned to the output file
'   - FOR OUTPUT means write-only, text mode
'   - WARNING: Text mode corrupts binary data!
'
' Line 40: IF LOC(1)=0 THEN 40
'   Polling loop - wait for data in the serial buffer.
'   - LOC(1) returns the number of bytes waiting in the COM1 buffer
'   - If zero, keep looping (busy wait)
'   - This is a tight loop but acceptable for BASIC's speed
'
' Line 50: N = LOC(1): IF N > 32 THEN N = 32
'   Get the count of available bytes, but limit to 32.
'   - First, N gets the current buffer count
'   - Then, cap at 32 to prevent string overflow issues
'   - 32 is a safe chunk size for GW-BASIC string operations
'
' Line 60: A$ = INPUT$(N, #1)
'   Read N bytes from the serial port.
'   - INPUT$(count, filenum) reads exactly 'count' bytes
'   - Returns a string containing the raw bytes
'   - Blocks until all requested bytes are available
'
' Line 70: PRINT #2, A$;
'   Write the received bytes to the output file.
'   - PRINT # outputs to a file handle
'   - The semicolon (;) at the end suppresses the automatic newline
'   - Without semicolon, extra CR/LF would be added after each write
'
' Line 80: GOTO 40
'   Loop back to wait for more data.
'   - Creates an infinite loop
'   - Only exits via error or user pressing Ctrl+Break
'
' Line 900: PRINT "ERR=";ERR;" ERL=";ERL
'   Error handler - display the error information.
'   - ERR contains the error code number
'   - ERL contains the line number where error occurred
'   - This helps diagnose problems
'
' Line 910: RESUME 40
'   After printing the error, continue execution.
'   - RESUME continues from a specified line
'   - Goes back to waiting for more data
'   - Allows recovery from transient errors
'
' ============================================================================
' COMMON MODIFICATIONS:
' ============================================================================
'
' Higher baud rate (4800):
'   20 OPEN "COM1:4800,N,8,1,CS0,DS0,CD0" AS #1
'
' Different output file:
'   30 OPEN "MYFILE.TXT" FOR OUTPUT AS #2
'
' Larger read buffer (may improve speed):
'   50 N = LOC(1): IF N > 128 THEN N = 128
'
' Add basic progress indicator:
'   75 PRINT ".";
'
' ============================================================================
