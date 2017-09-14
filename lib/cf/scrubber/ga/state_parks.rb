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

    module GA
      # Scrubber for state park system campgrounds.
      # This scrubber walks the Georgia State Park System web site to extract information about campgrounds.

      class StateParks < Cf::Scrubber::Base
        # The name of the organization dataset (the GA State Park System, which is part of GA)

        ORGANIZATION_NAME = 'ga:state'

        # The (fixed) region name is +Georgia+, since these are GA state parks.

        REGION_NAME = 'Georgia'

        # The URL of the GA State Park System web site.

        ROOT_URL = 'http://gastateparks.org'

        # The path in the web site for the index page.

        INDEX_PATH = '/AllParks'

        # @!visibility private

        GPS_RE = /N\s+([+-]?[0-9]+\.[0-9]+)\s*[\|,]\s+W\s+([+-]?[0-9]+\.[0-9]+)/

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
        # {#extract_park_details} in order to have a fully populated set.
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
        #  - *:signature* The park signature.
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

        # Given a park's local data, get the park details from the details page.
        #
        # @param [Hash] data The park local data, as returned by {#get_park_list}.
        #
        # @return [Hash] Returns a hash containing park data that was extracted from the park detail page:
        #  - *:types* The types of accomodations available in the park.
        #  - *:location* The geographic coordinates of the campground: *:lat*, *:lon*, and *:elevation*.
        #  - *:amenities* The (HTML) contents of the "Accommodations and Facilities" section.
        #  - *:things_to_do* The (HTML) contents of the "Things To Do & See" section.

        def get_park_details(data)
          res = get(adjust_park_url(data[:uri]), {
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
        # This method puts together the partial info methods {#get_park_list} and {#get_park_details}
        # as follows:
        # 1. Call {#get_park_list} to build the park list.
        # 2. For each park, call {#get_park_details} and merge the result value into the park data.
        #    - *:types* goes in the park data
        #    - *:location* goes in the park data
        #    - *:amenities* and *:things_to_do* go in the *:additional_info* entry.
        # 3. And adjust the park URI to include the root URL.
        #
        # @param [Array<Hash>] parks An array of park data, typically as returned by {#get_park_list}.
        #  If +nil+, initialize it via a call to {#get_park_list}.
        # @param [Boolean] logit If +true+, log an info line for each park found.
        #
        # @return [Array<Hash>, nil] Returns an array of hashes containing the park data. Each contains
        #  the keys returned by {#get_park_list} and by {#get_park_details}.

        def build_full_park_list(parks = nil, logit = false)
          # 1. park list and park map

          parks = get_park_list(logit) if parks.nil?
          parks_map = { }
          parks.each { |p| parks_map[p[:uri]] = p }

          # 2. park details, 3. adjust URI

          parks.each do |p|
            details = get_park_details(p)

            p[:types] = details[:types] if details.has_key?(:types)
            p[:location] = details[:location] if details.has_key?(:location)

            p[:additional_info] = { } unless p[:additional_info].is_a?(Hash)
            [ :amenities, :things_to_do ]. each do |k|
              p[:additional_info][k] = details[k] if details.has_key?(k)
            end

            p[:uri] = adjust_park_url(p[:uri])

            if logit
              self.logger.info { "filled park data for (#{p[:region]}) (#{p[:area]}) (#{p[:name]})" }
            end
          end

          parks
        end

        private

        def adjust_park_url(url)
          (url[0] == '/') ? self.root_url + url : url
        end

        def extract_camp_types(doc, res)
          # Unfortunately it seems that we will have to do it by scanning the list of accomodations.
          # There no longer seems to be a map of activities to parks.

          types = { }
          sec = park_page_section_node(doc, res)
          if sec
            sec.css("div.field > div.field-items > div.field-item h2").each do |h2n|
              if h2n.text() =~ /Accommodations/
                cn = h2n.next_sibling
                while cn.name != 'hr' do
                  if cn.name == 'ul'
                    ccn = cn.dup

                    ccn.css('li').each do |nli|
                      txt = nli.text.strip
                      if txt =~ /^[0-9]+\s+Tent.+Camp/
                        types[Cf::Scrubber::Base::TYPE_STANDARD] = true
                        types[Cf::Scrubber::Base::TYPE_RV] = true if txt =~ /\s+RV\s+/
                      elsif txt =~ /^[0-9]+\s+Pioneer\s+Camp/
                        # we currently ignore this
                      elsif txt =~ /^[0-9]+\s+(Horse|Equestrian)\s+Camp/
                        # in the future we may have horse camping as a type
                      elsif txt =~ /^[0-9]+\s+Camp/
                        types[Cf::Scrubber::Base::TYPE_STANDARD] = true
                      elsif txt =~ /^[0-9]+\s+.*\s+Group\s+Camp/
                        types[Cf::Scrubber::Base::TYPE_GROUP] = true
                      elsif txt =~ /^[0-9]+\s+.*\s+Camp/
                        types[Cf::Scrubber::Base::TYPE_STANDARD] = true
                      elsif txt =~ /^[0-9]+\s+Group\s+(Camp)|(Lodge)/
                        types[Cf::Scrubber::Base::TYPE_GROUP] = true
                        types[Cf::Scrubber::Base::TYPE_CABIN] = true if txt =~ /\s+Lodge/
                      elsif txt =~ /^[0-9]+\s+.*\s+Group\s+Camp/
                        types[Cf::Scrubber::Base::TYPE_GROUP] = true
                      elsif txt =~ /^[0-9]+\s+(Cottage)|(Yurt)|(Efficiency)/
                        types[Cf::Scrubber::Base::TYPE_CABIN] = true
                      elsif txt =~ /^[0-9]+\s+.+\s+Cottage/
                        types[Cf::Scrubber::Base::TYPE_CABIN] = true
                      elsif txt =~ /^[0-9]+\s+Cabin/
                        types[Cf::Scrubber::Base::TYPE_CABIN] = true
                      elsif txt =~ /^[0-9]+\s+.*\s+Cabin/
                        types[Cf::Scrubber::Base::TYPE_CABIN] = true
                      end
                    end
                  end

                  cn = cn.next_sibling
                end
              end
            end
          end

          types.keys
        end

        def extract_park_list(url, logit = false)
          res = get(url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)

            doc.css("#block-system-main > div.view > div.view-content > div.views-row > div.views-field-title").map do |nc|
              a = nc.css("span.field-content a")[0]
              name = a.text().strip

              cpd = {
                signature: "state/georgia/#{name.downcase}/#{name.downcase}",
                organization: ORGANIZATION_NAME,
                name: name,
                uri: a['href'],
                region: REGION_NAME,
                area: ''
              }

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

          types = extract_camp_types(doc, res)
          rv[:types] = types unless types.nil?

          loc = extract_location(doc, res)
          rv[:location] = loc unless loc.nil?

          amenities = extract_amenities(doc, res)
          rv[:amenities] = amenities unless amenities.nil?()

          todo = extract_todo(doc, res)
          rv[:things_to_do] = todo unless todo.nil?()

          rv
        end

        def extract_location(doc, res)
          an = park_page_aside_node(doc, res)
          if an
            # unfortunately, some park pages store the title to the GPS section as
            # <strong>GPS Coordinates</sctrong>, and some split GPS and Coordinates into two <strong>.
            # Visually, they are the same, but for the scrubber they are different.
            # So we'll get the text contents of the enclosing <p> and run the regexp over that.

            an.css('div.views-field p').each do |pn|
              # Some parks embed &nbsp; in the GPS coordinates instead of using spaces, and \s
              # does not understand that &nbsp; is whitespace. This causes the regexp match to fail.
              # So, we replace it with spaces; &nbsp; is 0xa0.

              ptxt = pn.text.gsub("\u00a0", " ")
              if ptxt =~ /GPS Coordinates/
                if ptxt =~ GPS_RE
                  m = Regexp.last_match
                  return { lat: m[1], lon: m[2] } if m
                end
              end
            end
          end

          nil
        end

        def extract_amenities(doc, res)
          sec = park_page_section_node(doc, res)
          (sec.nil?) ? nil : extract_named_section(sec, /Accommodations/)
        end

        def extract_todo(doc, res)
          sec = park_page_section_node(doc, res)
          (sec.nil?) ? nil : extract_named_section(sec, /Things To Do/)
        end

        def park_page_section_node(doc, res)
          doc.css('div.main-container div.row > section section#block-system-main > article')[0]
        end
            
        def park_page_aside_node(doc, res)
          doc.css('div.main-container div.row > aside section.block-views div.view-content')[0]
        end
            
        def extract_named_section(container, name)
          re = if name.is_a?(Regexp)
                 name
               else
                 Regexp.new("^#{name}$")
               end

          container.css("div.field > div.field-items > div.field-item h2").each do |h2n|
            if h2n.text() =~ re
              doc = Nokogiri::HTML::Document.new('')
              xn = Nokogiri::XML::NodeSet.new(doc)
              cn = h2n.next_sibling
              while cn && (cn.name != 'hr') do
                if cn.name == 'ul'
                  ccn = cn.dup

                  # we need to make all links open in a new window/tab

                  ccn.css('li a').each do |a|
                    href = a['href']
                    a['href'] = adjust_park_url(href)
                    a['target'] = '_blank'
                  end
                  xn.push(ccn)
                end

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
