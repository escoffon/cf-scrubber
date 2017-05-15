require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

module Cf
  module Scrubber
    # The namespace for scrubbers for OR sites.

    module Or
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

        # All activity codes and their names.

        ACTIVITY_CODES = {
          'ampitheater' => 'Ampitheater',
          'beach' => 'Beach Access',
          'beach-ada' => 'Beach Access (ADA)',
          'bike' => 'Bike Path',
          'bike-ada' => 'Bike Path (ADA)',
          'boat' => 'Boat Ramp',
          'boat-ada' => 'Boat Ramp (ADA)',
          'cabin' => 'Cabin',
          'cabin-ada' => 'Cabin (ADA)',
          'camping' => 'Camping',
          'camping-ada' => 'Camping (ADA)',
          'dayuse' => 'Day-Use Fee',
          'deluxecabin' => 'Deluxe Cabin',
          'deluxecabin-ada' => 'Deluxe Cabin (ADA)',
          'deluxeyurt-ada' => 'Deluxe Yurt (ADA)',
          'disc' => 'Disc Golf',
          'dump' => 'Dump Station',
          'dump-ada' => 'Dump Station (ADA)',
          'exhibit' => 'Exhibit Information',
          'exhibit-ada' => 'Exhibit Information (ADA)',
          'fishing' => 'Fishing',
          'fishing-ada' => 'Fishing (ADA)',
          'hiker' => 'Hiker Biker',
          'hiking' => 'Hiking Trails',
          'hiking-ada' => 'Hiking Trails (ADA)',
          'horse' => 'Horse Trails',
          'kayak' => 'Kayaking',
          'marina' => 'Marina',
          'pet' => 'Cabins/Yurts Pets OK',
          'pet-ada' => 'Cabins/Yurts Pets OK (ADA)',
          'picnic' => 'Picnicking',
          'picnic-ada' => 'Picnicking (ADA)',
          'pit' => 'Pit Toilets',
          'pit-ada' => 'Pit Toilets (ADA)',
          'playground' => 'Playground',
          'playground-ada' => 'Playground (ADA)',
          'potable' => 'Potable Water',
          'potable-ada' => 'Potable Water (ADA)',
          'reservable' => 'Reservable',
          'restrooms' => 'Restrooms Flush',
          'restrooms-ada' => 'Restrooms Flush (ADA)',
          'shower' => 'Hot Shower',
          'shower-ada' => 'Hot Shower (ADA)',
          'swimming' => 'Swimming',
          'tepee' => 'Tepee',
          'tepee-ada' => 'Tepee (ADA)',
          'vault' => 'Vault Toilets',
          'vault-ada' => 'Vault Toilets (ADA)',
          'viewpoint' => 'Viewpoint',
          'viewpoint-ada' => 'Viewpoint (ADA)',
          'wildlife' => 'Wildlife',
          'wildlife-ada' => 'Wildlife (ADA)',
          'windsurfing' => 'Windsurfing',
          'yearround' => 'Open Year Round',
          'yearround-ada' => 'Open Year Round (ADA)',
          'yurt' => 'Yurt',
          'yurt-ada' => 'Yurt (ADA)'
        }

        # Map of feature codes to campground types.

        CAMPGROUND_TYPES_MAP = {
          standard: [ 74, 75 ],		# 74: Tent Campsites, 75: Hiker Biker Campsites
          group: [ ],
          rv: [ 73 ],			# 73: RV Campsites
          cabin: [ 76, 92 ]		# 76: Yurts - Cabins, 92: Yurts - Cabins, Pets OK
        }

        # Activity codes that indicate camping available.

        CAMPING_ACTIVITY_CODES = [ 'cabin', 'cabin-ada', 'camping', 'camping-ada',
                                   'deluxecabin', 'deluxecabin-ada', 'deluxeyurt-ada', 'pet', 'pet-ada',
                                   # 'reservable',
                                   'tepee', 'tepee-ada', 'yurt', 'yurt-ada' ]

        # Activity codes for listing activities.

        ACTIVITY_ACTIVITY_CODES = [ 'dayuse', 'disc', 'fishing', 'fishing-ada', 'hiker',
                                    'hiking', 'hiking-ada', 'kayak', 'picnic', 'picnic-ada', 'swimming',
                                    'wildlife', 'wildlife-ada', 'windsurfing' ]

        # Activity codes for listing amenities.

        AMENITY_ACTIVITY_CODES = [ 'ampitheater', 'beach', 'beach-ada', 'bike', 'bike-ada', 'boat', 'boat-ada',
                                   'dump', 'dump-ada', 'horse', 'marina', 'playground', 'playground-ada',
                                   # 'reservable',
                                   'viewpoint', 'viewpoint-ada', 'yearround', 'yearround-ada' ]

        # Activity codes for information center facilities.

        LEARNING_ACTIVITY_CODES = [ 'exhibit', 'exhibit-ada' ]

        # Activity codes for restroom facilities.

        RESTROOM_ACTIVITY_CODES = [ 'pit', 'pit-ada', 'restrooms', 'restrooms-ada', 'vault', 'vault-ada' ]

        # Activity codes for water facilities.

        WATER_ACTIVITY_CODES = [ 'potable', 'potable-ada', 'shower', 'shower-ada' ]

        # @!visibility private
        ACTIVITY_MAP = {
          :campsite_types => CAMPING_ACTIVITY_CODES,
          :activities => ACTIVITY_ACTIVITY_CODES,
          :amenities => AMENITY_ACTIVITY_CODES,
          :learning => LEARNING_ACTIVITY_CODES,
          :restroom => RESTROOM_ACTIVITY_CODES,
          :water => WATER_ACTIVITY_CODES
        }

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::Or::StateParks::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          @_enable_global_features = false
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
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
                a = list_activities(pfl, al)
                add[ak] = a.join(', ') if a.count > 0
              end

              reservation_uri = extract_park_reservation_uri(doc, res, ple)
            end
          end

          cpd = {
            organization: ORGANIZATION_NAME,
            name: ple['park_name'],
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

        def has_activity?(fl, aid)
          fl.include?(aid)
        end

        def list_activities(fl, alist)
          l = [ ]
          alist.each do |e|
            l << ACTIVITY_CODES[e] if has_activity?(fl, e)
          end

          l
        end

        def has_class(n, c)
          unless n['class'].nil?
            n['class'].split.each { |e| return true if e == c }
          end
          false
        end

        def scan_park_features(cn, park_uri)
          pf = [ ]
          cn.css('p.clearfix a.park-guide-icon').each do |an|
            an['class'].split.each do |e|
              if e.index('park-guide-icon-') == 0
                fid = e[16, e.length]
                unless ACTIVITY_CODES.has_key?(fid)
                  self.logger.warn { "unknown activity code (#{fid}) for park at (#{park_uri})" }
                end

                f = { id: fid, name: an['title'] }
                _add_global_feature(f)
                pf << fid
                break
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
