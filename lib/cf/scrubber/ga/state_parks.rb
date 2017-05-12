require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

require 'cf/scrubber/base'

module Cf
  module Scrubber
    # The namespace for scrubbers for GA sites.

    module Ga
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Georgia State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the GA State Park System, which is part of GA)

        ORGANIZATION_NAME = 'ga:state'

        # The (fixed) region name is +Georgia+, since these are GA state parks.

        REGION_NAME = 'Georgia'

        # The URL of the GA State Park System web site

        ROOT_URL = 'http://gastateparks.org'

        # The path in the web site for the index page

        INDEX_PATH = '/parks'

        # The path in the web site for the activities page

        ACTIVITIES_PATH = '/activities'

        # All activity codes and their names. The activity codes double as paths in the web site for
        # the page listing parks that provide tat activity.

        ACTIVITY_CODES = {
          'archery' => 'Archery',
          'biking' => 'Biking',
          'boating' => 'Boating',
          'camping' => 'Camping',
          'disc-golf' => 'Disc Golf',
          'dog-walking' => 'Dog Walking',
          'equestrian' => 'Equestrian',
          'family-fun' => 'Family Fun',
          'fishing' => 'Fishing',
          'geocaching' => 'Geocaching',
          'golfing' => 'Golfing',
          'hiddengems' => 'Hidden Gems',
          'hiking' => 'Hiking',
          'history' => 'Historic Sites',
          'nature-watching' => 'Nature Watching',
          'paddling' => 'Canoeing and Kayaking',
          'rv' => 'RVs',
          'swimming' => 'Swimming'
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

        # Build the park list from the contents of the park list items in the index page.
        # Note that this method loads just the local data, and clients will have to call
        # {#extract_details_park_data} in order to have a fully populated set.
        # The reason we split this is to avoid fetching detail pages for parks that may be dropped by
        # a filter later.
        #
        # This list includes all parks in the GA State Parks system, including those that may not provide
        # campground facilities.
        #
        # @param [Boolean] logit If +true+, log an info line for each park found.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the local park data
        #  (data that can be extracted from the park index page).
        #  Returns +nil+ if it can't find it in the page.
        #  The local park data contain the following standard key/value pairs:
        #  - *:organization* Is +ga:parks+.
        #  - *:name* The campground name.
        #  - *:uri* The URL to the campground's details page.
        #  - *:region* The string +Georgia+.
        #  - *:area* An empty string.
        #  - *:types* An array listing the types of campsites in the campground; often this will be a one
        #    element array, but some campgrounds have multiple site types.
        #  - *:reservation_url* The URL to the reservation page, if one is available.

        def get_park_list(logit = false)
          extract_park_list(self.root_url + INDEX_PATH, logit)
        end

        # Get the list of activities and the parks that provide them.
        # This method parses the HTML returned by the activities page, loops over all entries in the
        # activities menu, loads the activities page and scans the park list.
        #
        # @return [Hash] Returns a hash where the keys are activity names, and the values are hashes containing
        #  two key/value pairs: *:name* is the activity name, and *:parks* is an array containing
        #  the URIs to parks that provide the activity.

        def get_activity_list()
          rv = { }
          res = get(self.root_url + ACTIVITIES_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("#main #activityMenu > a").map do |na|
              pkey = na['href']
              pkey = pkey[1,pkey.length] if pkey[0] == '/'
              plist = extract_park_list(self.root_url + '/' + pkey, false)
              rv[pkey] = {
                name: ACTIVITY_CODES[pkey],
                parks: plist.map { |p| p[:uri] }
              }
            end
          end

          rv
        end

        # Given a park's local data, get the park details from the details page.
        #
        # @param [Hash] data The park local data, as returned by {#get_park_list}.
        #
        # @return [Hash] Returns a hash containing park data that was extracted from the park detail page:
        #  - *:location* The geographic coordinates of the campground: *:lat*, *:lon*, and *:elevation*.
        #  - *:amenities* The (HTML) contents of the "Accomodations and Facilities" section.
        #  - *:things_to_do* The (HTML) contents of the "Things To Do & See" section.

        def get_park_details(data)
          res = get(self.root_url + data[:uri], {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            extract_park_details(doc, res)
          else
            { }
          end
        end

        # Build a full list of parks.
        # This method puts together the partial info methods {#get_park_list}, {#get_activity_list},
        # and {#get_park_details} as follows:
        # 1. Call {#get_park_list} to build the park list.
        # 2. Call {#get_activity_list} to build the list of activities, and generate a reverse map from
        #    park URI to list of activities.
        # 3. For each park, call {#get_park_details} and merge the result value into the park data.
        #    - *:location* goes in the park data
        #    - *:amenities* and *:things_to_do* go in the *:additional_info* entry.
        # 4. Then add the activity list for the park from step 2; this is added as the *:activities* key
        #    in the *:additional_info* entry.
        # 5. Add the RV accommodation type to the park if the park is in the RV activitiy list.
        # 6. And adjust the park URI to include the root URL.
        #
        # @param [Array<Hash>] parks An array of park data, typically as returned by {#get_park_list}.
        #  If +nil+, initialize it via a call to {#get_park_list}.
        # @param [Boolean] login If +true+, log an info line for each park found.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the park data. Each contains
        #  the keys returned by {#get_park_list} and by {#get_park_details}, and the following keys:
        #  - *:activities* is the list of activities provided by the park.

        def build_full_park_list(parks = nil, logit = false)
          # 1. park list and park map

          parks = get_park_list(logit) if parks.nil?
          parks_map = { }
          parks.each { |p| parks_map[p[:uri]] = p }

          # 2. activity list and reverse map

          activities = get_activity_list
          park_activities = { }
          activities.each do |ak, av|
            av[:parks].each do |p|
              if park_activities.has_key?(p)
                park_activities[p] << ak
              else
                park_activities[p] = [ ak ]
              end
            end
          end

          # 3. park details, 4. activity lists, 5. RV type, 6. adjust URI

          parks.each do |p|
            details = get_park_details(p)
            p[:location] = details[:location] if details.has_key?(:location)

            p[:additional_info] = { } unless p[:additional_info].is_a?(Hash)
            [ :amenities, :things_to_do ]. each do |k|
              p[:additional_info][k] = details[k] if details.has_key?(k)
            end

            p[:additional_info][:activities] = (park_activities[p[:uri]].map { |ak| activities[ak][:name] }).join(', ')

            if activities['rv'].include?(p[:uri])
              p[:types] << Cf::Scrubber::Base::TYPE_RV unless p[:types].include?(Cf::Scrubber::Base::TYPE_RV)
            end

            if p[:uri][0] == '/'
              p[:uri] = self.root_url + p[:uri]
            end
          end

          parks
        end

        private

        def extract_reservation_url(nc)
          nodes = nc.css(".resTop a[class~=resButton]")
          if nodes.count > 0
            nodes[0]['href']
          else
            nil
          end
        end

        def extract_park_name(nc)
          pn = nc.css(".resTop .showLinks .parkTitle")[0]
          pn.text();
        end

        def extract_park_url(nc)
          nc.css(".allReservables > a")[0]['href']
        end

        def extract_camp_types(nc)
          # note that for RV facilities we will have to go the activities route

          types = {}
          nc.css(".allReservables > span").each do |nr|
            a = nr.css('a')[0]
            if a
              t = a.text()
              if (t =~ /Cottage/) || (t =~ /Lodge Room/) || (t =~ /Yurt/) || (t =~ /Other Overnight/) || (t =~ /Cabin/)
                types[Cf::Scrubber::Base::TYPE_CABIN] = true
              elsif (t =~ /Campsite/) || (t =~ /Backcountry/)
                types[Cf::Scrubber::Base::TYPE_STANDARD] = true
              elsif (t =~ /Group Camp/) || (t =~ /Pioneer Camp/)
                types[Cf::Scrubber::Base::TYPE_GROUP] = true
              end
            end
          end

          types.keys
        end

        def extract_local_park_data(nc, res)
          cpd = {
            organization: ORGANIZATION_NAME,
            name: extract_park_name(nc),
            uri: extract_park_url(nc),
            types: extract_camp_types(nc),
            region: REGION_NAME,
            area: '',
            reservation_url: extract_reservation_url(nc)
          }

          cpd
        end

        def extract_park_list(url, logit = false)
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("#ChartPanel > div.resSet").map do |nc|
              cpd = extract_local_park_data(nc, res)
              if logit
                self.logger.info { "extracted local park data for (#{cpd[:region]}) (#{cpd[:area]}) (#{cpd[:name]})" }
              end
              cpd
            end
          else
            [ ]
          end
        end

        def extract_park_details(doc, res)
          rv = { }

          loc = extract_location(doc, res)
          rv[:location] = loc unless loc.nil?

          amenities = extract_amenities(doc, res)
          rv[:amenities] = amenities unless amenities.nil?()

          todo = extract_todo(doc, res)
          rv[:things_to_do] = todo unless todo.nil?()

          rv
        end

        def extract_location(doc, res)
          # this is the anchor to the directions section. The next div element is the container for the
          # directions, including GPS coordinates.

          anchor = doc.css("#directions")[0]
          if anchor
            main = anchor
            while main && (main.name != 'div') do
              main = main.next_sibling
            end

            if main
              main.css('h3').each do |h3n|
                if h3n.text() =~ /GPS Coord/
                  tn = h3n.next_sibling
                  txt = tn.text()
                  if txt =~ /N\s+([+-]?[0-9]+\.[0-9]+)\s+\|\s+W\s+([+-]?[0-9]+\.[0-9]+)/
                    m = Regexp.last_match
                    return { lat: m[1], lon: m[2] }
                  end
                end
              end
            end
          end

          nil
        end

        def extract_amenities(doc, res)
          c = doc.css('#leftColumn')[0]
          (c.nil?) ? nil : extract_named_section(c, /Accommodations/)
        end

        def extract_todo(doc, res)
          c = doc.css('#leftColumn')[0]
          (c.nil?) ? nil : extract_named_section(c, /Things To Do/)
        end

        def extract_named_section(container, name)
          re = if name.is_a?(Regexp)
                 name
               else
                 Regexp.new("^#{name}$")
               end

          container.css("h3").each do |h3n|
            if h3n.text() =~ re
              doc = Nokogiri::HTML::Document.new('')
              xn = Nokogiri::XML::NodeSet.new(doc)
              cn = h3n.next_sibling
              while cn.name != 'hr' do
                ccn = cn.dup
                if ccn.element?
                  if ccn.name == 'a'
                    # all the links are set up to open in a new window

                    href = ccn['href']
                    ccn['href'] = self.root_url + href if href[0] == '/'
                    ccn['target'] = '_blank'
                  elsif ccn.name == 'img'
                    src = ccn['src']
                    ccn['src'] = self.root_url + src if src[0] == '/'
                  end
                end
                xn.push(ccn)

                cn = cn.next_sibling
              end

              return xn.to_html
            end
          end

          nil
        end
      end
    end
  end
end
