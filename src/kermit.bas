' ============================================================================
' KERMIT.BAS - Receive-Only Kermit Protocol for IBM PC Bootstrap
' ============================================================================
'
' ORIGINAL AUTHOR: Frank da Cruz, Columbia University, October 1986
' SOURCE: Columbia University Kermit Project Archive
'
' PURPOSE:
'   A minimal Kermit protocol implementation for bootstrapping a full
'   Kermit program onto an IBM PC. This program can receive files sent
'   using the Kermit protocol from another computer.
'
' HISTORICAL CONTEXT:
'   In the 1980s and early 1990s, this program solved the classic
'   "bootstrap problem" - how do you get file transfer software onto
'   a computer that can't receive files? The answer: type in this
'   program by hand, then use it to receive larger programs.
'
' USAGE:
'   1. Type this program into GW-BASIC (you can omit the comments)
'   2. SAVE "KERMIT.BAS"
'   3. RUN
'   4. On the remote computer, use Kermit to send files at 1200 bps
'
' IMPORTANT LIMITATIONS:
'   - RECEIVE ONLY: Cannot send files, only receive
'   - TEXT MODE I/O: Opens output files with FOR OUTPUT (line 3050)
'   - BINARY FILES WILL BE CORRUPTED due to text mode
'   - Hard-coded to 1200 baud (line 1020)
'   - No 8th-bit quoting support
'
' WHY IT DOESN'T WORK FOR BINARY:
'   Line 3050: OPEN MID$(PKTDAT$,1,L) FOR OUTPUT AS #2
'   Line 4040: PRINT #2, MID$(PKTDAT$,1,P);
'
'   FOR OUTPUT and PRINT # use text mode, which:
'   - Translates CR/LF sequences
'   - Treats Ctrl-Z (0x1A) as end-of-file
'   - May corrupt certain byte values
'
' PROTOCOL OVERVIEW:
'   Kermit protocol uses packets with:
'   - MARK: Start of packet (Ctrl-A, ASCII 1)
'   - LEN: Packet length
'   - SEQ: Sequence number (0-63)
'   - TYPE: Packet type (S=Init, F=File, D=Data, Z=EOF, B=Break)
'   - DATA: Packet contents (control characters quoted)
'   - CHECK: Checksum
'
'   All data is encoded as printable ASCII (7-bit safe).
'   Control characters are "quoted" with # prefix and XOR 64.
'
' ============================================================================

001 ' KERMIT.BAS - Receive-only Kermit Protocol implementation for
002 ' bootstrapping a real Kermit program onto the PC.  Requires MS BASIC.
003 ' Start Basic, type in this program (you can leave out the comments),
004 ' SAVE, and then RUN.  Have the Kermit program on the other end of the
005 ' COM port connection send the desired file at a speed of 1200bps
006 ' with no flow control.

010 ' Author: Frank da Cruz, October 1986.

100  RESET : RESET : RESET
110  ON ERROR GOTO 9000
120  DEFINT A-Z

1010 N = 0 : SNDBUF$ = CHR$(1)+"# N3"+CHR$(13)
1020 OPEN "COM1:1200,N,8,,CS,DS" AS #1

2000 ' Get Send Initialization packet, exchange parameters.
2010 PRINT "Waiting..."
2020 GOSUB 5000
2030 IF TYP$ <> "S" THEN D$ = TYP$+" Packet in S State" : GOTO 9500
2040 IF LEN(PKTDAT$) > 4 THEN EOL=ASC(MID$(PKTDAT$,5,1))-32 ELSE EOL=13
2050 IF LEN(PKTDAT$) > 5 THEN CTL=ASC(MID$(PKTDAT$,6,1)) ELSE CTL=ASC("#")
2070 D$ = "H* @-#N1" : GOSUB 8020

3000 ' Get a File Header packet.  If a B packet comes, we're all done.
3010 GOSUB 5000
3020 IF TYP$ = "B" THEN GOSUB 8000 : GOTO 9900
3030 IF TYP$ <> "F" THEN D$ = TYP$+" Packet in F State" : GOTO 9500
3040 PRINT "Receiving "; MID$(PKTDAT$,1,L);
3050 OPEN MID$(PKTDAT$,1,L) FOR OUTPUT AS #2
3060 GOSUB 8000

4000 ' Get Data packets.  If a Z packet comes, the file is complete.
4010 GOSUB 5000
4020 IF TYP$ = "Z" THEN CLOSE #2 : GOSUB 8000 : PRINT "(OK)" : GOTO 3000
4030 IF TYP$ <> "D" THEN D$ = TYP$+" Packet in D State" : GOTO 9500
4040 PRINT #2, MID$(PKTDAT$,1,P);
4060 GOSUB 8000
4070 GOTO 4000

5000 ' Try to get a valid packet with the desired sequence number.
5010 GOSUB 7000
5020 FOR TRY = 1 TO 5
5030   IF SEQ = N AND TYP$ <> "Q" THEN RETURN
5040   PRINT #1, SNDBUF$;
5050   PRINT "%";
5060   GOSUB 7000
5070 NEXT TRY
5080 TYP$ = "T" : RETURN

6000 ' Send a packet with data D$ of length L, type TYP$, sequence #N.
6010 SNDBUF$ = CHR$(1)+CHR$(L+35)+CHR$(N+32)+TYP$+D$+" "+CHR$(EOL)
6020 CHKSUM = 0
6030 FOR I = 2 TO L+4
6040   CHKSUM = CHKSUM + ASC(MID$(SNDBUF$,I,1))
6050 NEXT I
6060 CHKSUM = (CHKSUM + ((CHKSUM AND 192) \ 64)) AND 63
6070 MID$(SNDBUF$,L+5) = CHR$(CHKSUM + 32)
6080 PRINT #1, SNDBUF$;
6100 RETURN

7000 ' Routine to Read and Decode a Packet.
7010 LINE INPUT #1, RCVBUF$
7020 I = INSTR(RCVBUF$,CHR$(1))
7030 IF I = 0 THEN TYP$ = "Q" : RETURN

7100 CHK   = ASC(MID$(RCVBUF$,I+1,1)) : L   = CHK - 35
7110 T     = ASC(MID$(RCVBUF$,I+2,1)) : SEQ = T - 32 : CHK = CHK + T
7120 TYP$  =     MID$(RCVBUF$,I+3,1)  : CHK = CHK + ASC(TYP$)

7130 P = 0 : FLAG = 0 : PKTDAT$ = STRING$(100,32)
7200 FOR J = I+4 TO I+3+L
7210   T = ASC(MID$(RCVBUF$,J,1))
7220   CHK = CHK + T
7240   IF TYP$ = "S" THEN 7300
7250     IF FLAG = 0 AND T = CTL THEN FLAG = 1 : GOTO 7400
7260     T7 = T AND 127
7270     IF FLAG THEN FLAG = 0 : IF T7 > 62 AND T7 < 96 THEN T = T XOR 64
7300   P = P + 1
7310   MID$(PKTDAT$,P,1) = CHR$(T)
7400 NEXT J
7420 CHK = (CHK + ((CHK AND 192) \ 64)) AND 63
7430 CHKSUM = ASC(MID$(RCVBUF$,J,1)) - 32
7450 IF CHKSUM <> CHK THEN TYP$ = "Q"
7460 RETURN

8000 ' Routine to send an ACK and increment the packet number...
8010 D$ = ""
8020 TYP$ = "Y" : L = LEN(D$) : GOSUB 6000
8030 N = (N + 1) AND 63
8040 IF (N AND 3) = 0 THEN PRINT ".";
8050 RETURN

9000 ' Error handler, nothing fancy...
9010 D$ = "Error " + STR$(ERR) + " at Line" + STR$(ERL)
9020 PRINT D$

9500 ' Error packet sender...
9520 L = LEN(D$) : TYP$ = "E" : GOSUB 6000

9900 ' Normal exit point
9910 CLOSE
9920 PRINT CHR$(7);"(Done)"
9999 END

' ============================================================================
' SUBROUTINE REFERENCE:
' ============================================================================
'
' GOSUB 5000 - Get Packet
'   Attempts to receive a valid packet with the expected sequence number.
'   Retries up to 5 times if needed.
'   Sets TYP$ to packet type, PKTDAT$ to decoded data.
'
' GOSUB 6000 - Send Packet
'   Sends a packet with the specified type and data.
'   Calculates and appends checksum.
'
' GOSUB 7000 - Read/Decode Packet
'   Reads one packet from serial, decodes control character quoting.
'   Validates checksum.
'
' GOSUB 8000 - Send ACK
'   Sends acknowledgment packet, increments sequence number.
'   Prints progress dots.
'
' ============================================================================
' PACKET TYPE CODES:
' ============================================================================
'
' S - Send Initiate (negotiation parameters)
' F - File Header (contains filename)
' D - Data (file contents)
' Z - End of File
' B - Break (end of transmission)
' Y - Acknowledgment (ACK)
' N - Negative Acknowledgment (NAK)
' E - Error
' Q - Invalid/corrupt packet (internal use)
' T - Timeout (internal use)
'
' ============================================================================
' CHARACTER ENCODING:
' ============================================================================
'
' Control characters (0-31, 127) cannot be sent directly over serial
' connections. Kermit "quotes" them:
'
' Original: 0x05 (Ctrl-E)
' Encoded:  # E  (# is the quote character, E is 0x05 XOR 0x40 = 0x45)
'
' The decode logic at lines 7250-7270 reverses this:
'   If we see #, set FLAG
'   Next character: XOR with 64 to recover original
'
' ============================================================================
' WHY 1200 BAUD:
' ============================================================================
'
' Line 1020 hard-codes 1200 baud. This was a reliable speed for:
' - Modems of the era
' - Serial connections without flow control
' - Interpreted BASIC keeping up with incoming data
'
' Higher speeds may work but weren't guaranteed in 1986.
'
' ============================================================================
