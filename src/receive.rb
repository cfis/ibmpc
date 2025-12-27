#!/usr/bin/env ruby
# ============================================================================
# receive.rb - Serial Loopback Listener for IBM PC Testing
# ============================================================================
#
# DESCRIPTION:
#   A Ruby script that listens on a serial port and displays received data.
#   Used as the companion to send.bas for testing serial communication from
#   the IBM PC.
#
# AUTHOR:
#   Created during IBM PC file recovery project, December 2024
#
# PURPOSE:
#   This script runs on the modern laptop to receive data sent from the IBM PC.
#   When send.bas transmits "HELLO", this script captures and displays it.
#   If nothing is received, the IBM PC has a transmit problem (likely the
#   MC1488 line driver or missing -12V power).
#
# USAGE:
#   1. Connect serial cable between IBM PC and laptop
#   2. Run this script on the laptop:
#      ruby receive.rb
#   3. Run send.bas on the IBM PC
#   4. This script displays whatever was received
#
# REQUIREMENTS:
#   - Ruby (https://www.ruby-lang.org/)
#   - serialport gem: gem install serialport
#
# CONFIGURATION:
#   - Edit COM3 to match your serial port (e.g., COM1, /dev/ttyUSB0)
#   - Baud rate must match send.bas (2400 baud)
#   - 8N1: 8 data bits, no parity, 1 stop bit
#   - No flow control
#
# EXPECTED OUTPUT:
#   If IBM PC transmit works:
#     Listening...
#     Received: "HELLO"
#     Hex: 48 45 4c 4c 4f
#
#   If IBM PC transmit is broken:
#     Listening...
#     (script hangs waiting for data)
#
# ============================================================================

require 'serialport'

# Open serial port: COM3 at 2400 baud, 8 data bits, 1 stop bit, no parity
p = SerialPort.new('COM3', 2400, 8, 1, SerialPort::NONE)

puts "Listening..."

# Read 5 bytes (matches "HELLO" sent by send.bas)
# This call blocks until 5 bytes are received
data = p.read(5)

# Display received data as string
puts "Received: #{data.inspect}"

# Display received data as hex bytes for debugging
# Useful for seeing exactly what bytes arrived
puts "Hex: #{data.bytes.map { |b| '%02x' % b }.join(' ')}"

p.close
