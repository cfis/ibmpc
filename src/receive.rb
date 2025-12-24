require 'serialport'
p = SerialPort.new('COM3', 2400, 8, 1, SerialPort::NONE)
puts "Listening..."
data = p.read(3)
puts "Received: #{data.inspect}"
puts "Hex: #{data.bytes.map { |b| '%02x' % b }.join(' ')}"
p.close