require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ridb'
require 'cf/scrubber/ridb/script'

module Cf::Scrubber::RIDB::Script
  # Framework class for running a rec area and facility query.

  class Query < Cf::Scrubber::Script::Base
    # A class to parse command line arguments.
    #
    # This class defines the following options:
    # - <tt>-k APIKEY</tt> (<tt>--api-key=APIKEY</tt>) the API key to use.
    # - <tt>-s STATES</tt> (<tt>--states=STATES</tt>) is the list of states to place in the query parameters.
    #   This is a comma-separated list of two-letter state codes, like +CA,OR,NM,WY+.
    #   If not provided, no +state+ query parameter is submitted.
    # - <tt>-a ACTIVITIES</tt> (<tt>--activities=ACTIVITIES</tt>) is the list of activities to place in
    #   the query parameters. This is a comma-separated list of activity names or activity codes.
    #   For example: +9,5+ is equivalent to +CAMPING,BIKING+ or +9,BIKING+.
    #   If not provided, no activity filtering is done.
    # - <tt>-q QUERY</tt> (<tt>--query=QUERY</tt>) is the query string to user.
    #   This value, if present, is passed in the +query+ parameter.
    # - <tt>-t TYPES</tt> (<tt>--types=TYPES</tt>) is the list of record types to return.
    #   This is a comma-separated list containing +R+ and +F+ (for rec areas and facilities, respectively).
    #   If not provided, both rec reas and facilities are returned.
    # - <tt>-f</tt> (<tt>--full</tt>) If present, fetch full rec area records.

    class Parser < Cf::Scrubber::Script::Parser
      # Initializer.

      def initialize()
        rv = super()
        opts = self.parser

        opts.on_head("-kAPIKEY", "--api-key=APIKEY", "The API key to use.") do |k|
          self.options[:api_key] = k
        end

        opts.on_head("-f", "--full", "If present, fetch full records.") do
          self.options[:full] = true
        end

        opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of state codes for states to return.") do |s|
          self.options[:states] = s
        end

        opts.on_head("-aACTIVITIES", "--activities=ACTIVITIES", "Comma-separated list of activity names or codes for activity filtering.") do |a|
          self.options[:activities] = a
        end

        opts.on_head("-qQUERY", "--query=QUERY", "The 'query' parameter.") do |q|
          self.options[:query] = q
        end

        opts.on_head("-tTYPES", "--types=TYPES", "Comma-separated list of record types to return.") do |t|
          self.options[:types] = t
        end

        self.options.merge!({ api_key: nil, states: nil, activities: nil, types: 'R,F',
                              full: false, query: nil })

        rv
      end
    end

    # Initializer.
    #
    # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

    def initialize(parser)
      @parser = parser
      @act_map = nil
    end

    # Run the query.
    # This is the method that should be called to run the script; it starts the process, and calls
    # {#process_record} for each record in the queries.

    def run_query()
      self.exec do |api, type, rec|
        process_record(api, type, rec)
      end
    end

    protected

    # Process one record.
    # This implementation is empty: subclasses are expected to override it.
    #
    # @param api [Cf::Scrubber::RIDB::API] The active instance of {Cf::Scrubber::RIDB::API}.
    # @param type [String] The record type.
    # @param rec [Hash] The record.

    def process_record(api, type, rec)
    end

    # Processor.
    # This is the framework method; it runs the query, yielding to the block provided for each record.
    #
    # ==== Note
    # If both rec areas and facilities are requested, the query returns first all rec areas, and then all
    # all facilities, so that the records are returned in order R,R,...,R,F,F...: we don't nest facilities
    # inside rec areas, because if we do that we may miss facilities that are nested inside a rec area
    # that is not returned by the query.
    #
    # @yield [api, type, rec] passes the following arguments to the block:
    #  - *api* is the active instance of {Cf::Scrubber::RIDB::API}.
    #  - *type* is the record type: +R+ for rec areas, +F+ for facilities.
    #  - *rec* is the record.

    def process(&blk)
      api = Cf::Scrubber::RIDB::API.new({
                                          :api_key => self.parser.options[:api_key],
                                          :logger => self.parser.options[:logger],
                                          :logger_level => self.parser.options[:logger_level]
                                        })

      params = { }
      if self.parser.options[:states].is_a?(String)
        params[:state] = (self.parser.options[:states].split(',').map { |s| s.strip.upcase.to_sym }).join(',')
      end

      if self.parser.options[:activities].is_a?(String)
        alist = self.parser.options[:activities].split(',').reduce([ ]) do |rv, a|
          if a != /^[0-9]$/
            a = activity_map(api)[a.upcase]
            rv << a.to_s if a
          else
            rv << a
          end

          rv
        end

        params[:activity] = alist.join(',')
      end

      params[:query] = self.parser.options[:query] if self.parser.options[:query].is_a?(String)
      params[:full] = 'yes' if self.parser.options[:full]

      types = self.parser.options[:types].split(',').map { |t| t.strip.upcase }

      if types.include?('R')
        api.rec_areas_for_organization(Cf::Scrubber::RIDB::API::ORGID_USFS, params).each do |a|
          blk.call(api, 'R', a)
        end
      end

      if types.include?('F')
        api.facilities_for_organization(Cf::Scrubber::RIDB::API::ORGID_USFS, params).each do |f|
          blk.call(api, 'F', f)
        end
      end
    end

    private

    def activity_map(api)
      if @act_map.nil?
        @act_map = { }
        api.activities.each do |a|
          @act_map[a['ActivityName']] = a['ActivityID']
        end
      end

      @act_map
    end
  end
end
