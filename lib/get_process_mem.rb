require 'pathname'
require 'bigdecimal'


# Cribbed from Unicorn Worker Killer, thanks!
class GetProcessMem
  if RUBY_VERSION >= '1.9'
    KB_TO_BYTE = 1024          # 2**10   = 1024
    MB_TO_BYTE = 1_048_576     # 1024**2 = 1_048_576
    GB_TO_BYTE = 1_073_741_824 # 1024**3 = 1_073_741_824
  else
    KB_TO_BYTE = '1024'          # 2**10   = 1024
    MB_TO_BYTE = '1_048_576'     # 1024**2 = 1_048_576
    GB_TO_BYTE = '1_073_741_824' # 1024**3 = 1_073_741_824
  end

  CONVERSION = { "kb" => KB_TO_BYTE, "mb" => MB_TO_BYTE, "gb" => GB_TO_BYTE }
  ROUND_UP   = BigDecimal.new("0.5")
  attr_reader :pid

  def initialize(pid = Process.pid)
    @process_file = Pathname.new "/proc/#{pid}/smaps"
    @pid          = pid
    @linux        = @process_file.exist?
  end

  def linux?
    @linux
  end

  def bytes
    memory =   linux_memory if linux?
    memory ||= ps_memory
  end

  def kb(b = bytes)
    (b/BigDecimal.new(KB_TO_BYTE)).to_f
  end

  def mb(b = bytes)
    (b/BigDecimal.new(MB_TO_BYTE)).to_f
  end

  def gb(b = bytes)
    (b/BigDecimal.new(GB_TO_BYTE)).to_f
  end

  def inspect
    b = bytes
    "#<#{self.class}:0x%08x @mb=#{ mb b } @gb=#{ gb b } @kb=#{ kb b } @bytes=#{b}>" % (object_id * 2)
  end

  def mem_type
    @mem_type
  end

  def mem_type=(mem_type)
    @mem_type = mem_type.downcase
  end

  # linux stores memory info in a file "/proc/#{pid}/smaps"
  # If it's available it uses less resources than shelling out to ps
  def linux_memory(file = @process_file)
    lines = file.each_line.select {|line| line.match /^Rss/ }
    return if lines.empty?
    lines.reduce(0) do |sum, line|
      memory_data = line.match(/(\d*\.{0,1}\d+)\s+(\w\w)/)

      if memory_data
        value = BigDecimal.new(memory_data[1]) + ROUND_UP
        unit  = memory_data[2].downcase
        sum  += CONVERSION[unit].to_i * value
      end

      sum
    end
  rescue Errno::EACCES
    0
  end

  private

  # Pull memory from `ps` command, takes more resources and can freeze
  # in low memory situations
  def ps_memory
    KB_TO_BYTE.to_i * BigDecimal.new(`ps -o rss= -p #{pid}`)
  end
end
