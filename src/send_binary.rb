#!/usr/bin/env ruby
# ============================================================================
# send_binary.rb - Binary File Sender for IBM PC File Transfer
# ============================================================================
#
# DESCRIPTION:
#   Sends binary files over a serial connection to an IBM PC running
#   binary-receive.bas. Automatically pads files to 128-byte boundaries.
#
# AUTHOR:
#   Created during IBM PC file recovery project, December 2024
#
# REQUIREMENTS:
#   Ruby with serialport gem:
#     gem install serialport
#
# USAGE:
#   ruby send_binary.rb PORT FILENAME [BAUD]
#
#   Arguments:
#     PORT     - Serial port (COM3 on Windows, /dev/ttyUSB0 on Linux)
#     FILENAME - File to send
#     BAUD     - Baud rate (default: 4800)
#
# EXAMPLES:
#   ruby send_binary.rb COM3 MSKERMIT.EXE 4800
#   ruby send_binary.rb /dev/ttyUSB0 PROGRAM.EXE 2400
#
# PROTOCOL:
#   1. File is padded to multiple of 128 bytes (with null bytes)
#   2. Raw bytes are sent over serial
#   3. Receiver (binary-receive.bas) writes 128-byte records
#   4. User presses Ctrl+Break on PC when sender reports "Done"
#
# WHY 128 BYTES:
#   GW-BASIC random access files use fixed-length records. The FIELD
#   statement creates a buffer that's always written completely.
#   Padding ensures every record is full and no garbage is written.
#
# ============================================================================

require 'serialport'

# Parse command line arguments
port_name = ARGV[0] || 'COM3'
file_path = ARGV[1]
baud_rate = (ARGV[2] || 4800).to_i

# Validate arguments
if file_path.nil? || !File.exist?(file_path)
  puts "Usage: ruby send_binary.rb PORT FILENAME [BAUD]"
  puts ""
  puts "Arguments:"
  puts "  PORT     - Serial port (e.g., COM3 or /dev/ttyUSB0)"
  puts "  FILENAME - File to send"
  puts "  BAUD     - Baud rate (default: 4800)"
  puts ""
  puts "Example:"
  puts "  ruby send_binary.rb COM3 MSKERMIT.EXE 4800"
  exit 1
end

# Read the file
data = File.binread(file_path)
original_size = data.size

# Pad to multiple of 128 bytes
# This is CRITICAL - the receiver writes 128-byte records
# Without padding, the last record would have garbage
padding_needed = (128 - (data.size % 128)) % 128
data += "\x00" * padding_needed

# Calculate statistics
record_count = data.size / 128
estimated_time = data.size.to_f / (baud_rate / 10) # 10 bits per byte with start/stop

# Display transfer information
puts "=" * 60
puts "Binary File Sender"
puts "=" * 60
puts "File:          #{file_path}"
puts "Original size: #{original_size} bytes"
puts "Padded size:   #{data.size} bytes (#{record_count} records)"
puts "Padding added: #{padding_needed} bytes"
puts "Port:          #{port_name}"
puts "Baud rate:     #{baud_rate}"
puts "Est. time:     #{(estimated_time / 60).round(1)} minutes"
puts "=" * 60
puts ""

# Open serial port
# Parameters: port, baud, data_bits, stop_bits, parity
begin
  sp = SerialPort.new(port_name, baud_rate, 8, 1, SerialPort::NONE)
  sp.flow_control = SerialPort::NONE
rescue => e
  puts "ERROR: Could not open serial port #{port_name}"
  puts e.message
  exit 1
end

# Send data with progress display
puts "Sending..."
puts ""

last_pct = -5
bytes_sent = 0

data.bytes.each_slice(128) do |chunk|
  # Send one 128-byte record
  sp.write(chunk.pack('C*'))
  bytes_sent += chunk.size

  # Calculate and display progress
  pct = (bytes_sent * 100) / data.size

  # Show progress every 5%
  if pct % 5 == 0 && pct > last_pct
    puts "#{pct}%"
    last_pct = pct
  end
end

# Close serial port
sp.close

# Final message
puts ""
puts "=" * 60
puts "Done! Sent #{data.size} bytes (#{record_count} records)"
puts "Press Ctrl+Break on the PC to stop the BASIC program"
puts "=" * 60

# ============================================================================
# TECHNICAL NOTES:
# ============================================================================
#
# Serial Port Configuration:
#   - 8 data bits, 1 stop bit, no parity (8N1)
#   - No flow control (matches IBM PC BASIC settings)
#   - Baud rate must match receiver exactly
#
# Why No Protocol:
#   This is a raw byte transfer with no error detection or correction.
#   The IBM PC's UART (8250) has only a 1-byte buffer, making complex
#   protocols difficult to implement in interpreted BASIC. For short
#   transfers over a reliable cable, raw transfer is sufficient.
#
#   For production use, consider:
#   - Lower baud rates for better reliability
#   - Transferring multiple times and comparing
#   - Using Kermit or XMODEM once MS-Kermit is bootstrapped
#
# Padding Explained:
#   GW-BASIC's FIELD/LSET/PUT writes exactly 128 bytes per record.
#   If we don't pad, the receiver's last LSET would pad with spaces
#   (ASCII 32), corrupting the binary. Padding with nulls (0x00) is
#   safe because:
#   1. Most executables ignore trailing nulls
#   2. The EXE header specifies the actual code size
#   3. Null bytes have no effect when appended to binary files
#
# ============================================================================
