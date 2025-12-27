# Part 7: Debugging

Although I could send files from my laptop to the IBM, I could not send files from the IBM to my laptop, which was the whole point of this exercise.

## Kermit Configuration

I first tried to change various kermit settings to no avail:

```
set speed 4800
set parity even
set flow none
set handshake none
set file type binary
set block 1
set window 1
set send packet-length 40
set receive packet-length 40
set block-check 1
```

Even with these settings, Kermit 95 Beta.7 on Windows and C-Kermit 9.x on Fedora timed out waiting for ACKs from MS-Kermit 3.15.

The `C-Kermit` output on the laptop was:

```
Kermit 95 3.0.0 Beta.7
Communication Device: COM3
Communication Speed: 4800
Parity: none

Packet Type: T
Packet Count: 7
Error Count: 7
Last Error: Timeout 14 sec
```
The laptop was receiving nothing from the PC.

## Terminal Mode Test

Next I put both kermit programs into connect mode:

```
PC> connect
Laptop> connect
```

When I typed characters on the laptop they correctly showed up on the IBM PC. But when I typed in characters on the IBM, nothing showed up on the laptop.

## Other Things Ruled Out

I then went through a number of possible other problems, eliminating them one-by-one:

| Item | Status                             |
|------|------------------------------------|
| Wrong COM port / tty | Ruled out (/dev/ttyUSB0 confirmed) |
| Baud rate mismatch | The same                           |
| Parity mismatch | Tried none and even                |
| Flow control blocking | Disabled                           |
| Carrier detect blocking | Disabled                           |
| Terminal type mismatch | Irrelevant for raw serial          |
| Windows driver issues | Same behavior on Linux             |
| Modern Kermit incompatibility | Same with classic settings         |
| User permissions | Ran as root                        |
| Receiver not listening | Verified                           |
| Noise / garbage | None seen                          |
| Cable continuity | Previously tested                  |
| IBM RX works | Yes                                |


## Raw Serial Test

Next I wrote a simple `send.bas` file ([source](https://github.com/cfis/ibmpc/blob/master/src/send.bas)) on the IBM to transmit data:

```basic
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
```

| Line | Code | Purpose |
|-----|------|---------|
| 10 | `ON ERROR GOTO 900` | Set up error handler |
| 20 | `OPEN "COM1:2400,N,8,1,RS,CS0,DS0,CD0"` | Open serial port. `RS` suppresses RTS; `CS0,DS0,CD0` disable handshaking |
| 30 | `IF LOC(1)>0 THEN J$=INPUT$...` | Flush any stale data in the receive buffer |
| 40 | `PRINT #1,"HELLO";` | Send "HELLO" (semicolon prevents CR/LF) |
| 50 | `A$="": T!=TIMER` | Initialize receive buffer and start timer |
| 60-75 | Loop | Wait up to 2 seconds for 5 bytes. `LOC(1)` returns bytes available |
| 80 | `IF LEN(A$) < 5` | Check if enough data arrived |
| 90 | `PRINT "Got back: ";A$` | Display received data |
| 900 | Error handler |

On the laptop, I then ran a Ruby script ([source](https://github.com/cfis/ibmpc/blob/master/src/receive.rb)) to listen for incoming data:

```ruby
require 'serialport'
p = SerialPort.new('COM3', 2400, 8, 1, SerialPort::NONE)
puts "Listening..."
data = p.read(5)
puts "Received: #{data.inspect}"
puts "Hex: #{data.bytes.map { |b| '%02x' % b }.join(' ')}"
p.close
```

| Line | Code | Purpose |
|------|------|---------|
| 1 | `require 'serialport'` | Load the serialport gem |
| 2 | `SerialPort.new('COM3', 2400, 8, 1, SerialPort::NONE)` | Open COM3 at 2400 baud, 8N1, no flow control |
| 3 | `puts "Listening..."` | Indicate the script is waiting |
| 4 | `data = p.read(5)` | Block until 5 bytes are received |
| 5 | `puts "Received: #{data.inspect}"` | Display received data as Ruby string |
| 6 | `data.bytes.map { |b| '%02x' % b }` | Convert each byte to 2-digit hex |
| 7 | `p.close` | Close the serial port |

As expected, the Ruby script blocked indefinitely waiting for data that never arrived.

## The USB Serial Adapter

Next, I unplugged the null modem cable from the USB serial adapter. I created a "loopback" by shorting pins 2 and 3 on the female DB-9 mating plate. This would verify the USB adapter was working properly by having it echo back anything sent to it.

!!! warning "Pin Placement"
    On a female mating plate, pin #1 is on the top right! For more information refer to the [RS-232](part2-serial-connection.md#rs-232-) section.

I typed some characters on the laptop and they echoed back correctly. So the USB serial adapter was working fine - the problem was on the IBM PC side.

## The Null Modem Cable

Next, I unplugged the null modem cable from the IBM PC. This exposed the DB-25 male adapter. Since I didn't have a multimeter, I again used my trusty paperclip to create a "loopback" by shorting pins 2 and 3. This is a whole lot trickier on a male adapter, and required some duct tape to keep everything in place.

I then ran the `send.bas` again. And again no data. This left the serial card as a suspect.

## Serial Card Testing

In [Part 1](part1-install-serial-card.md), I ran various tests to verify that the IBM PC correctly recognized the serial card.

Next, I tried sending data using the DEBUG program which works at a lower level than GW-BASIC:

```doscon
DEBUG
o 3fb 83    ; DLAB on
o 3f8 30    ; Divisor low (2400 baud)
o 3f9 00    ; Divisor high
o 3fb 03    ; DLAB off, 8N1
o 3fc 03    ; DTR + RTS
o 3f8 41    ; Send 'A'
i 3fd       ; Check Line Status Register
i 3f8       ; Read data
```

| Command | Register | Purpose |
|---------|----------|---------|
| `o 3fb 83` | LCR (Line Control) | Set DLAB=1 to access baud rate divisor |
| `o 3f8 30` | DLL (Divisor Low) | Low byte of divisor (0x30 = 48 for 2400 baud) |
| `o 3f9 00` | DLH (Divisor High) | High byte of divisor |
| `o 3fb 03` | LCR (Line Control) | DLAB=0, 8 data bits, 1 stop bit, no parity |
| `o 3fc 03` | MCR (Modem Control) | Assert DTR and RTS |
| `o 3f8 41` | THR (Transmit Hold) | Send 'A' (0x41) |
| `i 3fd` | LSR (Line Status) | Check transmitter/receiver status |
| `i 3f8` | RBR (Receive Buffer) | Read any received data |

The result was:

```
LSR: 60, Data: 00
```

Possible values for the 8250 Line Status Register (0x3FD) are:

| Value | Meaning                                    |
|-------|--------------------------------------------|
| 60    | Transmitter empty, no data                 |
| 61    | Data ready (may be noise on floating RX)   |
| 7B    | Data with errors (overrun, framing, break) |

So transmitter was empty and no data was received. Same problem.

## UART Internal Loopback Test

The 8250 UART has a diagnostic loopback mode (MCR bit 4) that internally connects the transmit logic directly to the receive logic, bypassing the external line drivers and physical pins:

```
Normal mode:
  CPU → UART TX → 1488 line driver → DB-25 pin
  CPU ← UART RX ← 1489 line receiver ← DB-25 pin

Loopback mode:
  CPU → UART TX ──┐
                  │ (internal connection)
  CPU ← UART RX ←─┘
```

The idea is to test if the UART chip was working.

```doscon
DEBUG
o 3fc 1b    ; MCR: OUT2 + RTS + DTR + loopback
o 3f8 55    ; send 0x55
i 3f8       ; read it back
```

| Command    | Register             | Purpose                                            |
|------------|----------------------|----------------------------------------------------|
| `o 3fc 1b` | MCR (Modem Control)  | Set bits: OUT2 + RTS + DTR + loopback mode (bit 4) |
| `o 3f8 55` | THR (Transmit Hold)  | Send byte 0x55 (alternating bits: 01010101)        |
| `i 3f8`    | RBR (Receive Buffer) | Read the byte back through internal loopback       |

The result was `55`, meaning the UART TX/RX logic works and the byte written was read back.

So the UART chip is working, but for some reason the TX signal does not reach the TX pin on the DB-25 plate.

---

**Next:** [Part 8: Next Steps](part8-next-steps.md)
