require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

module Cf
  module Scrubber
    # The namespace for scrubbers for OR sites.

    module OR
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Oregon State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the OR State Park System, which is part of OR).

        ORGANIZATION_NAME = 'or:state'

        # The (fixed) region name is +Oregon+, since these are OR state parks.

        REGION_NAME = 'Oregon'

        # The URL of the OR State Park System web site.

        ROOT_URL = 'http://oregonstateparks.org'

        # The path in the web site for the index page.

        INDEX_PATH = '/index.cfm?do=visit.dsp_find'

        # the path in the web site for the JSON list of parks.

        PARK_LIST_PATH = '/cfcs/shared/format.cfc'

        # the default query string for the JSON list of parks.

        PARK_LIST_DATA_QUERY = 'method=json&cfc=parks.parksData&function=findParksByDistance'

        # All known activity names.

        ACTIVITY_NAMES = [
                          'Ampitheater',
                          'Beach Access',
                          'Beach Access (Accessible)',
                          'Bike Path',
                          'Bike Path (Accessible)',
                          'Boat Ramp',
                          'Cabin',
                          'Cabin (Accessible)',
                          'Cabins/Yurts Pets OK',
                          'Cabins/Yurts Pets OK (Accessible)',
                          'Camping',
                          'Camping (Accessible)',
                          'Day-Use Fee',
                          'Deluxe Cabin',
                          'Deluxe Cabin (Accessible)',
                          'Deluxe Yurt',
                          'Deluxe Yurt (Accessible)',
                          'Disc Golf',
                          'Dump Station',
                          'Dump Station (Accessible)',
                          'Exhibit Information',
                          'Exhibit Information (Accessible)',
                          'Fishing',
                          'Fishing (Accessible)',
                          'Hiker Biker',
                          'Hiking Trails',
                          'Hiking Trails (Accessible)',
                          'Horse Trails',
                          'Hot Shower',
                          'Hot Shower (Accessible)',
                          'Kayaking',
                          'Marina',
                          'Open Year Round',
                          'Open Year Round (Accessible)',
                          'Picnicking',
                          'Picnicking (Accessible)',
                          'Playground',
                          'Playground (Accessible)',
                          'Potable Water',
                          'Reservable',
                          'Restrooms Flush',
                          'Restrooms Flush (Accessible)',
                          'Swimming',
                          'Tepee',
                          'Vault Toilets',
                          'Vault Toilets (Accessible)',
                          'Viewpoint',
                          'Viewpoint (Accessible)',
                          'Wildlife',
                          'Wildlife (Accessible)',
                          'Windsurfing',
                          'Yurt',
                          'Yurt (Accessible)'
                         ]

        # Map of feature codes to campground types.

        CAMPGROUND_TYPES_MAP = {
          standard: [ 74, 75 ],		# 74: Tent Campsites, 75: Hiker Biker Campsites
          group: [ ],
          rv: [ 73 ],			# 73: RV Campsites
          cabin: [ 76, 92 ]		# 76: Yurts - Cabins, 92: Yurts - Cabins, Pets OK
        }

        # Activity names that indicate camping available.

        CAMPING_ACTIVITY_NAMES = [ 'Cabin', 'Cabin (Accessible)',
                                   'Cabins/Yurts Pets OK', 'Cabins/Yurts Pets OK (Accessible)',
                                   'Camping', 'Camping (Accessible)',
                                   'Deluxe Cabin', 'Deluxe Cabin (Accessible)',
                                   'Deluxe Yurt', 'Deluxe Yurt (Accessible)',
                                   'Tepee',
                                   'Yurt', 'Yurt (Accessible)' ]

        # Activity names for listing activities.

        ACTIVITY_ACTIVITY_NAMES = [ 'Disc Golf',
                                    'Fishing', 'Fishing (Accessible)',
                                    'Hiker Biker',
                                    'Kayaking',
                                    'Picnicking', 'Picnicking (Accessible)',
                                    'Swimming',
                                    'Wildlife', 'Wildlife (Accessible)',
                                    'Windsurfing' ]

        # Activity names for listing amenities and facilities.

        AMENITY_ACTIVITY_NAMES = [ 'Ampitheater',
                                   'Beach Access', 'Beach Access (Accessible)',
                                   'Bike Path', 'Bike Path (Accessible)',
                                   'Boat Ramp',
                                   'Day-Use Fee',
                                   'Dump Station', 'Dump Station (Accessible)',
                                   'Hiking Trails', 'Hiking Trails (Accessible)',
                                   'Horse Trails',
                                   'Marina',
                                   'Open Year Round', 'Open Year Round (Accessible)',
                                   'Playground', 'Playground (Accessible)',
                                   'Reservable',
                                   'Viewpoint', 'Viewpoint (Accessible)' ]

        # Activity names for information center facilities.

        LEARNING_ACTIVITY_NAMES = [ 'Exhibit Information', 'Exhibit Information (Accessible)' ]

        # Activity names for restroom facilities.

        RESTROOM_ACTIVITY_NAMES = [ 'Restrooms Flush', 'Restrooms Flush (Accessible)',
                                    'Vault Toilets', 'Vault Toilets (Accessible)' ]

        # Activity names for water facilities.

        WATER_ACTIVITY_NAMES = [ 'Hot Shower', 'Hot Shower (Accessible)',
                                 'Potable Water' ]

        # @!visibility private
        ACTIVITY_MAP = {
          :campsite_types => CAMPING_ACTIVITY_NAMES,
          :activities => ACTIVITY_ACTIVITY_NAMES,
          :amenities => AMENITY_ACTIVITY_NAMES,
          :learning => LEARNING_ACTIVITY_NAMES,
          :restroom => RESTROOM_ACTIVITY_NAMES,
          :water => WATER_ACTIVITY_NAMES
        }

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::OR::StateParks::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          @_acts_map = {}
          @_enable_global_features = false
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # @!attribute [r] activity_map
        # A hash that, after a park list is loaded, contains the list of activities available in the
        # various state parks. The keys are activity names, and the values arrays that contain the
        # URL to the parks that offer that activity.
        # @return [Hash] Returns a hash as described above. The hash is rebuilt with each call
        #  to {build_park_list} or {build_overnight_park_list}.

        def activity_map()
          @_acts_map
        end

        # Extract the JSON fragment that contains the park list.
        # This method calls the query API to get the full list of parks.
        #
        # @param [Hash] rp A hash of request parameters. If this parameter is a hash with at least one
        #  key, the request is made using a +POST+ method, and these parameters are sent to the server;
        #  otherwise, +GET+ is used, and no parameters are sent down the pipe.
        #
        # @return [String, nil] Returns a string containing the park list, in JSON.
        #  Returns +nil+ if the call fails.
        #  Note that the value returned is the JSON string returned by the API call (minus the comment
        #  marker at the beginning). This JSON actually contains a hash with the following keys:
        #  - +SHOWMILES+ seems to be a flag that controlw display of miles (whatever that means).
        #  - +BADCITY+ also seems to be some kind of flag (maybe indicates that the requested city does
        #    not exist).
        #  - +PARKS+ is an array that contains the park list.
        #  - +MILERANGE+ is some control, maybe it's the radius for a distance search.

        def get_park_list_json(rp = nil)
          json = nil

          res = if rp.is_a?(Hash) && (rp.count > 0)
                  post(self.root_url + PARK_LIST_PATH + '?' + PARK_LIST_DATA_QUERY, rp, {
                        headers: {
                          'Accept' => 'application/json, text/javascript, */*; q=0.01'
                        }
                      })
                else
                  get(self.root_url + PARK_LIST_PATH + '?' + PARK_LIST_DATA_QUERY, {
                        headers: {
                          'Accept' => 'application/json, text/javascript, */*; q=0.01'
                        }
                      })
                end
          if res.is_a?(Net::HTTPOK)
            # the response is not technically legal JSON, since it starts with //: get rid of that

            json = (res.body.index('//') == 0) ? res.body[2, res.body.length] : res.body
          end

          json
        end

        # Extract the JSON fragment that contains the park list and convert it to Ruby.
        # This method calls {#get_park_list_json} and parses the result into Ruby; it then returns the
        # value of the +PARKS+ key.
        #
        # @param [Boolean] overnites_only If this parameter is set to +true+, only parks with overnight
        #  (campground) facilities are returned. If +false+, all parks are returned.
        # @param [Hash] rp A hash of request parameters that is passed to {#get_park_list_json}.
        #
        # @return [Array<Hash>, nil] Returns an array containing the park list.
        #  Returns +nil+ if it can't find it in the page.

        def get_park_list_raw(overnites_only = true, rp = nil)
          json = get_park_list_json(rp)
          unless json.nil?
            parsed = JSON.parse(json)
            if overnites_only
              parsed['PARKS'].select { |p| p['overNight'] == 1 }
            else
              parsed['PARKS']
            end
          else
            nil
          end
        end

        # Build the URL to the details page for a park.
        #
        # @param [Intger] park_id The park identifier.
        #
        # @return [String] Returns a string containing the URL to the park details page.

        def park_details_url(park_id)
          ROOT_URL + '/index.cfm?do=parkPage.dsp_parkPage&parkId=' + park_id.to_s
        end

        # Get the details page for a park.
        #
        # @param [Intger] park_id The park identifier.
        #
        # @return [Net::HTTPResponse] Returns a response object containing the response to the
        #  request for the page.

        def get_park_details_page(park_id)
          get(park_details_url(park_id),
              headers: {
                'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
              })
        end

        # Given a park list entry, build the park data.
        #
        # @param [Hash] ple The park list entry.
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the facilities list).
        #
        # @return [Hash] Returns a hash containing standardized information for the park.

        def build_park_data(ple, with_details = true)
          add = { }
          reservation_uri = nil

          if with_details
            res = get_park_details_page(ple['park_id'])
            if res.is_a?(Net::HTTPOK)
              doc = Nokogiri::HTML(res.body)

              pfl = extract_park_features(doc, res.uri)
              ACTIVITY_MAP.each do |ak, al|
                a = filter_activities(pfl, al)
                add[ak] = a.join(', ') if a.count > 0
              end

              reservation_uri = extract_park_reservation_uri(doc, res, ple)
            end
          end

          name = ple['park_name']

          cpd = {
            signature: "state/oregon/#{name.downcase}/#{name.downcase}",
            organization: ORGANIZATION_NAME,
            name: name,
            uri: park_details_url(ple['park_id']),
            region: REGION_NAME,
            area: '',
            location: {
              lat: ple['park_latitude'],
              lon: ple['park_longitude']
            },
            additional_info: add
          }

          cpd[:reservation_uri] = reservation_uri unless reservation_uri.nil?

          self.logger.info { "extracted park data for (#{cpd[:region]}) (#{cpd[:area]}) (#{cpd[:name]})" }
          cpd
        end

        # Extract the park list and generate standardized info from it.
        # This method calls {#get_park_list_raw} and builds a list of standardized park data from the
        # contents of the raw park list and the details pages.
        #
        # @param [Boolean] overnites_only If this parameter is set to +true+, only parks with overnight
        #  (campground) facilities are returned. If +false+, all parks are returned.
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the facilities list).
        #
        # @return [Array<Hash>, nil] Returns an array containing the standardized park data.
        #  Returns +nil+ if it can't find the park list.

        def build_park_list(overnites_only = true, with_details = true)
          _init_global_features()

          @_acts_map = {}

          rv = get_park_list_raw(overnites_only).map do |ple|
            build_park_data(ple, with_details)
          end
          if @_enable_global_features
            _global_features().keys.sort.each { |fk| self.output.printf("%-24s : #{_global_feature(fk)}\n", fk) }
          end

          rv
        end

        # Extract the park list for parks that support overnights, and generate standardized info from it.
        # This method calls {#get_park_list_raw} and builds a list of standardized park data from the
        # contents of the raw park list and the details pages.
        #
        # @param types [Array<Symbol>] An array listing the campsite types to include in the list; campgrounds
        #  that offer campsites from the list are added to the return set.
        #  A +nil+ value indicates that all camping types are to be included.
        #  See {Cf::Scrubber::Base::CAMPSITE_TYPES}.
        # @param with_details [Boolean] If +true+, look in the park's detail page for additional data
        #  (for example, for the facilities list).
        #
        # @return [Array<Hash>, nil] Returns an array containing the standardized park data.
        #  Returns +nil+ if it can't find the park list.

        def build_overnight_park_list(types = nil, with_details = true)
          _init_global_features()

          @_acts_map = {}

          # OK so we need to get the park list for all features needed.

          rp = {
            featureIds: -1,
            city: '',
            mileRanges: '10,20,30'
          }
          parks = [ ]
          park_types = { }
          tt = (types.is_a?(Array)) ? types : Cf::Scrubber::Base::CAMPSITE_TYPES
          tt.each do |t|
            st = t.to_sym
            if CAMPGROUND_TYPES_MAP.has_key?(st)
              CAMPGROUND_TYPES_MAP[st].each do |fid|
                rp[:featureIds] = fid
                get_park_list_raw(true, rp).each do |c|
                  cid = c['park_id']
                  pt = park_types[cid]
                  if pt
                    # Since the park was already picked up, all we need to do here is add the type

                    pt << st unless pt.include?(st)
                  else
                    # Not yet seen: push it on the park list and save its type

                    parks << c
                    park_types[cid] = [ st ]
                  end
                end
              end
            end
          end

          # OK at this point 'parks' has the list of park data, and 'park_types' their types, so we can
          # generate the park data

          rv = parks.map do |ple|
            cid = ple['park_id']
            pd = build_park_data(ple, with_details)
            pd[:types] = park_types[cid]
            pd
          end

          if @_enable_global_features
            _global_features().keys.sort.each { |fk| self.output.printf("%-24s : #{_global_feature(fk)}\n", fk) }
          end
          rv
        end

        private

        def filter_activities(fl, alist)
          fl.select { |a| alist.include?(a) }
        end

        def has_class(n, c)
          unless n['class'].nil?
            n['class'].split.each { |e| return true if e == c }
          end
          false
        end

        def scan_park_features(cn, park_uri)
          pf = [ ]
          cn.css('div.park-icons div.park-icon').each do |pi|
            an = pi.css('a.icon').first
            act = an['data-original-title'] || an['title']
            if act
              pf << act
              if @_acts_map.has_key?(act)
                @_acts_map[act] << park_uri
              else
                @_acts_map[act] = [ park_uri ]
              end
              self.logger.warn("unregistered activity: #{act}") unless ACTIVITY_NAMES.include?(act)

              if pi['class'].downcase.split.include?('accessible')
                aact = act + ' (Accessible)'
                pf << aact
                if @_acts_map.has_key?(aact)
                  @_acts_map[aact] << park_uri
                else
                  @_acts_map[aact] = [ park_uri ]
                end
                self.logger.warn("unregistered activity: #{aact}") unless ACTIVITY_NAMES.include?(aact)
              end
            end
          end

          pf
        end

        def extract_park_features(doc, park_uri)
          nts = doc.css('div.next-to-sidebar > #park-carousel')
          if nts.count > 0
            cn = nts[0].next_sibling
            while cn
              if has_class(cn, 'hidden-print')
                return scan_park_features(cn, park_uri)
              end
              cn = cn.next_sibling
            end
          end

          [ ]
        end

        def extract_park_reservation_uri(doc, res, pd)
          res_a = doc.css('div.sidebar-wrapper a.sidebar-button-reserve')
          if res_a.length > 0
            na = res_a[0]
            return na['href']
          end

          nil
        end

        # These methods are used to build the features list

        def _init_global_features()
          @_global_features = {}
        end

        def _add_global_feature(f)
          fid = f[:id]
          if @_global_features.has_key?(fid)
            unless @_global_features[fid].include?(f[:name])
              @_global_features[fid] << f[:name]
            end
          else
            @_global_features[fid] = [ f[:name] ]
          end
        end

        def _global_features()
          @_global_features
        end

        def _global_feature(fk)
          @_global_features[fk]
        end
      end
    end
  end
end
