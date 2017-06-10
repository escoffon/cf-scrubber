require 'optparse'
require 'logger'
require 'cf/scrubber'
require 'cf/scrubber/ridb'
require 'cf/scrubber/ridb/script'

module Cf::Scrubber::RIDB::Script
  # Framework class for iterating through the organizations.

  class Organizations < Cf::Scrubber::Script::Base
    # A class to parse command line arguments.
    #
    # This class defines the following options:
    # - *-kAPIKEY* (*--api-key=APIKEY*) the API key to use.
    # - *-n* (*--no-flat*) to have the script build a hierarchical rather than flat list.

    class Parser < Cf::Scrubber::Script::Parser
      # Initializer.

      def initialize()
        rv = super()
        opts = self.parser

        opts.on_head("-kAPIKEY", "--api-key=APIKEY", "The API key to use.") do |k|
          self.options[:api_key] = k
        end

        opts.on_head("-n", "--no-flat", "If present, generate a hierarchical organization list.") do
          self.options[:flat] = false
        end

        self.options.merge!({ api_key: nil, flat: true })

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
    # This is the framework method; it fetches the list of organizations and iterates
    # over each, yielding to the block provided.
    #
    # @yield [api, org] passes the following arguments to the block:
    #  - *api* is the active instance of {Cf::Scrubber::RIDB::API}.
    #  - *org* is the organization hash.

    def process(&blk)
      api = Cf::Scrubber::RIDB::API.new({
                                          :api_key => self.parser.options[:api_key],
                                          :logger => self.parser.options[:logger],
                                          :logger_level => self.parser.options[:logger_level]
                                        })
      orgs = api.organizations(self.parser.options[:flat]).sort do |o1, o2|
        if o1.has_key?(:organization)
          o1[:organization]['OrgID'] <=> o2[:organization]['OrgID']
        else
          o1['OrgID'] <=> o2['OrgID']
        end
      end

      orgs.each do |org|
        blk.call(api, org)
      end
    end
  end
end
