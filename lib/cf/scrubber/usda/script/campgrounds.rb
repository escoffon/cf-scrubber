require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/usda/usfs_helper'
require 'cf/scrubber/script/campground_list'

module Cf
  module Scrubber
    module USDA
      module Script
        # Framework class for iterating through campgrounds for various states and forests.

        class Campgrounds < Cf::Scrubber::Script::CampgroundList
          # A class to parse command line arguments.
          #
          # The base class defines the following options:
          # - <tt>-s STATES</tt> (<tt>--states=STATES</tt>) to set the list of states for which to list
          #   campgrounds. This is a comma-separated list of state codes, like +CA,OR,NV+.
          #   By default, all states are processed.
          # - <tt>-r FOREST</tt> (<tt>--forest=FOREST</tt>) to  the list of forests (or grasslands)
          #   for which to list campgrounds. Enter the option multiple times, one per forest to process.
          #   The value is the name of a forest or grassland, <i>as known to the USFS web site</i>; for
          #   example: <tt>Tahoe National Forest,Angeles National Forest</tt>. Note that command-line arguments
          #   will have to be enclosed in quotes, because of the spaces in the forest names.
          #   By default, all forests that apply (those that are associated with the list of states)
          #   are processed.
          # - <tt>-n</tt> (<tt>--no-details</tt>) to have the script not load campground details.
          # - <tt>-S STATEFORMAT</tt> (<tt>--state-format=STATEFORMAT</tt>) is the output format to use
          #   for the state name. The possible formats are: +full+ is the full name; +short+ is the two-letter
          #   state code. Defaults to +full+.

          class Parser < Cf::Scrubber::Script::CampgroundList::Parser
            # The known (and supported) state formats.

            STATE_FORMATS = [ :full, :short ]

            # Initializer.

            def initialize()
              rv = super()
              opts = self.parser

              opts.on_head("-SSTATEFORMAT", "--state-format=STATEFORMAT", "The output format to use for the state name: full or short (two-letter code).") do |f|
                f = f.to_sym
                self.options[:state_format] = f if STATE_FORMATS.include?(f)
              end

              opts.on_head("-n", "--no-details", "If present, do not load or emit the additional info and location info.") do
                self.options[:show_details] = false
              end

              opts.on_head("-rFOREST", "--forest=FOREST", "Name of a forest for which to list campgrounds; enter multiple times for multiple forests. Shows all forests (per state) if not given.") do |f|
                self.options[:forests] = [ ] unless self.options[:forests].is_a?(Array)
                self.options[:forests] << f.strip
              end

              opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of states for which to list forests. Shows all states if not given. You may use two-character state codes.") do |sl|
                self.options[:states] = sl.split(',').map do |s|
                  t = s.strip
                  (t.length == 2) ? t.upcase : t
                end
              end

              self.options.merge!( { states: nil, forests: nil, state_format: :full, show_details: true })

              rv
            end
          end

          # Initializer.
          #
          # @param parser [Cf::Scrubber::USDA::Script::Campgrounds::Parser] The parser to use.

          def initialize(parser)
            @parser = parser
          end

          # Implements the processing loop for campgrounds.

          def process_campgrounds()
            exec do |nfs, c, s, f|
              if @cur_state != s
                if self.parser.options[:state_format] == :short
                  self.output.printf("#-- State %s\n", nfs.state_code(s))
                else
                  self.output.printf("#-- State %s\n", s)
                end

                @cur_state = s
                @cur_forest = ''
              end

              if @cur_forest != f
                self.output.printf("#-- Forest %s\n", (f.is_a?(Hash)) ? f[:name] : f)
                @cur_forest = f
              end

              emit_campground(c)
            end
          end

          protected

          # Initialize processing.
          # Calls the superclass and then sets up tracking variables

          def process_init
            super()

            # if the format is :name, we don't need the details

            self.parser.options[:show_details] = false if self.parser.options[:format] == :name

            @cur_state = ''
            @cur_forest = ''
          end

          # Processor.
          # This is the framework method; it fetches the list of states and forests from the USFS web site,
          # iterates over each campground, yielding to the block provided.
          #
          # @yield [nfs, c, s, f] passes the following arguments to the block:
          #  - *usfs* is the active instance of {Cf::Scrubber::USDA::USFS}.
          #  - *c* is the campground data.
          #  - *s* is the state name.
          #  - *f* is the forest name.

          def process(&blk)
            usfs = Cf::Scrubber::USDA::USFS.new(nil, {
                                                  :output => self.parser.options[:output],
                                                  :logger => self.parser.options[:logger],
                                                  :logger_level => self.parser.options[:logger_level]
                                                })

            if self.parser.options[:states].nil?
              self.parser.options[:states] = usfs.states.map { |s| s[1] }
            end
            self.parser.options[:states].each do |s|
              forests = if self.parser.options[:forests].is_a?(Array)
                          self.parser.options[:forests]
                        else
                          Cf::Scrubber::USDA::USFSHelper.forests_for_state(s).keys
                        end
              fdl, unresolved = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(forests)
              unresolved.each do |u|
                self.logger.warn { "unresolved forest chain: #{u.join(', ')}" }
              end

              # If the initial forest list and the resolved descriptors don't match, let's issue a
              # warning, since the discrepancy may be the consequence of misconfigured registry entries.

              fdl_names = fdl.map { |f| f[:name] }
              if !compare_forests(forests, fdl_names)
                self.logger.warn { "requested forests (#{forests.sort.join(', ')}) and resolved forests (#{fdl_names.sort.join(', ')}) differ" }
              end

              (fdl.sort { |fd1, fd2| fd1[:name] <=> fd2[:name] }).each do |f|
                usfs.get_forest_campgrounds(s, f, self.parser.options[:types],
                                            self.parser.options[:show_details]).each do |c|
                  blk.call(usfs, c, s, f)
                end
              end
            end
          end

          private

          def compare_forests(forests, fdl_names)
            fs = forests.sort
            ds = fdl_names.sort
            d1 = fs - ds
            d2 = ds - fs

            ((d1.count + d2.count) == 0) ? true : false
          end
        end
      end
    end
  end
end
