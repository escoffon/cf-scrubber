require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

module Cf
  module Scrubber
    # The namespace for scrubbers for NV sites.

    module Nv
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Nevada State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the CA State Park System, which is part of CA)

        ORGANIZATION_NAME = 'nv:state'

        # The (fixed) region name is +Nevada+, since these are NV state parks.

        REGION_NAME = 'Nevada'

        # The URL of the NV State Park System web site

        ROOT_URL = 'http://parks.nv.gov'

        # The path in the web site for the index page

        INDEX_PATH = '/parks'

        # All activity codes and their names.

        ACTIVITY_CODES = {
          'ada-campsites' => 'ADA Campsites',
          'bike-trails' => 'Bike Trails',
          'bird-watching' => 'Bird Watching',
          'boat-launch' => 'Boat Launch',
          'cabins-yurts' => 'Cabins/Yurts',
          'campsites' => 'Campsites',
          'canoeing-water-sports' => 'Canoeing / Water Sports',
          'drinking-water' => 'Drinking Water',
          'equestrian' => 'Equestrian',
          'fishing' => 'Fishing',
          'gift-shop' => 'Gift Shop',
          'hiking' => 'Hiking',
          'historic-site' => 'Historic Site',
          'pets-okay' => 'Pets Okay',
          'picnic-sites' => 'Picnic Sites',
          'restrooms' => 'Restrooms',
          'rv-dump-station' => 'RV Dump Station',
          'rv-hookups' => 'RV Hookups',
          'showers' => 'Showers',
          'visitor-center' => 'Visitor Center'
        }

        # Activity codes that indicate camping available.

        CAMPING_ACTIVITY_CODES = [ 'ada-campsites', 'cabins-yurts', 'campsites' ]

        # Activity codes for listing activities.

        ACTIVITY_ACTIVITY_CODES = [ 'bike-trails', 'bird-watching', 'canoeing-water-sports', 'equestrian',
                                    'fishing', 'hiking' ]

        # Activity codes for listing amenities.

        AMENITY_ACTIVITY_CODES = [ 'boat-launch', 'gift-shop', 'pets-okay', 'picnic-sites',
                                   'rv-dump-station', 'rv-hookups' ]


        # Activity codes for information center facilities.

        LEARNING_ACTIVITY_CODES = [ 'historic-site', 'visitor-center' ]

        # Activity codes for restroom facilities.

        RESTROOM_ACTIVITY_CODES = [ 'restrooms' ]

        # Activity codes for water facilities.

        WATER_ACTIVITY_CODES = [ 'drinking-water', 'showers' ]

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
        #  value of {Cf::Scrubber::Usda::NationalForestService::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # Build the list of features from the index page.
        # This method parses the HTML returned by the index page, picks up the ul.nav_categories element,
        # and extracts category id and label from its li elements.
        #
        # @return [Array<Hash>] Returns an array of hashes, each containing the following keys:
        #  - *:activity_id* is a string containing the activity identifier (+ada-campsites+, +bike-trails+,
        #    etc...).
        #  - *:name* is a string containing the activity name.
        #  The array is returned in the order in which the li elements are listed.

        def get_activity_list()
          res = get(self.root_url + INDEX_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("ul.nav_categories li label").map do |n|
              i = n.css("input")[0]
              {
                activity_id: i['value'].to_sym,
                name: n.text().strip
              }
            end
          else
            [ ]
          end
        end

        # Get the contents of the detail page for a park.
        #
        # @param [String] url The URL to the park's detail page.
        #
        # @return [String] Returns the contents of the detail page (the response body).

        def get_park_details_page(url)
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            res.body
          else
            ''
          end
        end

        # Build the park list from the contents of the park cards in the index page.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the park data.
        #  Returns +nil+ if it can't find it in the page.

        def get_park_list()
          res = get(self.root_url + INDEX_PATH, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("div.parkCard-wrapper > div.parkCard-item").map do |nc|
              extract_park_data(nc, res)
            end
          else
            [ ]
          end
        end

        # Narrow the park list to those that have camping facilities.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the park data.
        #  Returns +nil+ if it can't find it in the page.

        def select_campground_list()
          get_park_list.select { |pd| pd[:additional_info].has_key?(:campsite_types) }
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

        def adjust_href(href, base_uri)
          n_uri = URI(href)

          if href[0] == '/'
            uri = base_uri.dup
            uri.path = n_uri.path
          else
            uri = URI(href)
          end

          uri.to_s
        end

        def extract_park_name(nf)
          pn = nf.css("div.parkCard-description > h3")[0]
          pn.text();
        end

        def extract_park_blurb(nf)
          pn = nf.css("div.parkCard-description > p")[0]
          pn.text();
        end

        def extract_park_uri(nf, res)
          an = nf.css("a.parkCard-item-front-linkWrapper")[0]
          adjust_href(an['href'], res.uri)
        end

        def extract_features(nb)
          nb.css("ul.parkCard-item-back-amenities > li > span > .icon").map do |n|
            f = ''
            n['class'].split.each do |c|
              if c =~ /^icon-symbols-(.+)/
                m = Regexp.last_match
                f = m[1].downcase
                break
              end
            end

            f
          end
        end

        def extract_park_location(dpg, cpd)
          if dpg.length > 0
            doc = Nokogiri::HTML(dpg)
            doc.css("div.parkQuickLinks > ul > li > a").each do |an|
              uri = URI(an['href'])
              if uri.host =~ /google.com/
                if uri.path =~ /\/maps\//
                  idx = uri.path.index('@')
                  if idx
                    s = uri.path[idx+1, uri.path.length].split(',')
                    cpd[:location] = {
                      lat: s[0],
                      lon: s[1]
                    }
                  else
                    uri.query.split('&').each do |qe|
                      idx = qe.index('ll=')
                      if idx == 0
                        s = qe[idx+3, qe.length].split(',')
                        cpd[:location] = {
                          lat: s[0],
                          lon: s[1]
                        }
                        break
                      end
                    end
                  end
                end

                break
              end
            end
          end
        end

        def extract_park_data(nc, res)
          nf = nc.css("div.parkCard-item-front")[0]
          nb = nc.css("div.parkCard-item-back")[0]

          park_uri = extract_park_uri(nf, res)

          fl = extract_features(nb)
          add = {}
          ACTIVITY_MAP.each do |ak, al|
            a = list_activities(fl, al)
            add[ak] = a.join(', ') if a.count > 0
          end

          cpd = {
            organization: ORGANIZATION_NAME,
            name: extract_park_name(nf) + ' SP',
            uri: park_uri,
            region: REGION_NAME,
            area: '',
            additional_info: add
          }

          # unfortunately the location is in hidden in the park details page

          extract_park_location(get_park_details_page(park_uri), cpd)

          self.logger.info { "extracted park data for (#{cpd[:region]}) (#{cpd[:area]}) (#{cpd[:name]})" }
          cpd
        end
      end
    end
  end
end
