# Part 5: Binary Bootstrap Receiver

Since text transfer did not work, the next choice was to rewrite my `receive-text.bas` program to support binary transfer. Of course, looking back, I should have just started with a binary transfer program.

## FOR BINARY Mode

First, I tried using `FOR BINARY` mode:

```basic
30 OPEN "MSKERMIT.EXE" FOR BINARY AS #2
70 PUT #2,,A$
```

That resulted in a syntax error:

```basic
ERR=2 ERL=70
```

It turns out the version of GW-BASIC installed on the IBM PC is too old to support `FOR BINARY`.

## Random Access Mode

Since `FOR BINARY` didn't work, my next approach was to use random access files with `FIELD`, `LSET`, and `PUT`. Here is the final working program ([source](https://github.com/cfis/ibmpc/blob/master/src/receive-binary.bas)):

```basic
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
920 PRINT "Received"; RECORD - 1; "records"
930 END
```

## Understanding GW-BASIC Random Access Files

GW-BASIC's random access file mode was designed for database-style record storage, but it works for binary transfers. Unlike text mode (`FOR OUTPUT`), random access mode writes bytes exactly as provided without any translation.

Random access files work with fixed-size records. You define a record size, create a buffer, fill the buffer, and write it to disk. Here's how each piece works:

### Opening the File

```basic
OPEN "MSKERMIT.EXE" FOR RANDOM AS #2 LEN=128
```
This opens the file in random access mode with 128-byte records. The `LEN=128` parameter sets the record size. I chose 128 bytes to be conservative - this is old hardware and I wasn't sure the disk could keep up with the maximum size of 256.

### Creating the Buffer

```basic
FIELD #2, 128 AS F$
```

The `FIELD` statement creates a 128-byte buffer named `F$` that is linked to file #2. This buffer lives in a special area of memory that GW-BASIC uses for file I/O. When you write to the file, GW-BASIC writes the contents of this buffer.

### Filling the Buffer

```basic
LSET F$ = B$
```

`LSET` (Left-justify SET) copies the data into the buffer. In this version we read exactly COUNT bytes each time, so there is no carry-over buffer and no padding in the receive loop.

### Writing to Disk

```basic
50 RECORD = 1
...
80 PUT #2, RECORD
...
90 RECORD = RECORD + 1
```

The `PUT` statement writes the field buffer to the specified record number. The `RECORD` variable starts at 1 and increments after each write. This places each 128-byte chunk sequentially in the file: record 1 at bytes 0-127, record 2 at bytes 128-255, and so on.

If you forget to increment `RECORD`, every write overwrites the same location. The end result is a 128-byte file that only contains the last chunk of data.

!!! warning "Critical: Both Sides Must Agree on COUNT"
    The receiver blocks until it gets exactly COUNT bytes each time. If the sender does not pad the file to a multiple of COUNT bytes, the last partial block never arrives and the receiver hangs. Padding with zeros on the sender side is required.

!!! note "Padding Could Cause Problems"
    Adding extra bytes to the end of an executable could theoretically cause problems - some programs check their own size or have data appended after the code. In practice, MS-Kermit worked fine with the extra padding. If you transfer a file that doesn't work, this is something to check.

!!! tip "ERR=75 Fix"
    If you see `ERR=75` (path/file access error) on the `INPUT$` line, make sure `RS` is present in the serial open string:
    ```basic
    OPEN "COM1:4800,N,8,1,RS,CS0,DS0,CD0" AS #1
    ```

### send_binary.rb (Laptop)

The sender is a Ruby script ([source](https://github.com/cfis/ibmpc/blob/master/src/send_binary.rb)) that reads a binary file, pads it to a multiple of COUNT bytes, and sends it over the serial port. It displays progress every 5% so you know the transfer is working.

Usage:

```bash
ruby send_binary.rb COM3 MSKERMIT.EXE 4800
```

Arguments: serial port, filename, baud rate (default 4800).

```ruby
#!/usr/bin/env ruby
require 'serialport'

port_name = ARGV[0] || 'COM3'
file_path = ARGV[1]
baud_rate = (ARGV[2] || 4800).to_i

data = File.binread(file_path)
original_size = data.size

# Pad to multiple of 128 bytes
padding = (128 - (data.size % 128)) % 128
data += "\x00" * padding

puts "Sending #{file_path}"
puts "Original size: #{original_size} bytes"
puts "Padded size: #{data.size} bytes (#{data.size / 128} records)"
puts "Port: #{port_name} at #{baud_rate} baud"
puts

sp = SerialPort.new(port_name, baud_rate, 8, 1, SerialPort::NONE)
sp.flow_control = SerialPort::NONE

last_pct = -5
data.bytes.each_slice(128).with_index do |chunk, i|
  sp.write(chunk.pack('C*'))
  pct = ((i + 1) * 128 * 100) / data.size
  if pct >= last_pct + 5
    puts "#{pct}%"
    last_pct = pct
  end
end

sp.close
puts
puts "Done! Sent #{data.size} bytes"
puts "Press Ctrl+Break on the PC to stop the BASIC program"
```

The key line for sending data in 128-byte chunks:

```ruby
data.bytes.each_slice(128).with_index do |chunk, i|
  sp.write(chunk.pack('C*'))
```

This slices the padded data into 128-byte chunks and writes each chunk to the serial port. The `pack('C*')` call converts the array of byte values back into a binary string (`C` means unsigned byte, `*` means all elements). The receiver reads COUNT bytes at a time and writes each record, so both sides stay synchronized on the COUNT-byte boundary.

## Transfer Speed

At 4800 baud:

```
185 KB / 4800 bytes per second = ~5 minutes
```

## Success

[MS-Kermit](https://www.columbia.edu/kermit/mskermit.html) is a terminal emulator and file transfer program for DOS that was widely used in the 1980s and 1990s. It implements the Kermit protocol, which provides reliable file transfers with error checking and retransmission.

I downloaded MS-Kermit 3.15 from the [Columbia University Kermit archive](https://www.columbia.edu/kermit/archive.html). The archive offers several versions - I chose `MSK315M.EXE`, the medium-size executable (185 KB) that includes most features without requiring overlay files.

Using this binary transfer system, I successfully transferred `MSK315M.EXE` from my laptop to the IBM PC in approximately 7 minutes at 4800 baud.

Now I was ready to transfer over the old files from the IBM PC!

---

**Next:** [Part 6: Can't Send Files!](part6-mskermit.md)
