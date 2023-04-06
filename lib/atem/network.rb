require "socket"

class String
  def to_hex
    bytes.map { |a| "0x" + a.to_s(16) }.join(" ")
  end
end

module ATEM
  class Network
    module Packet
      NOP = 0x00
      ACK_REQ = 0x01
      HELLO = 0x02
      RESEND = 0x04
      UNDEFINED = 0x08
      ACK = 0x10
    end

    class Retry < StandardError
    end

    @@SIZE_OF_HEADER = 0x0c

    @package_id = 0

    def initialize ip, port, uid = 0x1337
      @socket = UDPSocket.new
      @socket.bind "0.0.0.0", 9100

      @ip = ip
      @port = port
      @uid = uid
      @package_id = 0
    end

    def disconnect
      @socket.close
    end

    def << data
      bitmask, ack_id, payload = data

      bitmask = bitmask << 11
      bitmask |= (payload.length + @@SIZE_OF_HEADER)

      package_id = 0
      if (bitmask & (Packet::HELLO | Packet::ACK)) != 0 && @ready && payload.length != 0
        # p "SENDING PACKAGE"
        @package_id += 1
        package_id = @package_id
      end

      packet = [bitmask, @uid, ack_id, 0, package_id].pack("S>S>S>L>S>")
      packet += payload

      # print "TX(#{packet.length}, #{@package_id}, #{ack_id})"; p packet.to_hex
      @socket.send packet, 0, @ip, @port
    end

    def send! cmd, payload
      raise "Invalid command" if cmd.bytes.length != 4

      size = cmd.length + payload.length + 4
      datagram = [size, 0, 0].pack("S>CC") + cmd + payload

      self << [Packet::ACK_REQ, @ack_id, datagram]
      receive
    end

    def hello
      self << [0x02, 0x0, [0x01000000, 0x00].pack("L>L>")]
      receive_until_ready
    end

    def receive
      packets = []
      # next_packet = nil

      begin
        begin
          data, _ = @socket.recvfrom(2048)
        rescue
          p "ERR"
          return []
        end

        # print "RX(#{data.length}) "; p data.to_hex

        bitmask, _size, uid, ack_id, _, package_id = data.unpack("CXS>S>S>LS>")
        @uid = uid

        bitmask = bitmask >> 3
        # size &= 0x07FF

        # print "RX HEADER: "
        # p [bitmask, size, uid, ack_id, package_id]

        @ack_id = package_id

        packet = [ack_id, bitmask, package_id, data[@@SIZE_OF_HEADER..]]

        packets += handle(packet)

        #				raise Retry

        #			rescue Retry
        #				retry if next_packet and next_packet.length >= @@SIZE_OF_HEADER
      end

      packets
    end

    def receive_until_ready
      packets = []
      until @ready
        packets += receive
      end
      packets
    end

    private

    def handle packet
      bitmask = packet[1]

      if (bitmask & Packet::HELLO) == Packet::HELLO

        @ready = false
        self << [Packet::ACK, 0x0, ""]

      elsif ((bitmask & Packet::ACK_REQ) == Packet::ACK_REQ) && (@ready || (!@ready && packet[3].length == 0))

        self << [Packet::ACK, packet[2], ""]
        @ready = true

      end

      data = packet[3]
      packets = []

      while !data.nil? && data.length > 0

        packet, data = payload(data)
        packets << packet

      end

      packets
    end

    def payload packet
      size = packet.unpack1("S>")
      pack = packet[4..size - 1]
      packet = packet[size..]

      command = pack.slice!(0, 4)

      [[command, pack], packet]
    end
  end
end
