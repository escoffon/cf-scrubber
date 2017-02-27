require 'net/http'
require 'json'
require 'nokogiri'
require 'logger'

module Cf
  # The namespace module for scrubbers.

  module Scrubber
    # The base class for scrubbers.

    class Base
      # The default values for request headers.

      DEFAULT_HEADERS = {
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.8'
      }

      # The standard set of keys for the additional info hash in scrubbed data.
      # Subclasses may define other keys.

      ADDITIONAL_INFO_KEYS = [
                              :activities,
                              :amenities,
                              :campsite_types,
                              :closest_towns,
                              :fees,
                              :hours_of_operation,
                              :information_center,
                              :learning,
                              :open_season,
                              :permit_info,
                              :reservations,
                              :restrictions,
                              :restroom,
                              :usage,
                              :water
                             ]

      # Initializer.
      #
      # @param root_url [String] The root URL (if any) for the web site to scrub.
      # @param opts [Hash] Additional configuration options for the scrubber.
      # @option opts [Logger] :logger The logger object to use; if none is specified, the scrubber creates a
      #  standard object writing to +STDERR+.
      # @option opts :logger_level The logger level to use; this is one of the levels defined by the +Logger+
      #  class. The default value is +Logger::INFO+. This option can also be passed as a string, in which
      #  case the initializer attempts to convert it to a +Logger+ constant.

      def initialize(root_url = nil, opts = {})
        @root_url = root_url
        if opts.has_key?(:logger)
          @logger = opts[:logger]
        else
          @logger = Logger.new(STDERR)
        end
        logger.level = if opts.has_key?(:logger_level)
                         lvl = opts[:logger_level]
                         if lvl.is_a?(String)
                           lvl.split('::').inject(Object) { |o,c| o.const_get c }
                         else
                           lvl
                         end
                       else
                         Logger::INFO
                       end
      end

      # @!attribute [r] root_url
      # A string containing the root URL for the web site to scrub; this value was set in the initializer.
      # @return [String] the root URL, as a string.
      attr_reader :root_url

      # @!attribute [rw] logger
      # The logger associated with the scrubber.
      # @return [Object] the current logger.
      attr_accessor :logger

      # Get a page.
      #
      # @param url [String] The URL to the page.
      # @param opts [Hash] A set of options for the method.
      # @option opts [Hash] :headers A hash of request headers. The +Accept+ header is set to accept
      #  HTML if not present. The +Accept-Language+ is set to accept English if not present.
      #  The keys *must* be strings; do not use symbols.
      # @option opts [Array<String>] :cookies An array of cookie string representations that will be sent
      #  in the +Cookie+ request header. This value overrides any values in +Cookie+ from the :headers
      #  options.
      # @option opts [Integer] :max_redirects The maximum number of redirects to follow. Defaults to 4.
      #  To turn off following of redirects, set this value to 1.
      #
      # @return [Net::HTTPResponse] Returns a response object.

      def get(url, opts = {})
        headers = merge_headers(opts.has_key?(:headers) ? opts[:headers] : {})

        if opts.has_key?(:cookies)
          headers['Cookie'] = opts[:cookies].join('; ')
        end

        res = nil
        max_redirects = opts.has_key?(:max_redirects) ? opts[:max_redirects] : 4
        uri = URI(url)
        while max_redirects > 0 do
          self.logger.debug { "GET (#{max_redirects}): " + uri.to_s }
          req = Net::HTTP::Get.new(uri)
          headers.each { |hk, hv| req[hk] = hv }

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(req)
          end

          if res.is_a?(Net::HTTPRedirection)
            uri = URI(res['Location'])
            max_redirects -= 1
          else
            max_redirects = 0
          end
        end

        res
      end

      # Post a request.
      #
      # @param url [String] The URL to which to post.
      # @param form_data [Hash] The request parameters.
      # @param opts [Hash] A set of options for the method.
      # @option opts [Hash] :headers A hash of request headers. The +Accept+ header is set to accept
      #  HTML if not present. The keys *must* be strings; do not use symbols.
      # @option opts [Array<String>] :cookies An array of cookie string representations that will be sent
      #  in the +Cookie+ request header. This value overrides any values in +Cookie+ from the :headers
      #  options.
      # @option opts [Integer] :max_redirects The maximum number of redirects to follow. Defaults to 1,
      #  which turns off following of redirects.
      #  Note that the default is different than for {Cf::Scrubber::Base::get}: a POST by default returns
      #  the redirection response, whereas a GET follows it.
      #
      # @return [Net::HTTPResponse] Returns a response object.

      def post(url, form_data = {}, opts = {})
        headers = merge_headers(opts.has_key?(:headers) ? opts[:headers] : {})

        if opts.has_key?(:cookies)
          headers['Cookie'] = opts[:cookies].join('; ')
        end

        # We have to think about this. Browsers seem to do a GET on a redirect, so maybe we should
        # do the same.

        res = nil
        max_redirects = opts.has_key?(:max_redirects) ? opts[:max_redirects] : 1
        uri = URI(url)
        while max_redirects > 0 do
          self.logger.debug { "GET (#{max_redirects}): " + uri.to_s }
          req = Net::HTTP::Post.new(uri)
          headers.each { |hk, hv| req[hk] = hv }
          req.set_form_data(form_data)

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(req)
          end

          if res.is_a?(Net::HTTPRedirection)
            uri = URI(res['Location'])
            max_redirects -= 1
          else
            max_redirects = 0
          end
        end

        res
      end

      protected

      # Build request headers from defaults an local values.
      # This method merges the default header values into _headers_ and returns a new hash.
      #
      # @param headers [Hash] The local header values (to be used in a request).
      #
      # @return [Hash] Returns a hash where the values in _headers_ have been merged with a set of defaults.

      def merge_headers(headers)
        DEFAULT_HEADERS.merge(headers)
      end
    end
  end
end
