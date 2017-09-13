require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'

require 'cf/scrubber/base'
require 'cf/scrubber/reserve_america'

module Cf
  module Scrubber
    # The namespace for scrubbers for UT sites.

    module UT
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Utah State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the UT State Park System, which is part of UT)

        ORGANIZATION_NAME = 'ut:state'

        # The (fixed) region name is +Utah+, since these are UT state parks.

        REGION_NAME = 'Utah'

        # The URL of the UT State Park System web site.

        ROOT_URL = 'https://stateparks.utah.gov'

        # The camping activities URL (default value).

        CAMPING_URL = '/activities/camping'

        # The list of camping activity labels and what they map to.
        # The Park Service pages don't distinguish between tents and RV, so we will need to figure that
        # out using reserveamerica. Similarly for GROUP.

        CAMPING_ACTIVITIES = [
                              [ Regexp.new('^Map$', Regexp::IGNORECASE), nil ],
                              [ Regexp.new('^Tent & RV$', Regexp::IGNORECASE),
                                [ Cf::Scrubber::Base::TYPE_STANDARD ] ],
                              [ Regexp.new('^Cabins$', Regexp::IGNORECASE),
                                [ Cf::Scrubber::Base::TYPE_CABIN ] ],
                              [ Regexp.new('^Canvas Tent$', Regexp::IGNORECASE),
                                [ Cf::Scrubber::Base::TYPE_CABIN ] ],
                              [ Regexp.new('^Teepees$', Regexp::IGNORECASE),
                                [ Cf::Scrubber::Base::TYPE_CABIN ] ],
                              [ Regexp.new('^Yurts$', Regexp::IGNORECASE),
                                [ Cf::Scrubber::Base::TYPE_CABIN ] ]
                             ]

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::UT::StateParks::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          @park_slugs_to_reservation_uris_map = nil
          @park_slugs_to_park_codes_map = nil
          @park_codes_to_park_slugs_map = nil
          @full_amenities = nil
          @camping_map = nil

          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # Build the park list from the contents of the park list selector in the main page.
        # Note that this method loads just minimal data, and clients will have to call
        # {#extract_park_details} in order to have a fully populated set.
        #
        # This list includes all parks in the UT State Parks system, including those that may not provide
        # campground facilities.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing minimal park data
        #  (data that can be extracted from the park main page).
        #  Returns +nil+ if it can't find it in the page.
        #  The minimal park data contain the following standard key/value pairs:
        #  - *:signature* The park signature.
        #  - *:organization* Is +ut:parks+.
        #  - *:name* The park name.
        #  - *:uri* The URL to the park's details page.
        #  - *:region* The string +Utah+.
        #  - *:area* An empty string.

        def get_park_list()
          extract_park_list(self.root_url)
        end

        # Check if a park claims to have camping accommodations.
        #
        # @param [Hash] lpd The park data, which must include at least the *:uri* key.
        #
        # @return [Boolean] Returns +true+ if the park's URI is present in {#camping_map}, and its value
        #  is a nonempty array. Otherwise, it returns +false+.

        def has_campgrounds?(lpd)
          uri = lpd[:uri]
          if uri
            types = camping_map[uri.downcase]
            (types && (types.length > 0)) ? true : false
          else
            false
          end
        end

        # Load park details for an individual park page.
        # This method extracts park details from one or more park pages.
        #
        # @param [Hash] lpd The park data, which must include at least the *:uri* key.
        # @param [Boolean] logit Set to +true+ to log an info line that the park data were fetched.
        #
        # @return [Hash] Returns a hash containing park data that was extracted from the park detail page
        #  and possibly other related pages:
        #  - *:types* The accommodation types for the park.
        #  - *:reservation_uri* The URL to the reservation page, if one is available.
        #  - *:amenities* A list of amenities present in the park; this is an array of amenity names.
        #  - *:location* A string representation of geographic coordinates for the park; this is
        #    extracted from the list of amenites if possible. Note that these coordinates are not
        #    necessarily expressed in latitude/longitude pairs (and typically they will not be), so that
        #    they may have to be converted by the loaders.

        def get_park_details(lpd, logit = false)
          details = extract_park_details(lpd)

          if details
            if logit
              self.logger.info { "extracted park data for (#{lpd[:region]}) (#{lpd[:area]}) (#{lpd[:name]})" }
            end

            details
          else
            self.logger.warn { "failed to extract park data for (#{lpd[:region]}) (#{lpd[:area]}) (#{lpd[:name]})" }
            { }
          end
        end

        # Build a list of parks with details.
        # This method puts together the partial info methods {#get_park_list} and {#get_park_details} as
        # follows:
        # 1. Call {#get_park_list} to build the park list.
        # 2. For each park, if _filter_ is defined yield to it, passing it the park data, and get its
        #    return value. If the return value is true, or if _filter_ is not defined, call {#get_park_details}
        #    and merge the result value into the park data.
        #    - *:location*, *:reservation_uri*, and *:types* go in the park data.
        #    - *:amenities* goes in the *:additional_info* entry.
        #
        # @param [Array<Hash>] parks An array of park data, typically as returned by {#get_park_list}.
        #  If +nil+, initialize it via a call to {#get_park_list}.
        # @param [Boolean] logit If +true+, log an info line for each park added to the list.
        # @param [Proc] filter The filter block.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the park data. Each contains
        #  the keys returned by {#get_park_list} and by {#get_park_details}.
        #
        # @yield [lpd] If a block is present, yields to it to have it check if the park should be added to
        #  the final list. If no block is provided, all parks in _parks_ will be placed in the return value.

        def build_park_list(parks = nil, logit = false, &filter)
          plist = [ ]

          # 1. park list

          parks = get_park_list() if parks.nil?

          # 2. park details

          parks.each do |p|
            if filter.nil? || filter.call(p)
              pd = p.dup
              details = get_park_details(p, logit)
              [ :location, :types, :reservation_uri ].each do |k|
                pd[k] = details[k] if details.has_key?(k)
              end

              pd[:additional_info] = { } unless pd[:additional_info].is_a?(Hash)
              pd[:additional_info][:amenities] = details[:amenities].join(', ') if details.has_key?(:amenities)

              plist << pd

              if logit
                self.logger.info { "filled park data for (#{p[:region]}) (#{p[:area]}) (#{p[:name]})" }
              end
            end
          end

          plist
        end

        protected

        # Get the camping map.
        # The camping map contains a summary of the "Camping" page: keys are normalized park URIs converted to
        # lowercase, and values are arrays of accommodation types as extracted from the various subpages of
        # the "Camping" page.
        #
        # Note that the "Camping" subpage does not distinguish between tent and RV sites, nor does it have
        # information about group camping; therefore, only {Cf::Scrubber::Base::TYPE_STANDARD} and
        # {Cf::Scrubber::Base::TYPE_CABIN} are present in the values, and other means are needed to check
        # for RV and group sites.
        #
        # @return [Hash] Returns the camping map, a hash as described above. This method caches the map
        #  value, so that the "Camping" page is traversed only the first time it is called.

        def camping_map()
          if @camping_map.nil?
            # first of all, get the "Camping" page

            main_menubar, main_doc = get_main_menu_bar()
            if main_menubar
              activities_item = get_menu_item(main_menubar, 'activities')
              activities_submenu = get_main_menu_item_submenu(activities_item)
              camping_url = get_submenu_item_href(get_submenu_item(activities_submenu, 'camping'))
              camping_url = CAMPING_URL unless camping_url.is_a?(String)

              camping_menubar, camping_doc = get_park_menu_bar(nil, normalize_uri(camping_url))
              if camping_menubar
                @camping_map = { }
            
                camping_menubar.css("> li > a").each do |li_a|
                  label = li_a.text().strip
                  CAMPING_ACTIVITIES.each do |act|
                    if label =~ act[0]
                      res_a = get(normalize_uri(li_a['href']), {
                                    headers: {
                                      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                                    }
                                  })
                      if res_a.is_a?(Net::HTTPOK)
                        href_re = /(.*)\/park-fees\/?/i
                        href_re_2 = /(.*)\/new-tent-cabins-at-palisade-state-park\/?/i
                        doc_a = Nokogiri::HTML(res_a.body)
                        doc_a.css('article p > a.pkbutton').each do |pk_a|
                          # The park link is to the park-fees subpath, so we need to remove that.
                          # At least one link is to a different subpath (that would be Palisade State Park).

                          href = normalize_uri(pk_a['href']).to_s.downcase
                          href = Regexp.last_match[1] if (href =~ href_re) || (href =~ href_re_2)

                          @camping_map[href] = [] unless @camping_map.has_key?(href)
                          @camping_map[href] |= act[1]
                        end
                      end

                      break
                    end
                  end
                end
              end
            end
          end

          @camping_map
        end

        # @!visibility private
        RESTFEEDS_URL = 'https://stateparks.utah.gov/restfeeds/'

        # Get the full list of amenities for the park system.
        # The full list of amenities is a hash where the keys are strings containing a park code, and
        # the values are arrays of amenity descriptors.
        # Each descriptor is a one- or two- element array where the first element is the amenity name,
        # and the optional second element is a string representation of the geographic location of the
        # amenity.
        #
        # For example, a park with code +AISP+ may list multiple +Restrooms+ amenities, each of which
        # will be added to the array for the +AISP+ park. A restroom facility would be listed as an array
        # containing at most two elements:
        # 0. The string +Restrooms+.
        # 1. A string containing the geographic coordinates of the restrooms in question; for example:
        #    <code>SRID=3857;POINT(-12495099.247068636 5016311.2562325643)</code>.
        #    This representation indicates that the coordinates are in the 3857 coordinate system (a
        #    Mercator projection).
        #
        # @return [Hash] Returns a hash as described above. This method caches the value, so that only
        #  one call to the server is made for each call to this method.

        def full_amenities()
          if @full_amenities.nil?
            url = RESTFEEDS_URL + '?type=amenities'
            rv = nil

            res = get(url, {
                        headers: {
                          'Accept' => 'application/json, text/javascript, */*; q=0.01'
                        }
                      })
            if res.is_a?(Net::HTTPOK)
              # it looks like the call may claim that the content type is text/javascript, even though it
              # seems to be valid JSON (which is a stricter form of JS), so we gamble that the JSON parser
              # succeeds.

              json = JSON.parse(res.body)
              if json.has_key?('error')
                err = json['error']
                self.logger.error("failed to fetch restfeeds?amenities: #{err['code']} - #{err['message']} - #{err['details']}")
              else
                # We need the SRID for the coordinates

                srid = nil
                if json['spatialReference']
                  srid = json['spatialReference']['latestWkid']
                  srid = json['spatialReference']['wkid'] if srid.nil?
                end

                # Note that we load the full list of amenities, with geographic coordinates.
                # This means we may have multiple amenities (like Restrooms) per park: this is the raw list.

                @full_amenities = { }
                json['features'].each_with_index do |f, idx|
                  attrs = f['attributes']
                  abbid = attrs['ParkABBID']
                  if abbid.nil?
                    self.logger.warn("null ParkABBID at index #{idx}")
                  else
                    fac = attrs['ParkRecPnt']
                    @full_amenities[abbid] = [ ] unless @full_amenities.has_key?(abbid)
                    v = [ fac ]
                    geom = f['geometry']
                    v << "SRID=#{srid};POINT(#{geom['x']} #{geom['y']})" if geom && srid
                    @full_amenities[abbid] << v
                  end
                end
              end
            else
              self.logger.warn("failed to fetch restfeeds (#{url}): #{res.code} #{res.message}")
            end
          end

          @full_amenities
        end

        # Get the map from park slugs to reservation URIs.
        # See {#park_slugs_to_park_codes_map} for a description of park slugs.
        #
        # @return [Hash] Returns a hash where the keys are park slugs, and the values are URIs to the
        #  main reservations page for the corresponding park.
        #  The method caches the map, so that only one call to server is made for multiple calls to the
        #  method.

        def park_slugs_to_reservation_uris_map()
          load_js_maps()
          (@park_slugs_to_reservation_uris_map.nil?) ? { } : @park_slugs_to_reservation_uris_map
        end

        # Get the map from park slugs to park codes.
        # The UT state park system uses two types of park identifiers:
        # - A <em>park slug</em> is essentially the path to the park's main page, but should be treated as an
        #   opaque identifier.
        # - A <em>park code</em> is a string containing a unique identifier for the park (essentially an
        #   acronym for its name).
        # This map is used to convert from one to the other.
        #
        # @return [Hash] Returns a hash where the keys are park slugs, and the values are park codes.
        #  The method caches the map, so that only one call to server is made for multiple calls to the
        #  method.

        def park_slugs_to_park_codes_map()
          load_js_maps()
          (@park_slugs_to_park_codes_map.nil?) ? { } : @park_slugs_to_park_codes_map
        end

        # Get the map from park codes to park maps.
        # See {#park_slugs_to_park_codes_map} for a description of park slugs and park codes.
        #
        # @return [Hash] Returns a hash where the keys are park codes, and the values are park slugs.
        #  The method caches the map, so that only one call to server is made for multiple calls to the
        #  method.

        def park_codes_to_park_slugs_map()
          load_js_maps()
          (@park_codes_to_park_slugs_map.nil?) ? { } : @park_codes_to_park_slugs_map
        end

        # Get the park slug from a park page.
        # See {#park_slugs_to_park_codes_map} for a description of park slugs and park codes.
        #
        # @param [Nokogiri::Node] doc An object containing the parsed representation of a park page.
        # @param [String] uri The URI to the park page; this is used if _doc_ is +nil+ to get a park page.
        #
        # @return [String] Returns the park slug as extracted from the park page in _doc_ or at _uri_.

        def get_park_slug(doc, uri = nil)
          if doc.nil?
            doc = get_park_page(uri) unless uri.nil?
            return nil if doc.nil?
          end

          re = /reservelinkupdater\(['"]([a-zA-Z-]+)['"]\)/i

          # unfortunately, because some of the pages contain poorly nested HTML, the script element
          # we are looking for is not necessarily in 'body > main > script' where it should be.
          # Therefore, we have to scan all script elements, no matter where they are.

          doc.css('script').each do |sn|
            txt = sn.text()
            return Regexp.last_match[1] if txt =~ re
          end

          nil
        end

        # Given a list of parks, load their :types property.
        # This method builds a list of parks that support various accommodation types, and from that
        # builds the :types attribute for each park in the list.
        #
        # Unfortunately, it's not easy (likely not possible) to determine if a park has only tent or only
        # RV sites, and we'll have to use reserveamerica for that, like we do for Colorado.
        # And group camping has a similar problem.
        #
        # @param [Array<Hash>] plist An array of park data.
        #
        # @return [Array<Hash>] Returns _plist_; the hashes in the array have been modified to contain the
        #  :types attribute.

        def load_types(plist)
          # first of all, get the "Camping" page

          main_menubar, main_doc = get_main_menu_bar()
          if main_menubar
            activities_item = get_menu_item(main_menubar, 'activities')
            activities_submenu = get_main_menu_item_submenu(activities_item)
            camping_url = get_submenu_item_href(get_submenu_item(activities_submenu, 'camping'))
            camping_url = CAMPING_URL unless camping_url.is_a?(String)

            camping_menubar, camping_doc = get_park_menu_bar(nil, normalize_uri(camping_url))
            if camping_menubar
              parks_url_map = { }
              parks_name_map = { }
              plist.each do |p|
                parks_url_map[p[:uri].downcase] = p
                parks_name_map[p[:name]] = p
              end
            
              camping_menubar.css("> li > a").each do |li_a|
                label = li_a.text().strip
                CAMPING_ACTIVITIES.each do |act|
                  if label =~ act[0]
                    res_a = get(normalize_uri(li_a['href']), {
                                  headers: {
                                    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                                  }
                                })
                    if res_a.is_a?(Net::HTTPOK)
                      href_re = /(.*)\/park-fees\/?/i
                      href_re_2 = /(.*)\/new-tent-cabins-at-palisade-state-park\/?/i
                      doc_a = Nokogiri::HTML(res_a.body)
                      doc_a.css('article p > a.pkbutton').each do |pk_a|
                        # The park link is to the park-fees subpath, so we need to remove that.
                        # At least one link is to a different subpath (that would be Palisade State Park).

                        href = normalize_uri(pk_a['href']).to_s
                        href = Regexp.last_match[1] if (href =~ href_re) || (href =~ href_re_2)

                        park = parks_url_map[href.downcase]
                        if park.nil?
                          # try by name

                          name = pk_a.text().strip
                          park = parks_name_map[name]
                        end

                        unless park.nil?
                          park[:types] = [] unless park.has_key?(:types)
                          park[:types] |= act[1]
                        end
                      end
                    end

                    break
                  end
                end
              end

              # Now that we have loaded the types from the camping pages, we still need to check for
              # RV sites. And also for group camping sites, although that might be a bit trickier

              plist.each do |pd|
                ruri = pd[:reservation_uri]
                if ruri
                  if has_rv_sites?(ruri)
                    pd[:types] = [] unless pd.has_key?(:types)
                    pd[:types] |= [ Cf::Scrubber::Base::TYPE_RV ]
                  end
                end
              end
            end
          end

          plist
        end

        private

        FUNCTIONS_URL = 'https://stateparks.utah.gov/wp-content/themes/stateparks/js/functions.min.js'
        PARK_SLUGS_NAME = 'parkSlugToReserveLink'
        PARK_CODES_NAME = 'parkSlugToAbbid'
        RESERVEAMERICA_ROOT_URL = 'http://utahstateparks.reserveamerica.com/camping/'

        def strip_quotes(s)
          s = s[1, s.length] if s[0] == '"'
          s = s[0, s.length-1] if s[-1] == '"'
          s
        end

        def parse_js_map(jscode, label)
          rv = nil
          re = Regexp.new("#{label}\s*=\s*{", Regexp::IGNORECASE)
          idx = jscode =~ re
          if idx
            idx_s = idx + Regexp.last_match[0].length
            idx_e = jscode.index('}', idx_s)
            if idx_e
              rv = { }
              fragment = jscode[idx_s, idx_e-idx_s]
              fragment.split(',').each do |f|
                slug, v = f.split(':')
                slug = strip_quotes(slug)
                v = strip_quotes(v)
                rv[slug] = v
              end
            end
          end

          rv
        end

        def load_js_maps()
          if @park_slugs_to_reservation_uris_map.nil? || @park_slugs_to_park_codes_map.nil?
            res = get(FUNCTIONS_URL, {
                        headers: {
                          'Accept' => 'text/javascript,*/*;q=0.9'
                        }
                      })
            if res.is_a?(Net::HTTPOK)
              jscode = res.body

              map = parse_js_map(jscode, PARK_SLUGS_NAME)
              if map.nil?
                self.logger.warn("failed to parse JS map (#{PARK_SLUGS_NAME})")
              else
                @park_slugs_to_reservation_uris_map = map
              end

              map = parse_js_map(jscode, PARK_CODES_NAME)
              if map.nil?
                self.logger.warn("failed to parse JS map (#{PARK_CODES_NAME})")
              else
                @park_slugs_to_park_codes_map = map
                @park_codes_to_park_slugs_map = { }
                map.each { |k, v| @park_codes_to_park_slugs_map[v] = k }
              end
            else
              self.logger.warn("failed to fetch JS URL (#{FUNCTIONS_URL}): #{res.code} #{res.message}")
            end
          end
        end

        def normalize_uri(uri)
          # OK, so normalization does the following:
          # 1. convert to an absolute URL if necessary

          nuri = adjust_href(uri.to_s, ROOT_URL)

          # 2. The scheme is HTTPS

          nuri.scheme = 'https'

          # 3. Remove trailing slashes

          if nuri.path[-1] == '/'
            nuri.path = nuri.path[0, nuri.path.length-1]
          end

          nuri
        end

        def get_park_page(url)
          res = get(normalize_uri(url), {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            Nokogiri::HTML(res.body)
          else
            self.logger.warn("failed to fetch park page (#{url}): #{res.code} #{res.message}")
            nil
          end
        end

        def get_menu_bar(sel, doc = nil, url = nil)
          doc = get_park_page(url) if doc.nil?
          (doc) ? [ doc.css(sel), doc ] : [ nil, nil ]
        end

        def get_menu_item(menubar, label)
          if menubar
            label = Regexp.new("^#{label}$", Regexp::IGNORECASE) unless label.is_a?(Regexp)
            menubar.css("> li > a").each do |li_a|
              if li_a.text().strip =~ label
                return li_a.parent
              end
            end
          end

          nil
        end

        def get_submenu_item(submenu, label)
          if submenu
            label = Regexp.new("^#{label}$", Regexp::IGNORECASE) unless label.is_a?(Regexp)
            submenu.css("li.menu-item > a").each do |pn|
              return pn if pn.text().strip =~ label
            end
          end

          nil
        end

        def get_submenu_item_href(submenu_item)
          (submenu_item) ? submenu_item['href'] : nil
        end

        def get_main_menu_bar(doc = nil, url = nil)
          get_menu_bar('ul#menu-main-nav-menu', doc, url)
        end

        def get_main_menu_item_submenu(menu_item)
          (menu_item) ? menu_item.css("div.submenu-container > ul.sub-menu").first : nil
        end

        def get_menu_item_href(menu_item)
          if menu_item
            a = menu_item.css('a').first
            (a) ? a['href'] : nil
          else
            nil
          end
        end

        def get_main_menu_item_href(menu_item)
          get_menu_item_href(menu_item)
        end

        def get_park_menu_bar(doc = nil, url = nil)
          get_menu_bar('nav.parknav div.parknavbox div.menubox > ul.menu', doc, url)
        end

        def extract_park_list(url)
          plist = []
          main_menubar, main_doc = get_main_menu_bar()
          parks_submenu = get_main_menu_item_submenu(get_menu_item(main_menubar, 'parks'))
          if parks_submenu
            parks_submenu.css("> li.menu-item > a").each do |pn|
              name = pn.text().strip
              plist << {
                signature: "state/utah/#{name.downcase}/#{name.downcase}",
                organization: ORGANIZATION_NAME,
                name: name,
                uri: normalize_uri(pn['href']).to_s,
                region: REGION_NAME,
                area: ''
              }
            end
          end

          plist
        end

        def extract_park_reservation_uri(doc)
          park_slug = get_park_slug(doc)
          rmap = park_slugs_to_reservation_uris_map
          if rmap.has_key?(park_slug)
            RESERVEAMERICA_ROOT_URL + rmap[park_slug]
          else
            self.logger.warn("no reservation URI for park slug (#{park_slug})")
            nil
          end
        end
          
        COORDINATES_ORDER = [ 'Park Office', 'Entrance Station', 'Parking Lot' ]

        def extract_park_details(mdata)
          rv = { }

          park_doc = get_park_page(mdata[:uri])
          if park_doc
            # 1. the reservation URI

            main_menubar, park_doc = get_main_menu_bar(park_doc)
            reserve_item = get_menu_item(main_menubar, 'reserve')
            if reserve_item
              ruri = extract_park_reservation_uri(park_doc)
              if ruri
                rv[:reservation_uri] = ruri
              else
                self.logger.warn("could not extract park reservation URI (#{mdata[:name]})")
              end
            end

            # 2. the amenities and the location

            park_slug = get_park_slug(park_doc)
            if park_slug.nil?
              self.logger.warn("could not extract park slug for park (#{mdata[:name]})")
            else
              park_code = park_slugs_to_park_codes_map[park_slug]
              if park_code.nil?
                self.logger.warn("could not find park code for park (#{mdata[:name]})")
              else
                if full_amenities && full_amenities.has_key?(park_code)
                  alist = [ ]
                  coords = { }
                  first_coords = nil
                  full_amenities[park_code].each_with_index do |a, idx|
                    name = a[0]
                    alist << name unless alist.include?(name)
                    if a.count > 1
                      coords[name] = [ ] if coords[name].nil?
                      coords[name] << a[1]
                      first_coords = a[1] if first_coords.nil?
                    end
                  end

                  rv[:amenities] = alist

                  COORDINATES_ORDER.each do |name|
                    unless coords[name].nil?
                      rv[:location] = coords[name][0]
                      break
                    end
                  end

                  rv[:location] = first_coords if rv[:location].nil? && !first_coords.nil?
                else
                  self.logger.warn("no amenities listed for park (#{mdata[:name]})")
                end
              end
            end

            # 3. the accommodation types

            duri = mdata[:uri].downcase
            types = camping_map[duri]
            if types
              ruri = rv[:reservation_uri]
              if ruri
                t = if has_rv_sites?(ruri)
                      types | [ Cf::Scrubber::Base::TYPE_RV ]
                    else
                      types.dup
                    end
              else
                t = types.dup
              end

              rv[:types] = t
            end
          else
            self.logger.warn("could not find park page (#{mdata[:name]}) (#{mdata[:uri]})\n")
          end

          rv
        end

        def has_rv_sites?(reservation_url)
          ra = Cf::Scrubber::ReserveAmerica.new(reservation_url, { logger: self.logger })
          ra.has_rv_sites?()
        end
      end
    end
  end
end
