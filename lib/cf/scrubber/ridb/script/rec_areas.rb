require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ridb'
require 'cf/scrubber/ridb/script'

module Cf::Scrubber::RIDB::Script
  # Framework class for iterating through the rec areas for an organization.

  class RecAreas < Cf::Scrubber::Script::Base
    include Cf::Scrubber::StatesHelper

    # A class to parse command line arguments.
    #
    # This class defines the following options:
    # - <tt>-k APIKEY</tt> (<tt>--api-key=APIKEY</tt>) the API key to use.
    # - <tt>-g ORGANIZATION</tt> (<tt>--organization=ORGANIZATION</tt>) the organization to target.
    #   This is either an organization name as known to RIDB, or the organization ID; for example,
    #   +National Park Service+ has ID +128+, and +USDA Forest Service+ has ID +131+.
    #   You can get organization names and IDs using the +ridb_organizations+ utility.
    #   Defaults to +USDA Forest Service+.
    # - <tt>-s STATES</tt> (<tt>--states=STATES</tt>) is the list of states for which to return rec areas.
    #   This is a comma-separated list of two-letter state codes, like +CA,OR,NM,WY+.
    #   If not provided, all states are returned.
    # - <tt>-a ACTIVITIES</tt> (<tt>--activities=ACTIVITIES</tt>) is the list of activities for which
    #   to return rec areas. This is a comma-separated list of activity names or activity codes.
    #   For example: +9,5+ is equivalent to +CAMPING,BIKING+ or +9,BIKING+.
    #   If not provided, no activity filtering is done.
    # - <tt>-f</tt> (<tt>--full</tt>) If present, fetch full rec area records.

    class Parser < Cf::Scrubber::Script::Parser
      # Initializer.

      def initialize()
        rv = super()
        opts = self.parser

        opts.on_head("-kAPIKEY", "--api-key=APIKEY", "The API key to use.") do |k|
          self.options[:api_key] = k
        end

        opts.on_head("-f", "--full", "If present, fetch full rec area records.") do
          self.options[:full] = true
        end

        opts.on_head("-sSTATES", "--states=STATES", "Comma-separated list of state codes for states to return.") do |s|
          self.options[:states] = s
        end

        opts.on_head("-aACTIVITIES", "--activities=ACTIVITIES", "Comma-separated list of activity names or codes for activity filtering.") do |a|
          self.options[:activities] = a
        end

        opts.on_head("-gORGANIZATION", "--organization=ORGANIZATION", "Name or ID of the organization to use.") do |g|
          self.options[:organization] = g
        end

        self.options.merge!({ api_key: nil, states: nil, activities: nil, full: false, organization: nil })

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

    protected

    # Processor.
    # This is the framework method; it fetches the list of rec areas for each state and iterates
    # over each, yielding to the block provided.
    #
    # @yield [api, state, areas] passes the following arguments to the block:
    #  - *api* is the active instance of {Cf::Scrubber::RIDB::API}.
    #  - *state* The two-letter state code.
    #  - *areas* is an array of hashes containing rec area information.

    def process(&blk)
      api = Cf::Scrubber::RIDB::API.new({
                                          :api_key => self.parser.options[:api_key],
                                          :logger => self.parser.options[:logger],
                                          :logger_level => self.parser.options[:logger_level]
                                        })
      states = if self.parser.options[:states].nil?
                 STATE_CODES.keys.sort
               else
                 self.parser.options[:states].split(',').map { |s| s.strip.upcase.to_sym }
               end

      organization = if self.parser.options[:organization].nil?
                       Cf::Scrubber::RIDB::API::ORGID_USFS
                     elsif self.parser.options[:organization] =~ /^[0-9]+$/
                       self.parser.options[:organization]
                     else
                       h = find_organization(self.parser.options[:organization], api)
                       if h.nil?
                         self.logger.error { "unknown organization name: #{self.parser.options[:organization]}" }
                         exit(1)
                       end
                       h['OrgID']
                     end
      params = { }
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

      params[:full] = 'yes' if self.parser.options[:full]

      states.each do |s|
        params[:state] = s
        areas = api.rec_areas_for_organization(organization, params)
        blk.call(api, s, areas)
      end
    end

    private

    def find_organization(name, api)
      api.organizations.find { |h| h['OrgName'] == name }
    end

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
