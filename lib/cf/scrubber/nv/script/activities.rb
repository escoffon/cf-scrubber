require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/nv/script'

module Cf
  module Scrubber
    module NV
      module Script
        # Framework class for listing activity identifiers.

        class Activities < Cf::Scrubber::Script::Base
          # Initializer.
          #
          # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of activities from the NV state park system's
          # web site, and yields to the block.
          #
          # @yield [sp, act] passes the following arguments to the block:
          #  - *sp* is the active instance of {Cf::Scrubber::NV::StateParks}.
          #  - *act* is a hash containing activity information: *:activity_id* and *:name*.

          def process(&blk)
            sp = Cf::Scrubber::NV::StateParks.new(nil, {
                                                    :output => self.parser.options[:output],
                                                    :logger => self.parser.options[:logger],
                                                    :logger_level => self.parser.options[:logger_level]
                                                  })
            sp.get_activity_list.each do |act|
              blk.call(sp, act)
            end
          end
        end
      end
    end
  end
end
