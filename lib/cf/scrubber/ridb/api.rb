require 'json'

require 'cf/scrubber/logged_api'
require 'cf/scrubber/states_helper'

module Cf::Scrubber::RIDB
  # The RIDB API.
  #
  # === Common API parameters
  # The API URLs may include a number of parameters in their query string; unless otherwise noted, all these
  # parameters are optional. Not all API calls support all; see the documentation for individual
  # API calls for a list of the supported parameters.
  # - *query* A string containing query filter criteria. The search context is API call dependent.
  # - *limit* A numeric value containing the number of records to return in a call (max 50).
  # - *offset* A numeric value containing the start record in the overall result set.
  # - *full* A string value that controls if the API returns the full record details or compact (abbreviated)
  #   details. Typically, one uses a the value +true+ to request full records, and does not specify the
  #   parameter for compact records.
  # - *state* A string containing the comma delimited list of 2 character state codes: only results in those
  #   states are returned.
  # - *activity* A string containing the comma delimited list of activity IDs to filter: only results that
  #   contain those activities are returned.
  # - *lastupdated* A date value to return all records modified since this date.
  # - *latitude* A numeric value containing the latitude of the point in decimal degrees.
  # - *longitude* A numeric value containing the longitude of the point in decimal degrees.
  # - *radius* A numeric value containing the distance (in miles) by which to include search results.
  #
  # Note that *latitude*, *longitude*, and *radius* must all apeear together.
  #
  # For example, to return the first 10 records in California for camping, use +state=CA&activity=9&limit=10+.
  #
  # === Pagination
  # The RIDB API supports pagination using the two parameters *offset* and *limit*. Many API calls in this
  # class fetch multiple pages automatically, so that users of the class do not need to implement pagination
  # loops. See {#pagination_loop} for details.

  class API
    include Cf::Scrubber::LoggedAPI
    include Cf::Scrubber::StatesHelper

    # The default API key to use (belongs to emil@scoffone.com, at some point we'll have to register one for
    # the gem).

    DEFAULT_API_KEY = 'AC446564B088446090BAE3A5A07FEAFB'

    # The root for the RIDB API URLs.
    URL_ROOT = 'https://ridb.recreation.gov/api/v1'

    # @!visibility private
    ROOT_ORGANIZATIONS = '/organizations'

    # @!visibility private
    ROOT_ACTIVITIES = '/activities'

    # @!visibility private
    ROOT_REC_AREAS = '/recareas'

    # @!visibility private
    ROOT_FACILITIES = '/facilities'

    # @!visibility private
    ROOT_CAMPSITES = '/campsites'

    # The organization ID for the US Forest Service.
    ORGID_USFS = 131

    # The organization ID for the National Park Service.
    ORGID_NPS = 128

    # The organization ID for the Bureau of Land Management.
    ORGID_BLM = 126

    # The activity code for camping.
    ACTIVITY_CAMPING = 9

    # The activity code for cabins.
    ACTIVITY_CABINS = 30

    # The activity code for horse camping.
    ACTIVITY_HORSE_CAMPING = 109

    # The activity code for federal or state owned lodges, hotels, or resorts.
    ACTIVITY_LODGING_FEDERAL_STATE = 40

    # The activity code for privately owned lodges, hotels, or resorts.
    ACTIVITY_LODGING_PRIVATE = 44

    # The activity code for recreational vehicles.
    ACTIVITY_RV = 23

    # @!attribute [r]
    # @return Returns the API key.

    attr_reader :api_key

    # @!attribute [r]
    # @return Returns the HTTP::Response from the last API call executed.

    attr_reader :last_response

    # Initializer.
    #
    # @param [Hash] opts Configuration options.
    # @option opts [String] :api_key The API key to use. If none is provided, use {DEFAULT_API_KEY}.
    # @option opts [Logger] :logger The logger object to use. If none is specified, the scrubber creates a
    #  standard object writing to +STDERR+. If +nil+ is specified, no logging is done.
    # @option opts :logger_level The logger level to use; this is one of the levels defined by the +Logger+
    #  class. The default value is +Logger::INFO+. This option can also be passed as a string, in which
    #  case the initializer attempts to convert it to a +Logger+ constant.

    def initialize(opts = {})
      @api_key = (opts.has_key?(:api_key) && opts[:api_key].is_a?(String)) ? opts[:api_key] : DEFAULT_API_KEY
      @last_response = nil
      initialize_logger(opts)
    end

    # Get the list of organizations.
    #
    # @param [Boolean] flat If +true+, the return value is a flat list; if +false+, it is a hierrchical
    #  list. See the description of the return value.
    #
    # @return If _flat_ is +true+, the return value is an array of hashes containing organization data as
    #  returned by the API call. If _flat_ is +false+ the return value is also an array of hashes, but of
    #  different format; in this case, the hashes contain two keys: *:organization* is a the hash of 
    #  organization data, and *:children* (if present) is an array of hashes that contain te organization's
    #  children (also in *:organization*/*:chidren* format).

    def organizations(flat = true)
      result = api_call(ROOT_ORGANIZATIONS)
      return nil if result.nil?

      orgs = result[:results]
      return orgs if flat

      idmap = {}
      parentmap = {}
      orgs.each do |o|
        oid = o['OrgID']
        idmap[oid] = o

        pid = o['OrgParentID']
        parentmap[pid] = [] unless parentmap.has_key?(pid)
        parentmap[pid] << oid
      end

      # OK, to build it we start with 0, which is the list of organizations that do not have a parent.
      # These are going to be at the root of the hash.

      rv = []
      parentmap[0].each do |oid|
        rv << make_organization(oid, idmap, parentmap)
      end

      rv
    end

    # Get the list of activities.
    #
    # @param [Hash] params A hash of parameters for the API call.
    #  Supports the parameters *limit*, *offset*, and *query* (searches on activity name).
    #
    # @return Returns an array of hashes containing activity descriptors.

    def activities(params = {})
      rv = []
      try_again = true
      fetched = 0
      p = params.dup
      p[:offset] = 0

      while try_again do
        result = api_call(ROOT_ACTIVITIES, p)
        return nil if result.nil?
        rv += result[:results]

        meta = result[:meta]
        fetched += meta[:count]
        if fetched >= meta[:total]
          try_again = false
        else
          p[:offset] += meta[:count]
        end
      end

      rv
    end

    # Get the list of rec areas for a given organization.
    #
    # @param [Integer] orgid The ID for the organization.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters:
    #  *query* (searches on recreation area name, description, keywords, and stay limit),
    #  *limit*, *offset*, *full*, *state*, *activity*, and *lastupdated*.
    #
    # @return Returns an array of hashes describing the rec areas.
    #  A few notes on the return value:
    #  - The return value is the raw result from the API call. In particular, the API seems to return
    #    duplicate records: for example, a call for National Park Service rec areas in CA returns 13
    #    duplicates ("Alcatraz Island", recid 2558 appears twice in the resut set, and 12 more). These
    #    duplicates have *not* been removed from the return value.
    #  - When using the *:state* parameters, rec areas that lay in more than one state are not returned.
    #    Placing all the states in the *:states* list still does not seem to return those areas.
    #    (Multiple states in *:states* return the union of the rec areas for all the listed states.)

    def rec_areas_for_organization(orgid, params = {})
      path = "#{ROOT_ORGANIZATIONS}/#{orgid}#{ROOT_REC_AREAS}"

      rv = pagination_loop(params) do |p, c|
        api_call(path, params)
      end

      rv
    end

    # Get a rec area.
    #
    # @param [Integer] rec_area_id The ID for the rec area.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters: *full*.
    #
    # @return Returns a hash describing the rec area.

    def get_rec_area(rec_area_id, params = {})
      path = "#{ROOT_REC_AREAS}/#{rec_area_id}"
      api_call(path, params)
    end

    # Get the list of activities for a given rec area.
    #
    # @param [Integer] rec_area_id The ID for the rec area.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters:
    #  *query* (searches on activity name), *limit*, and *offset*.
    #
    # @return Returns an array of hashes describing the activities.

    def activities_for_rec_area(rec_area_id, params = {})
      path = "#{ROOT_REC_AREAS}/#{rec_area_id}#{ROOT_ACTIVITIES}"

      pagination_loop(params) do |p, c|
        api_call(path, params)
      end
    end

    # Get the list of facilities for a given organization.
    #
    # @param [Integer] orgid The ID for the organization.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters:
    #  *query* (searches on facility name, description, keywords, and stay limit),
    #  *limit*, *offset*, *full*, *state*, *activity*, and *lastupdated*.
    #
    # @return Returns an array of hashes describing the facilities.

    def facilities_for_organization(orgid, params = {})
      path = "#{ROOT_ORGANIZATIONS}/#{orgid}#{ROOT_FACILITIES}"

      pagination_loop(params) do |p, c|
        api_call(path, params)
      end
    end

    # Get the list of facilities for a given rec area.
    #
    # @param [Integer] rec_area_id The ID for the rec area.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters:
    #  *query* (searches on facility name, description, keywords, and stay limit),
    #  *limit*, *offset*, *latitude*, *longitude*, *radius*, and *lastupdated*.
    #
    # @return Returns an array of hashes describing the facilities.

    def facilities_for_rec_area(rec_area_id, params = {})
      path = "#{ROOT_REC_AREAS}/#{rec_area_id}#{ROOT_FACILITIES}"

      pagination_loop(params) do |p, c|
        api_call(path, params)
      end
    end

    # Get a facility.
    #
    # @param [Integer] fac_id The ID for the facility.
    # @param [Boolean] full Set to +true+ to fetch a full result, +false+ for a subset of the full result.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters: *full*.
    #
    # @return Returns a hash describing the facility.

    def get_facility(fac_id, full = true, params = {})
      path = "#{ROOT_FACILITIES}/#{fac_id}"
      p = (full) ? params.merge({ full: 'true'}) : params

      api_call(path, p)
    end

    # Get the list of activities for a given facility.
    #
    # @param [Integer] fac_id The ID for the facility.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters:
    #  *query* (searches on activity name), *limit*, and *offset*.
    #
    # @return Returns an array of hashes describing the activities.

    def activities_for_facility(fac_id, params = {})
      path = "#{ROOT_FACILITIES}/#{fac_id}#{ROOT_ACTIVITIES}"

      pagination_loop(params) do |p, c|
        api_call(path, params)
      end
    end

    # Get the list of campsites for a given facility.
    # A campsite is an individual camping slot; a campground contains one or more campsites.
    #
    # @param [Integer] fac_id The ID for the facility.
    # @param [Hash] params A hash of parameters for the request.
    #  The API supports the following parameters:
    #  *query* (searches on campsite name, type, loop, type of use (Overnight/Day),
    #  campsite accessible (Yes/No)), *limit*, and *offset*.
    #
    # @return Returns an array of hashes describing the campsites.

    def campsites_for_facility(fac_id, params = {})
      path = "#{ROOT_FACILITIES}/#{fac_id}#{ROOT_CAMPSITES}"

      pagination_loop(params) do |p, c|
        api_call(path, params)
      end
    end

    # Pagination loop wrapper.
    # This method implements a loop to fetch results sets using the pagination facilities provided by
    # the RIDB API.
    # It sets up some control structures, including the maximum number of records to return from the *max*
    # parameter. It then loops, yielding to the block with each iteration; two arguments are passed to the
    # block, as described below.
    # If the block returns a hash, it adds the results to the current list, bumps the *offset* parameter
    # appropriately, and repeats the loop. If the block returns +false+, it exits the loop
    # *before adding the results*. Finally, if the block returns +nil+, it returns +nil+ to indicate that
    # the call failed.
    # Additionally, if *max* was present in _params_, it exits the loop if at least that many total records
    # were returned.
    #
    # @param [Hash] params A hash of parameters for the API call, which are described in the class 
    #  documentation.
    #  The value of *offset* is the starting position of the first record to return, and defaults to 0 if
    #  not present.
    #  In addition to the standard API parameters, *max* specifies the maximum number of records to return;
    #  if *max* is not provided, all records are returned.
    #
    # @return [Array<Hash>] Returns an array of hashes containing the records from the API call..
    #
    # @yield [p, cur] The block is expected to make an API call (via {#api_call} or a method that calls it),
    #  and return one of the values described below.
    #
    # @yieldparam [Hash] p A hash containing query parameters for the URL. The list of supported parameters
    #  depends on the API call, but *:offset* is modified with each call to the block.
    # @yieldparam [Array<Hash>] cur An array of hashes containing the accumulated return values for each call.
    #
    # @yieldreturn [Hash, nil, false] The block returns one of three possible values:
    #  - A hash containing a return value consistent with {#api_call} (and typically a return value from
    #    {#api_call}, which should have been called in the block).
    #  - +false+ to indicate that the pagination loop should terminate.
    #  - +nil+ to indicate an error condition.

    def pagination_loop(params = {}, &blk)
      max = params.delete(:max)
      cur = []
      try_again = true
      fetched = 0
      p = params.dup
      p[:offset] = 0 unless p[:offset]

      while try_again do
        result = blk.call(p, cur)
        return nil if result.nil?
        break if result == false
        cur += result[:results]
        break if max && (cur.count >= max)

        meta = result[:meta]
        fetched += meta[:count]
        if fetched >= meta[:total]
          try_again = false
        else
          p[:offset] += meta[:count]
        end
      end

      cur
    end

    # Make an API call.
    # This method builds the URL by potentially appending _path_ to the root URL, tagging on the +.json+ format
    # qualifier, and building the query string.
    # It then sets up the +apikey+ header and the +Content-Type+ header (to indicate that we will accept
    # JSON).
    # Finally, it calls {Cf::Scrubber::LoggedAPI::InstanceMethods#get}, parses its return value on
    # success, and returns the parsed data.
    #
    # @param path [String] The URL for the call. If this is a full URL, it is used as is; if a path, it is
    #  appended to the root URL. For example, to list organizations this value is <code>/organizations</code>.
    # @param params [Hash] The query string parameters to add to the API call.
    #
    # @return [Hash] If this is a paginated API call, the return value is a hash containing two keys:
    #  - *:results* contains the actual results from the call, which are request-dependent.
    #  - *:meta* contains a hash with metadata about the call:
    #    - *:count* is the number of records returned.
    #    - *:total* is the total number of records available.
    #    - *:query* is the query string used in the call.
    #    - *:offset* is the offset for the results to return.
    #    - *:limit* is the maximum number of results to return.
    #  Otherwise, the return value is a hash containing the requested record.

    def api_call(path, params = {})
      if path[0] == '/'
        url = URL_ROOT + path + '.json'
      else
        url = path + '.json'
      end
      qa = []
      # Should I URL-encode this?
      params.each { |pk, pv| qa << "#{pk}=#{pv}" }
      url += "?#{qa.join('&')}" if qa.count > 0

      headers = {
        'Accept' => 'application/json, */*; q=0.01',
        'apikey' => @api_key
      }

      @last_response = get(url, headers: headers)
      return nil unless @last_response.is_a?(Net::HTTPOK)

      json = JSON.parse(@last_response.body)

      # The API returns one of:
      # - an array with one or more hashes. If no hashes, something was wrong in the call.
      #   For example, campsite details return this
      # - a pagination hash, which contains RECDATA and METADATA.
      #   For example, lists of rec areas of facilities return this.
      # - a hash containing data about an entity.
      #   For example, rec area or facility details return this.

      if json.is_a?(Array)
        return (json.count < 1) ? nil : json
      end

      if json.has_key?('RECDATA') && json.has_key?('METADATA')
        # This is a paginated API call
        md = json['METADATA']

        {
          results: json['RECDATA'],
          meta: {
            count: md['RESULTS']['CURRENT_COUNT'],
            total: md['RESULTS']['TOTAL_COUNT'],
            query: md['SEARCH_PARAMETERS']['QUERY'],
            offset: md['SEARCH_PARAMETERS']['OFFSET'],
            limit: md['SEARCH_PARAMETERS']['LIMIT']
          }
        }
      else
        json
      end
    end

    private

    def make_organization(oid, idmap, parentmap)
      rv = { organization: idmap[oid] }
      if parentmap.has_key?(oid) && (parentmap[oid].count > 0)
        rv[:children] = parentmap[oid].map { |pid| make_organization(pid, idmap, parentmap) }
      end

      rv
    end
  end
end
