require 'net/http'
require 'json'
require 'nokogiri'
require 'cf/scrubber/logged_api'

module Cf
  module Scrubber
    # API to ReserveAmerica.

    class ReserveAmerica
      include Cf::Scrubber::LoggedAPI

      # The path to the query API.

      CAMPSITE_SEARCH_PATH = '/campsiteSearch.do'

      # The code for RV sites.

      SITE_RV = 2001

      # Initializer.
      #
      # @param root_url [String] The root URL for the Reserve America site to use. Many contracts use
      #  specialized domain names.
      # @param opts [Hash] Additional configuration options for the API.
      # @option opts [Logger] :logger The logger object to use. If none is specified, the scrubber creates a
      #  standard object writing to +STDERR+. If +nil+ is specified, no logging is done.
      # @option opts :logger_level The logger level to use; this is one of the levels defined by the +Logger+
      #  class. The default value is +Logger::INFO+. This option can also be passed as a string, in which
      #  case the initializer attempts to convert it to a +Logger+ constant.

      def initialize(root_url, opts = {})
        @root_url = URI::parse(root_url)
        initialize_logger(opts)
      end

      # @!attribute [r] root_url
      # A string containing the root URL for the Reserve America site to use; this value was set in the
      # initializer.
      # @return [URI::Generic] the root URL, as a URI object.
      attr_reader :root_url

      # Make a call to the search query and check if any RV sites are returned.
      #
      # @param params [Hash] A hash of parameters to use in the call; these values override any of the
      #  built-in values or those extracted from the root URL.
      #
      # @return [Boolean] Returns +true+ if a search for RV types returns a nonempty result set, +false+
      #  otherwise.

      def has_rv_sites?(params = {})
        check_for_site(SITE_RV, params)
      end

      protected

      # Make a call to the search query and check if any sites of a given type are returned.
      #
      # @param type [Integer] The numeric value for the type, for exampe
      #  {Cf::Scrubber::LoggedAPI::SITE_RV}.
      # @param params [Hash] A hash of parameters to use in the call; these values override any of the
      #  built-in values or those extracted from the root URL.
      #
      # @return [Boolean] Returns +true+ if a search for the type returns a nonempty result set, +false+
      #  otherwise.

      def check_for_site(type, params = {})
        return false unless @root_url.query

        surl = "https://#{@root_url.host}#{CAMPSITE_SEARCH_PATH}?#{@root_url.query}"

        # parkId and contractCode should come from the root URL

        p = {
          siteType: type,
          loop: nil,
          csite: nil,
          eqplen: nil,
          maxpeople: nil,
          hookup: nil,
          range: 1,
          arvdate: nil,
          enddate: nil,
          lengthOfStay: nil,
          siteTypeFilter: 'ALL',
          submitSiteForm: true,
          search: 'site',
          currentMaximumWindow: 12
        }

        @root_url.query.split('&') do |q|
          qk, qv = q.split('=')
          p[qk.to_sym] = qv
        end

        submit = (params.is_a?(Hash)) ? p.merge(params) : p
        res = post(surl, submit, {
                     headers: {
                       'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                     }
                   })
        if res.is_a?(Net::HTTPOK)
          doc = Nokogiri::HTML(res.body)
          return (doc.css('#csiterst table#shoppingitems').first.nil?) ? false : true
        end

        false
      end
    end
  end
end
