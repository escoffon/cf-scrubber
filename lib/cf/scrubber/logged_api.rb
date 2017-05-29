require 'net/http'
require 'json'
require 'nokogiri'
require 'logger'

module Cf
  module Scrubber
    # A mixin module that defines HTTP methods that emit to a logger.

    module LoggedAPI
      # The default values for request headers.

      DEFAULT_HEADERS = {
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.8'
      }

      # The methods in this module will be installed as class methods of the including class.

      module ClassMethods
      end

      # The methods in this module are installed as instance method of the including class.

      module InstanceMethods
        # Initialize logger support.
        # This should typically be called in a class initializer; see, for example,
        # {Cf::Scrubber::Base#initialize}.
        #
        # @param opts [Hash] Configuration options for the object.
        # @option opts [Logger] :logger The logger object to use. If none is specified, the method creates a
        #  standard logger writing to +STDERR+. If +nil+ is specified, no logging is done.
        # @option opts :logger_level The logger level to use; this is one of the levels defined by the +Logger+
        #  class. The default value is +Logger::INFO+. This option can also be passed as a string, in which
        #  case the initializer attempts to convert it to a +Logger+ constant.
        #  Note that this option is ignored if *:logger* is defined.

        def initialize_logger(opts = {})
          if opts.has_key?(:logger)
            if opts[:logger].is_a?(Logger)
              @logger = opts[:logger]
            else
              @logger = Logger.new(nil)
            end
          else
            @logger = Logger.new(STDERR)

            @logger.level = if opts.has_key?(:logger_level)
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
        end

        # @!attribute [rw] logger
        # The logger associated with the object.
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
              uri = redirect_uri(URI(res['Location']), res)
              max_redirects -= 1
            else
              max_redirects = 0

              if res.is_a?(Net::HTTPNotFound)
                self.logger.warn { "GET request returns Not Found for (#{uri.to_s})" }
              end
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

          res = nil
          max_redirects = opts.has_key?(:max_redirects) ? opts[:max_redirects] : 4
          uri = URI(url)
          while max_redirects > 0 do
            self.logger.debug { "POST (#{max_redirects}): " + uri.to_s }
            req = Net::HTTP::Post.new(uri)
            headers.each { |hk, hv| req[hk] = hv }
            req.set_form_data(form_data)

            res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.request(req)
            end

            if res.is_a?(Net::HTTPRedirection)
              uri = redirect_uri(URI(res['Location']), res)
              max_redirects -= 1
            else
              max_redirects = 0

              if res.is_a?(Net::HTTPNotFound)
                self.logger.warn { "POST request returns Not Found for (#{uri.to_s})" }
              end
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
          Cf::Scrubber::LoggedAPI::DEFAULT_HEADERS.merge(headers)
        end

        private

        def redirect_uri(uri, res)
          if uri.scheme.nil? || uri.host.nil?
            t = res.uri.dup
            t.path = uri.path
            t.query = uri.query
            t.fragment = uri.fragment
            uri = t
          end

          uri
        end
      end

      # Perform actions when the module is included.
      # - Injects the class and instance methods.

      def self.included(base)
        base.extend ClassMethods

        base.instance_eval do
        end

        base.send(:include, InstanceMethods)

        base.class_eval do
        end
      end
    end
  end
end
