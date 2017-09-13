require 'cf/scrubber/script/processor'

module Cf::Scrubber::Script
  # Scrub processor that dumps the contets of a scrub file.

  class Dumper < Cf::Scrubber::Script::Processor
    # Dump the contents of a scrub file.
    # Calls {#exec} with a specialized dumper block.

    def dump_file()
      self.exec do |loader, cd|
        self.output.print("---- #{cd[:name]}\n")
        if cd.has_key?(:signature)
          self.output.print("  -- Signature: #{cd[:signature]}\n")
        else
          self.output.print("  -- Signature: no signature defined\n")
        end
        self.output.print("  -- Organization: #{cd[:organization]} - #{cd[:region]} - #{cd[:area]}\n")
        self.output.print("  -- Details page: #{cd[:uri]}\n")
        self.output.print("  -- Accommodation types: #{cd[:types].join(', ')}\n")
        if cd.has_key?(:location)
          self.output.print("  -- Location: #{cd[:location][:lat]} #{cd[:location][:lon]}\n")
        else
          self.output.print("  -- Location: no location defined\n")
        end
        if cd.has_key?(:reservation_uri)
          self.output.print("  -- Reservations: #{cd[:reservation_uri]}\n")
        else
          self.output.print("  -- Reservations: no reservation_uri defined\n")
        end
        if cd[:additional_info].is_a?(Hash)
          self.output.print("  -- Additional info keys: #{cd[:additional_info].keys.join(', ')}\n")
        end
      end
    end
  end
end
