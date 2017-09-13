require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/usda/script'
require 'cf/scrubber/usda/usfs_helper'

module Cf
  module Scrubber
    module USDA
      module Script
        # Framework class for iterating through forests or grasslands for various states.

        class Forests < Cf::Scrubber::Script::Base
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - <tt>-s STATES</tt> (<tt>--states=STATES</tt>) to set the list of states for which to list
          #   campgrounds. This is a comma-separated list of state codes, like +CA,OR,NV+.
          #   By default, all states are processed.
          # - <tt>-c</tt> (<tt>--convert-names</tt>) If present, the list of forest names is converted to
          #   a list that may contain "umbrella" forests. For example, Colorado places 
          #   <tt>Arapaho National Forest</tt>, <tt>Roosevelt National Forest</tt>, and
          #   <tt>Pawnee National Grassland</tt> under the
          #   <tt>Arapaho & Roosevelt National Forests Pawnee NG</tt> rec area.
          #   If this option is not provided, these two forests and one grassland are listed separately, but
          #   when it is provided <tt>Arapaho & Roosevelt National Forests Pawnee NG</tt> is listed instead.
          #   See the documentation for {Cf::Scrubber::USDA::USFSHelper} and
          #   {Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors}.

          class Parser < Cf::Scrubber::Script::Parser
            # Initializer.

            def initialize()
              rv = super()
              opts = self.parser

              opts.on_head("-c", "--convert-names", "If present, convert the list of names to incude aggregate rec areas") do |n|
                self.options[:convert] = true
              end

              opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of states for which to list forests. Shows all states if not given. You may use two-character state codes.") do |sl|
                self.options[:states] = sl.split(',').map do |s|
                  t = s.strip
                  (t.length == 2) ? t.upcase : t
                end
              end

              self.options.merge!({ states: nil, convert: false })

              rv
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::USDA::Script::States::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Processor.
          # This is the framework method; it fetches the list of states from the USFS web site, iterates
          # over each, yielding to the block provided.
          #
          # @yield [nfs, s, f, idx] passes the following arguments to the block:
          #  - *usfs* is the active instance of {Cf::Scrubber::USDA::USFS}.
          #  - *s* is the state name.
          #  - *f* is the forest name.
          #  - *desc* is the corresponding forest descriptor.

          def process(&blk)
            usfs = Cf::Scrubber::USDA::USFS.new(nil, {
                                                  :output => self.parser.options[:output],
                                                  :logger => self.parser.options[:logger],
                                                  :logger_level => self.parser.options[:logger_level]
                                                })

            self.parser.options[:states] = usfs.states.keys if self.parser.options[:states].nil?
            self.parser.options[:states].sort.each do |s|
              forests = usfs.forest_ids_for_state(s)
              if self.parser.options[:convert]
                r, u = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(forests.keys)
                u.each do |e|
                  self.logger.warn { "unresolved forest name: #{e.join(', ')}" }
                end

                forests = r.reduce({ }) do |rv, e|
                  rv[e[:name]] = e[:usfs_id]
                  rv
                end
              end
              forests.keys.sort.each do |fk|
                blk.call(usfs, s, fk, { name: fk, id: forests[fk] })
              end
            end
          end
        end
      end
    end
  end
end
