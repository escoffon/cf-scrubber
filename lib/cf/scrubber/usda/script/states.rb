require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/usda/script'

module Cf
  module Scrubber
    module USDA
      module Script
        # Framework class for iterating through the states with national forests or grasslands.

        class States < Cf::Scrubber::Script::Base
          # Initializer.
          #
          # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of states from the USFS web site, iterates
          # over each, yielding to the block provided.
          #
          # @yield [nfs, s, idx] passes the following arguments to the block:
          #  - *usfs* is the active instance of {Cf::Scrubber::USDA::USFS}.
          #  - *s* is the state name.
          #  - *idx* is the corresponding state identifier.

          def process(&blk)
            usfs = Cf::Scrubber::USDA::USFS.new(nil, {
                                                  :output => self.parser.options[:output],
                                                  :logger => self.parser.options[:logger],
                                                  :logger_level => self.parser.options[:logger_level]
                                                })
            s = usfs.states
            s.keys.sort.each do |sk|
              blk.call(usfs, sk, s[sk])
            end
          end
        end
      end
    end
  end
end
