require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ridb'
require 'cf/scrubber/ridb/script'

module Cf::Scrubber::RIDB::Script
  # Framework class for iterating through the activities.

  class Activities < Cf::Scrubber::Script::Base
    # A class to parse command line arguments.
    #
    # This class defines the following options:
    # - <tt>-k APIKEY</tt> (<tt>--api-key=APIKEY</tt>) the API key to use.
    # - <tt>-s SORT</tt> (<tt>--sort=SORT</tt>) defines the sort algorithm.
    #   Allowed values are: +id+ sorts by activity ID; +name+ sorts by activity name. Defaults to +id+.

    class Parser < Cf::Scrubber::Script::Parser
      # @!visibility private

      SORT = [ :id, :name ]

      # Initializer.

      def initialize()
        rv = super()
        opts = self.parser

        opts.on_head("-kAPIKEY", "--api-key=APIKEY", "The API key to use.") do |k|
          self.options[:api_key] = k
        end

        opts.on_head("-sSORT", "--sort=SORT", "The sort key; one of #{SORT.join(', ')}.") do |s|
          self.options[:sort] = s.to_sym if SORT.include?(s.to_sym)
        end

        self.options.merge!({ api_key: nil, sort: :id })

        rv
      end
    end
    # Initializer.
    #
    # @param parser [Cf::Scrubber::Script::Parser] The parser to use.

    def initialize(parser)
      @parser = parser
    end

    # Processor.
    # This is the framework method; it fetches the list of activities and iterates
    # over each, yielding to the block provided.
    #
    # @yield [api, act] passes the following arguments to the block:
    #  - *api* is the active instance of {Cf::Scrubber::RIDB::API}.
    #  - *act* is the activity hash.

    def process(&blk)
      api = Cf::Scrubber::RIDB::API.new({
                                          :api_key => self.parser.options[:api_key],
                                          :logger => self.parser.options[:logger],
                                          :logger_level => self.parser.options[:logger_level]
                                        })
      case self.parser.options[:sort]
      when :id
        acts = api.activities().sort do |o1, o2|
          o1['ActivityID'] <=> o2['ActivityID']
        end
      when :name
        acts = api.activities().sort do |o1, o2|
          o1['ActivityName'] <=> o2['ActivityName']
        end
      end

      acts.each do |act|
        blk.call(api, act)
      end
    end
  end
end
