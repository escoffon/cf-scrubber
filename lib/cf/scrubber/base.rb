require 'net/http'
require 'json'
require 'nokogiri'
require 'logger'
require 'cf/scrubber/logged_api'

module Cf
  module Scrubber
    # The base class for scrubbers.
    #
    # Scrubbers are expected to generate campground data in a common format: a hash containing a number
    # of standard keys. Each scrubber can also add scrubber-specific keys.
    # The common set of keys is:
    # - *:organization* The name of the organization that controls this campground; for example, for
    #   the National Forest Service it is +usda:nfs+, and for the California State Park system it
    #   is +ca:state+.
    # - *:name* The campground name.
    # - *:uri* The URL to the campground's details page; this value is expected to be unique across all
    #   campgrounds and organizations, and it is used as the identifier for the campground.
    # - *:region* A region that has competence over the campground. This need not be a geographical region:
    #   it could be a department of the *:organization*, for example. The National Forest Service stores
    #   the state name here; various state park systems store the state name.
    # - *:area* A subset of *:region*. For example, the National Forest Service stores the name of the
    #   national forest (or grassland) where the campground is located; California state parks store the
    #   name of the district where the campground is located; Oregon and Nevada leave it blank.
    # - *:location* The geographic coordinates of the campground. The value is either a hash containing
    #   the keys *:lat*, *:lon*, and *:elevation*, or a string representation of the coordinates.
    #   The string representation should be in PostGIS EWKT format, for example for coordinates in a
    #   Mercator projection system: <code>SRID=3857;POINT(-12495099.247068636 5016311.2562325643)</code>.
    # - *:types* An array listing the types of campsites in the campground. See {CAMPSITE_TYPES}.
    # - *:reservation_uri* The URL to the reservation page for the campground.
    # - *:blurb* A short description of the campground.
    # - *:additional_info* A hash containing an open-ended collection of properties for this campground.
    #   The constant {ADDITIONAL_INFO_KEYS} lists standard keys; scrubber subclasses can add their own.

    class Base
      include Cf::Scrubber::LoggedAPI

      # Standard campsite: tent accomodations.

      TYPE_STANDARD = :standard

      # Group campsite: tent accomodations for groups (multiple tents?).

      TYPE_GROUP = :group

      # Cabins, yurts, and other permanent or semipermanent accomodations.

      TYPE_CABIN = :cabin

      # Accomodations for RVs.

      TYPE_RV = :rv

      # The standard campsite names.

      CAMPSITE_TYPES = [ TYPE_STANDARD, TYPE_GROUP, TYPE_CABIN, TYPE_RV ]

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
                              :things_to_do,
                              :usage,
                              :water
                             ]

      # Initializer.
      #
      # @param root_url [String] The root URL (if any) for the web site to scrub.
      # @param opts [Hash] Additional configuration options for the scrubber.
      # @option opts [String, IO] :output A stream object, or a string containing a file path for the
      #  output to use when generating data. The stream must have been opened for writing. The string will
      #  be opened for writing with the truncate option (existing files are overwritten).
      #  If not specified, +STDOUT+ is used.
      # @option opts [Logger] :logger The logger object to use. If none is specified, the scrubber creates a
      #  standard object writing to +STDERR+. If +nil+ is specified, no logging is done.
      # @option opts :logger_level The logger level to use; this is one of the levels defined by the +Logger+
      #  class. The default value is +Logger::INFO+. This option can also be passed as a string, in which
      #  case the initializer attempts to convert it to a +Logger+ constant.

      def initialize(root_url = nil, opts = {})
        @root_url = root_url

        if opts.has_key?(:output)
          if opts[:output].is_a?(IO)
            @output = opts[:output]
          elsif opts[:output].is_a?(String)
            case opts[:output]
            when 'STDOUT'
              @output = STDOUT
            when 'STDERR'
              @output = STDERR
            else
              @output = File.open(opts[:output], 'w')
            end
          else
            @output = STDOUT
          end
        else
          @output = STDOUT
        end

        initialize_logger(opts)
      end

      # @!attribute [r] root_url
      # A string containing the root URL for the web site to scrub; this value was set in the initializer.
      # @return [String] the root URL, as a string.
      attr_reader :root_url

      # @!attribute [rw] outpput
      # The output stream to use.
      # @return [IO] the current output stream.
      attr_accessor :output

      # Convert a relative URL to a full one, filtering out query parameters as instructed.
      # Calls the class method {.adjust_href}.
      #
      # @param [String] href A string containing a URl, which is possibly relative.
      # @param [String,URI::Generic] base The URI object containing the parsed representation of
      #  the base URL, or a string containing the base URL.
      # @param [Array<String>] qf An array containing the names of query string parameters to be
      #  dropped from the query string.
      #
      # @return [String] Returns a string containing the adjusted URL.

      def adjust_href(href, base, qf = [ ])
        Cf::Scrubber::Base.adjust_href(href, base, qf)
      end

      # Convert a relative URL to a full one, filtering out query parameters as instructed.
      # The method parses _href_ and generates a new URL using the components of _base_ if not present
      # in _href_. The +path+ component is treated differently: if it starts with a '/', the path in
      # _href_ is used as is. Otherwise, the path in _href_ is appended to the path in _base_.
      # Finally, the parameters in _qf_ are dropped from the query string.
      #
      # @param [String, nil] href A string containing a URL, which is possibly relative. If +nil+ or an
      #  empty string, the method returns the URL for _base_.
      # @param [String,URI::Generic] base The URI object containing the parsed representation of
      #  the base URL, or a string containing the base URL.
      # @param [Array<String>] qf An array containing the names of query string parameters to be
      #  dropped from the query string.
      #
      # @return [URI::Generic] Returns a URI instance containing the adjusted URL, as described above.

      def self.adjust_href(href, base, qf = [ ])
        base_uri = (base.is_a?(String)) ? URI(base) : base
        if href.nil? || (href.length < 1)
          base_uri
        else
          h_uri = URI(href)

          scheme = (h_uri.scheme.nil?) ? base_uri.scheme : h_uri.scheme
          params = {
            host: (h_uri.host.nil?) ? base_uri.host : h_uri.host,
            fragment: (h_uri.fragment.nil?) ? base_uri.fragment : h_uri.fragment
          }

          if h_uri.path
            if h_uri.path[0] == '/'
              params[:path] = h_uri.path
            else
              params[:path] = base_uri.path + '/' + h_uri.path
            end
          else
            params[:path] = base_uri.path
          end

          query = (h_uri.query.nil?) ? base_uri.query : h_uri.query
          if !query.nil?
            if qf.count > 0
              qa = query.split('&').select do |e|
                !qf.include?(e.split('=')[0])
              end
              params[:query] = qa.join('&')
            else
              params[:query] = query
            end
          end

          case scheme.downcase
          when 'http'
            URI::HTTP.build(params)
          when 'https'
            URI::HTTPS.build(params)
          else
            params[:scheme] = scheme
            URI::Generic.build(params)
          end
        end
      end
    end
  end
end
