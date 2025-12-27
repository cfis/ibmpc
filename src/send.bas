' ============================================================================
' SEND.BAS - Serial Loopback Test Program for IBM PC
' ============================================================================
'
' DESCRIPTION:
'   A GW-BASIC program to test serial port transmit functionality. Sends
'   "HELLO" and waits for an echo response. Used to diagnose whether the
'   IBM PC can successfully transmit data over the serial port.
'
' AUTHOR:
'   Created during IBM PC file recovery project, December 2024
'
' PURPOSE:
'   This program helps isolate transmit problems. If the IBM PC can receive
'   but not transmit, this program will print "No data" because the sent
'   "HELLO" never reaches the loopback or remote listener.
'
' USAGE:
'   1. Create a loopback by shorting pins 2 and 3 on the serial connector
'      OR run a listener script on the remote computer
'   2. Start GW-BASIC on the IBM PC
'   3. Type in or LOAD this program
'   4. RUN
'   5. If working: displays "Got back: HELLO"
'      If TX broken: displays "No data" after 2 second timeout
'
' SERIAL PORT CONFIGURATION:
'   - COM1 at 2400 baud, 8N1, no flow control
'   - RS: Suppress RTS signal
'   - CS0,DS0,CD0: Disable hardware handshaking
'
' ============================================================================

10 ON ERROR GOTO 900
20 OPEN "COM1:2400,N,8,1,RS,CS0,DS0,CD0" AS #1
30 IF LOC(1)>0 THEN J$=INPUT$(LOC(1),#1): GOTO 30
40 PRINT #1,"HELLO";
50 A$="": T!=TIMER
60 IF LEN(A$) >= 5 OR TIMER - T! >= 2 THEN 80
70 IF LOC(1)>0 THEN A$=A$+INPUT$(1,#1)
75 GOTO 60
80 IF LEN(A$) < 5 THEN PRINT "No data": GOTO 200
90 PRINT "Got back: ";A$
200 CLOSE #1
210 END
900 PRINT "ERR=";ERR;" ERL=";ERL: CLOSE: END

' ============================================================================
' LINE-BY-LINE EXPLANATION:
' ============================================================================
'
' Line 10: ON ERROR GOTO 900
'   Sets up error handling. Any error jumps to line 900.
'
' Line 20: OPEN "COM1:2400,N,8,1,RS,CS0,DS0,CD0" AS #1
'   Opens serial port with:
'   - 2400 baud, no parity, 8 data bits, 1 stop bit
'   - RS: Suppress RTS (Request To Send)
'   - CS0,DS0,CD0: Ignore CTS, DSR, and CD signals
'
' Line 30: IF LOC(1)>0 THEN J$=INPUT$(LOC(1),#1): GOTO 30
'   Flush any stale data from the receive buffer before sending.
'   LOC(1) returns bytes waiting in buffer. Loop until empty.
'
' Line 40: PRINT #1,"HELLO";
'   Send "HELLO" to the serial port. Semicolon prevents CR/LF.
'
' Line 50: A$="": T!=TIMER
'   Initialize receive buffer (A$) and start timeout timer (T!).
'   The ! suffix makes T a single-precision floating point variable.
'
' Line 60: IF LEN(A$) >= 5 OR TIMER - T! >= 2 THEN 80
'   Exit loop if we received 5 bytes OR 2 seconds have elapsed.
'
' Line 70: IF LOC(1)>0 THEN A$=A$+INPUT$(1,#1)
'   If data available, read one byte and append to buffer.
'
' Line 75: GOTO 60
'   Continue waiting for data.
'
' Line 80: IF LEN(A$) < 5 THEN PRINT "No data": GOTO 200
'   If we didn't get 5 bytes, transmit failed. Print message and exit.
'
' Line 90: PRINT "Got back: ";A$
'   Success! Display the received echo.
'
' Line 200-210: CLOSE #1 / END
'   Close the serial port and end program.
'
' Line 900: Error handler
'   Print error code and line number, close files, and exit.
'
' ============================================================================
' EXPECTED RESULTS:
' ============================================================================
'
' With working loopback or echo server:
'   Got back: HELLO
'
' With broken transmit (MC1488 or -12V issue):
'   No data
'
' With serial port error:
'   ERR=xx ERL=yy
'
' ============================================================================
