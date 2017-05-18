require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

require 'cf/scrubber/base'

module Cf
  module Scrubber
    # The namespace for scrubbers for CO sites.

    module Co
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Colorado State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the CO State Park System, which is part of CO)

        ORGANIZATION_NAME = 'co:state'

        # The (fixed) region name is +Colorado+, since these are CO state parks.

        REGION_NAME = 'Colorado'

        # The URL of the CO State Park System web site.

        ROOT_URL = 'http://cpw.state.co.us'

        # The path in the web site for the index page.

        INDEX_PATH = '/placestogo/parks'

        # The partial URL of the section page containing directions to the park.
        MAP_URL = 'Pages/MapsDirections.aspx'

        # The names of the section page containing directions to the park.
        MAP_MENU = [ 'Maps and Directions', MAP_URL ]

        # The partial URL of the section page containing the list of facilities for the park.
        FACILITIES_URL = 'Pages/Facilities.aspx'

        # The names of the section page containing the list of facilities for the park.
        FACILITIES_MENU = [ 'Park Facilities', 'SWA Facilities', FACILITIES_URL ]

        # The partial URL of the section page containing the list of activities for the park.
        ACTIVITIES_URL = 'Pages/Activities.aspx'

        # The name of the section page containing the list of activities for the park.
        ACTIVITIES_MENU = [ 'Park Activities', 'SWA Activities', ACTIVITIES_URL ]

        # The partial URL of the section page containing camping information.
        CAMPING_URL = 'Pages/Camping.aspx'

        # The names of the section page containing camping information.
        CAMPING_MENU = [ 'Camping', CAMPING_URL ]

        # The list of known facilities.

        FACILITIES = {
          'Accessible Facilities' => nil,	# ignore
          'Amphitheater' => {},
          'Archery Range' => {},
          'Boat Ramps' => {},
          'Cabins and Yurts' => {},
          'Camper Services Building' => {},
          'Campgrounds' => {},
          'Conference Rooms' => {},
          'Duck Blinds' => {},
          'Dump Station' => {},
          'Entrance Station' => nil,		# ignored
          'Event Facilities' => nil,		# ignored
          'Fishing Piers' => {},
          'Food Service' => nil,		# ignored
          'Group Campground' => {},
          'Group Picnic Area' => {},
          'Horse Trailer Parking' => {
            no: [ Regexp.new('no facilities', Regexp::IGNORECASE) ]
          },
          'Marina' => {},
          'Model Airplane Field' => nil,	# ignored
          'Park Office' => nil,			# ignored
          'Picnic Sites' => {},
          'Playground' => {},
          'Retail Store' => {},
          'Showers' => {
            no: [ Regexp.new('no showers', Regexp::IGNORECASE) ]
          },
          'Shooting Range' => {},
          'Swim Beach' => {},
          'Stables or Corrals' => nil,		# ignored
          'Trails' => {},
          'Visitor Center' => {},
          'Visitor Center Overlook' => {},
          'Wedding Facilities' => nil		# ignored
        }

        # The facilities that indicate the presence of a given accommodation type.

        CAMPGROUND_FACILITIES = {
          Cf::Scrubber::Base::TYPE_STANDARD => [ 'Campgrounds' ],
          Cf::Scrubber::Base::TYPE_GROUP => [ 'Group Campground' ],
          Cf::Scrubber::Base::TYPE_CABIN => [ 'Cabins and Yurts' ],
          Cf::Scrubber::Base::TYPE_RV => [ ]
        }

        # The list of known activities.

        ACTIVITIES = {
          'Archery' => {},
          'Backcountry camping' => {},
          'Biking' => {},
          'Birding' => {},
          'Boating' => {},
          'Cabins and Yurts' => nil,		# ignored
          'Camping' => {
            no: [ Regexp.new('no camping', Regexp::IGNORECASE) ]
          },
          'Cross-country Skiing' => {},
          'Dog-friendly' => {},
          'Education Programs' => {},
          'Equipment Rental' => {},
          'Fishing' => {},
          'Geocaching' => {},
          'Gold Panning' => {},
          'Golfing' => nil,			# ignored
          'Group Camping' => {},
          'Group Picnicking' => {},
          'Hiking' => {},
          'Horseback Riding' => {},
          'Hot-Air Ballooning' => {},
          'Hunting' => {},
          'Ice Fishing' => {},
          'Ice Skating' => {},
          'Jet Skiing' => {},
          'Model Airplane Flying' => {},
          'OHV Riding' => {},
          'Paddle Boarding' => {},
          'Photography' => {},
          'Picnicking' => {},
          'Rock Climbing' => {},
          'Sailboarding' => {},
          'Sailing' => {},
          'Sledding' => {},
          'Snowmobiling' => {},
          'Snowshoeing' => {},
          'Snowtubing' => {},
          'Swimming' => {},
          'Volleyball' => {},
          'Water Skiing' => {},
          'Whitewater rafting' => {},
          'Wildlife Viewing' => {},
          'Winter Activities' => {},
          'Winter Camping' => {}
        }

        # The activities that indicate the presence of a given accommodation type.

        CAMPGROUND_ACTIVITIES = {
          Cf::Scrubber::Base::TYPE_STANDARD => [ 'Backcountry camping', 'Camping', 'Group Camping',
                                                 'Winter Camping' ],
          Cf::Scrubber::Base::TYPE_GROUP => [ 'Group Camping' ],
          Cf::Scrubber::Base::TYPE_CABIN => [ 'Cabins and Yurts' ],
          Cf::Scrubber::Base::TYPE_RV => [ ]
        }

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::Usda::NationalForestService::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # Build the park list from the contents of the park list selector in the index page.
        # Note that this method loads just local data, and clients will have to call
        # {#extract_park_details} in order to have a fully populated set.
        #
        # This list includes all parks in the CO State Parks system, including those that may not provide
        # campground facilities.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing local park data
        #  (data that can be extracted from the park index page).
        #  Returns +nil+ if it can't find it in the page.
        #  The local park data contain the following standard key/value pairs:
        #  - *:organization* Is +co:parks+.
        #  - *:name* The park name.
        #  - *:uri* The URL to the park's details page.
        #  - *:region* The string +Colorado+.
        #  - *:area* An empty string.

        def get_park_list()
          extract_park_list(self.root_url + INDEX_PATH)
        end

        # Given a park's local data, get the park details from the details page.
        #
        # @param [Hash] lpd The park local data, as returned by {#get_park_list}.
        # @param [Boolean] logit Set to +true+ to log an info line that the park data were fetched.
        #
        # @return [Hash] Returns a hash containing park data that was extracted from the park detail page:
        #  - *:name* A string containing a more complete name for the park.
        #  - *:types* An array listing the types of campsites in the campground; often this will be a one
        #    element array, but some campgrounds have multiple site types.
        #  - *:reservation_uri* The URL to the reservation page, if one is available.
        #  - *:location* The geographic coordinates of the campground: *:lat*, *:lon*, and *:elevation*.
        #  - *:amenities* The (HTML) contents of the "Accomodations and Facilities" section.
        #  - *:things_to_do* The (HTML) contents of the "Things To Do & See" section.

        def get_park_details(lpd, logit = false)
          res = get(lpd[:uri], {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            details = extract_park_details(doc, lpd)

            if logit
              self.logger.info { "extracted park data for (#{lpd[:region]}) (#{lpd[:area]}) (#{lpd[:name]})" }
            end

            details
          else
            self.logger.warn { "failed to extract park data for (#{lpd[:region]}) (#{lpd[:area]}) (#{lpd[:name]})" }
            { }
          end
        end

        # Build a full list of parks.
        # This method puts together the partial info methods {#get_park_list} and {#get_park_details} as
        # follows:
        # 1. Call {#get_park_list} to build the park list.
        # 2. For each park, call {#get_park_details} and merge the result value into the park data.
        #    - *:location*, *:reservation_uri*, and *:types* go in the park data.
        #    - *:facilities* and *:activities* go in the *:additional_info* entry.
        #
        # @param [Array<Hash>] parks An array of park data, typically as returned by {#get_park_list}.
        #  If +nil+, initialize it via a call to {#get_park_list}.
        # @param [Boolean] logit If +true+, log an info line for each park found.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the park data. Each contains
        #  the keys returned by {#get_park_list} and by {#get_park_details}, and the following keys:
        #  - *:activities* is the list of activities provided by the park.

        def build_full_park_list(parks = nil, logit = false)
          # 1. park list

          parks = get_park_list() if parks.nil?

          # 2. park details

          parks.each do |p|
            details = get_park_details(p, logit)
            [ :location, :types, :reservation_uri ].each do |k|
              p[k] = details[k] if details.has_key?(k)
            end

            p[:additional_info] = { } unless p[:additional_info].is_a?(Hash)
            [ :activities, :facilities ]. each do |k|
              p[:additional_info][k] = details[k] if details.has_key?(k)
            end

            if logit
              self.logger.info { "filled park data for (#{p[:region]}) (#{p[:area]}) (#{p[:name]})" }
            end
          end

          parks
        end

        private

        def get_park_page(url)
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            Nokogiri::HTML(res.body)
          else
            nil
          end
        end

        def extract_park_list(url)
          plist = []
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("#ParksSelect select#ParkList option").each do |nc|
              if nc['value'] != '/'
                plist << {
                  organization: ORGANIZATION_NAME,
                  name: nc.text().strip,
                  uri: adjust_href(nc['value'], ROOT_URL),
                  region: REGION_NAME,
                  area: ''
                }
              end
            end
          end

          plist
        end

        def extract_park_details(doc, ldata)
          rv = { }

          rootmenu = doc.css("#sideNavBox ul.root").first
          n = doc.css("#cpw_parkpage div.article-left div.article-header div.cpw_pagetitle").first
          if n
            rv[:name] = n.text().strip
          else
            # here we could try looking it up in the left sidebar (rootmenu)
          end

          if rootmenu
            navmenu = rootmenu.css("ul.static").first
            if navmenu
              loc = extract_location(navmenu, ldata)
              rv[:location] = loc unless loc.nil?
            end
          end

          reservation_url = extract_reservation_url(navmenu, ldata)
          rv[:reservation_uri] = reservation_url unless reservation_url.nil?

          facilities = extract_facilities(navmenu, ldata)
          if facilities.nil?
            self.logger.warn { "no facilities found in (#{ldata[:region]}) (#{ldata[:area]}) (#{ldata[:name]})" }
          else
            rv[:facilities] = facilities.join(', ')
          end

          activities = extract_activities(navmenu, ldata)
          if activities.nil?
            self.logger.warn { "no activities found in (#{ldata[:region]}) (#{ldata[:area]}) (#{ldata[:name]})" }
          else
            rv[:activities] = activities.join(', ')
          end

          # from activities and facilities, we can figure out what accommodations
          # the park supports, except that it's impossible to figure out if RV camping is supported
          # (which it mostly is in the parks).
          # To do that, possibly our best bet is to look into reserveamerica.

          types = [ ]

          # first, we use activities to pick up types based on the activity (obviously...)
          # We do this first because we then check if facilities contain a corresponding facility.
          # For example, a park may list "Camping" in the activities, but only to say that camping is
          # NOT allowed (El Dorado Canyon, for example).
          # This may cause types to be added when they should not be; we'll try to fix that in the facilities
          # loop, later

          if activities
            CAMPGROUND_ACTIVITIES.each do |tk, tv|
              types << tk if ((activities & tv).count > 0) && !types.include?(tk)
            end
          end

          if facilities
            # first of all, try to remove spurious types (see comments above).
            # we do this by looking at facilities that are necessary for each type: if none are present,
            # then we remove that type
            #
            # This is still not perfect, because some parks list "group camping" as an activity and describe
            # a group campground area, but then don't list "group campground" in the facilities, and they
            # should. But we'll deal with this later.

            tl = types.select do |t|
              # if the intersection between the available facilities and the required facilities is not empty,
              # there does seem to be a required facility available, so we keep the type
              
              (CAMPGROUND_FACILITIES[t] & facilities).count > 0
            end
            types = tl

            # Now we can add types based on the facilities

            CAMPGROUND_FACILITIES.each do |tk, tv|
              types << tk if ((facilities & tv).count > 0) && !types.include?(tk)
            end
          end

          # If there is reservation URL, and there are types listed, let's see if the park supports RVs. 
          # Unfortunately there does not seem to be a way to gather thatother than by reading the facilites
          # descriptions. However, with the reservation URl we can try hitting reserveamerica and ask for
          # RV sites

          if (types.count > 0) && !reservation_url.nil?
            types << Cf::Scrubber::Base::TYPE_RV if has_rv_sites?(reservation_url)
          end

          rv[:types] = types

          rv
        end

        def find_menu_item(navmenu, label, cpd)
          if label.is_a?(Array)
            ll = label[0, label.count-1]
            pg = label.last
          else
            ll = [ label ]
            pg = nil
          end

          navmenu.css('li a').each do |n|
            sn = n.css('span span').first
            if sn
              txt = sn.text().strip
              ll.each do |l|
                return adjust_href(n['href'], cpd[:uri]) if txt == l
              end
            end
          end

          (pg.nil?) ? nil : adjust_href(pg, cpd[:uri])
        end

        def extract_location(navmenu, cpd)
          url = find_menu_item(navmenu, MAP_MENU, cpd)
          if url
            doc = get_park_page(url)
            iframe = doc.css('div.article-content iframe').first
            if iframe
              src_uri = URI::parse(iframe['src'])
              qp = src_uri.query.split('&').find { |p| p.start_with?('pb=') }
              if qp
                ll = qp.split('!').select { |p| p.start_with?('2d') || p.start_with?('3d') }
                if ll.count == 2
                  # 2d is longitude, 3d latitude

                  if ll.first.start_with?('2d')
                    lat = ll.last[2,ll.last.length]
                    lon = ll.first[2,ll.first.length]
                  else
                    lat = ll.first[2,ll.first.length]
                    lon = ll.last[2,ll.last.length]
                  end

                  return { lat: lat, lon: lon }
                end
              end
            end
          end

          nil
        end

        def detail_ok?(nli, f, details)
          fac = details[f]
          return false if fac.nil?

          if fac.has_key?(:no)
            desc = nli.css('div.description > div').first.text()
            fac[:no].each do |re|
              return false if desc =~ re
            end
          end
             
          true
        end

        def extract_details(label, details, navmenu, cpd)
          flist = nil
          url = find_menu_item(navmenu, label, cpd)
          if url
            doc = get_park_page(url)
            if doc
              flist = [ ]
              doc.css('div#mainbody div.article-content ul.dfwp-list li').each do |nli|
                nh2 = nli.css('h2').first
                if nh2
                  f = nh2.text().strip
                  if details.has_key?(f)
                    flist << f if detail_ok?(nli, f, details)
                  else
                    self.logger.warn { "unknown detail (#{label}) '#{f}' in (#{cpd[:region]}) (#{cpd[:area]}) (#{cpd[:name]})" }
                  end
                end
              end
            end
          end

          flist
        end

        def extract_facilities(navmenu, cpd, label = FACILITIES_MENU)
          extract_details(label, FACILITIES, navmenu, cpd)
        end

        def extract_activities(navmenu, cpd, label = ACTIVITIES_MENU)
          extract_details(label, ACTIVITIES, navmenu, cpd)
        end

        def extract_reservation_url(navmenu, cpd)
          url = find_menu_item(navmenu, CAMPING_MENU, cpd)
          if url
            doc = get_park_page(url)
            if doc
              doc.css('#cpw_zone-sidebar2 a').each do |na|
                # we rely on the fact that the park system uses reserveamerica for their reservations
                if na['href'] =~ /reserveamerica/
                  # we accept a reservation URL only if it contains a query string (which we assume contains
                  # the contractCode and parkId)

                  ruri = URI.parse(na['href'])
                  return na['href'] unless ruri.query.nil?
                end
              end
            end
          end

          nil
        end

        RESERVEAMERICA_CAMPSITE_SEARCH_PATH = '/campsiteSearch.do'

        def has_rv_sites?(reservation_url)
          puri = URI.parse(reservation_url)
          surl = "https://#{puri.host}#{RESERVEAMERICA_CAMPSITE_SEARCH_PATH}?#{puri.query}"

          # 2001 is the code for RV sites
          # parkId and contractCode should come from the reservation URL

          params = {
            siteType: 2001,
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

          puri.query.split('&') do |q|
            qk, qv = q.split('=')
            params[qk.to_sym] = qv
          end

          res = post(surl, params, {
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
end
