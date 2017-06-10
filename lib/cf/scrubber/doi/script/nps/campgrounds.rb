require 'optparse'
require 'logger'

require 'cf/scrubber'
require 'cf/scrubber/doi/script/nps'
require 'cf/scrubber/states_helper'

module Cf::Scrubber::DOI::Script::NPS
  # Framework class for iterating through campgrounds for various states.

  class Campgrounds < Cf::Scrubber::Script::CampgroundList
    include Cf::Scrubber::StatesHelper

    # A class to parse command line arguments.
    #
    # The base class defines the following options:
    # - *-sSTATES* (*--states=STATES*) to set the list of states for which to list campgrounds.
    # - *-aREC_AREAS* (*--rec-areas=REC_AREAS*) to set the list of rec areas for which to list campgrounds.
    # - *-SSTATEFORMAT* (*--state-format=STATEFORMAT*) is the output format to use for the state name.

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

        opts.on_head("-aREC_AREAS", "--rec-areas=REC_AREAS", "Comma-separated list of rec areas for which to list campgrounds. Shows all rec areas (per state) if not given.") do |sl|
          self.options[:rec_areas] = sl.split(',').map do |s|
            s.strip.downcase
          end
        end

        opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of states for which to list forests. You may use two-character state codes.") do |sl|
          self.options[:states] = sl.split(',').map do |s|
            t = s.strip
            (t.length == 2) ? t.upcase : t
          end
        end

        self.options.merge!( { states: nil, rec_areas: nil, state_format: :full })

        rv
      end
    end

    # Initializer.
    #
    # @param parser [Cf::Scrubber::DOI::Script::NPS::Campgrounds::Parser] The parser to use.

    def initialize(parser)
      @parser = parser
    end

    # Implements the processing loop for campgrounds.

    def process_campgrounds()
      exec do |nps, c, s, ra|
        if @cur_state != s
          if self.parser.options[:state_format] == :short
            self.output.printf("#-- State %s\n", get_state_code(s))
          else
            self.output.printf("#-- State %s\n", s)
          end

          @cur_state = s
          @cur_rec_area = ra
          @cur_rec_area_id = ra[:id]
        end

        if @cur_rec_area_id != ra[:id]
          self.output.printf("#-- Rec Area %s\n", ra[:name])
          @cur_rec_area = ra
          @cur_rec_area_id = ra[:id]
        end

        emit_campground(c)
      end
    end

    protected

    # Initialize processing.
    # Calls the superclass and then sets up tracking variables

    def process_init
      super()

      @cur_state = ''
      @cur_rec_area = ''
      @cur_rec_area_id = ''
    end

    # Processor.
    # This is the framework method; it fetches campgrounds for each state and iterates
    # over each, yielding to the block provided.
    #
    # @yield [nps, c, s, ra] The processor block
    #
    # @yieldparam [Cf::Scrubber::DOI::NationalParkService] nps The active scrubber instance.
    # @yieldparam [Hash] c The campground data.
    # @yieldparam [String] s The state name.
    # @yieldparam [Hash] ra A hash containing rec area information:
    #  - *:name* A string containing the rec area name.
    #  - *:id* A string containing the rec area's identifier.
    #  - *:data* A hash containing the rec area data.

    def process(&blk)
      states = self.parser.options[:states]
      unless states.is_a?(Array) && (states.count > 0)
        print("error: you must list at least one state\n")
        exit(1)
      end

      nps = Cf::Scrubber::DOI::NationalParkService.new(nil, {
                                                         :output => self.parser.options[:output],
                                                         :logger => self.parser.options[:logger],
                                                         :logger_level => self.parser.options[:logger_level]
                                                       })

      rec_areas = self.parser.options[:rec_areas]

      states.each do |s|
        ral = nps.rec_areas_for_state_and_activities(s, [ Cf::Scrubber::RIDB::API::ACTIVITY_CAMPING ])
        if ral && (ral.count > 0)
          ral.each do |raid, ra|
            if rec_areas.nil? || rec_areas.include?(ra['RecAreaName'].downcase)
              self.logger.info { "processing rec area (#{ra['RecAreaName']})" }

              fl = nps.facilities_for_rec_area(raid)
              if fl && (fl.count > 0)
                cl = nps.extract_campgrounds(fl)
                if cl && (cl.count > 0)
                  rad = { id: raid.to_s, name: ra['RecAreaName'], data: ra }
                  nps.convert_campgrounds(cl).each do |c|
#                  self.logger.info { "campground (#{c[:name]}) in rec area (#{ra['RecAreaName']})" }
                    blk.call(nps, c, s, rad)
                  end
                else
                  self.logger.warn { "no campgrounds for state (#{s}) in rec area (#{ra['RecAreaName']})" }
                end
              else
                self.logger.warn { "no facilities for state (#{s}) in rec area (#{ra['RecAreaName']})" }
              end
            end
          end
        else
          self.logger.warn { "no rec areas with campgrounds for state (#{s})" }
        end
      end
    end
  end
end
