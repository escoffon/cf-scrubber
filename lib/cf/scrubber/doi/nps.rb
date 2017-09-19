require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'
require 'digest/md5'

require 'cf/scrubber/base'
require 'cf/scrubber/states_helper'
require 'cf/scrubber/ridb/api'

module Cf
  module Scrubber
    module DOI
      # Scrubber for National Park Service campgrounds.
      # This scrubber extracts NPS information from the RIDB API to build lists of NPS campgrounds.
      # It then also pokes around in the NPS web site to extract some additional information, as needed.

      class NPS < Cf::Scrubber::Base
        include Cf::Scrubber::StatesHelper

        # The name of the organization dataset (the National Park Service, which is part of
        # the Department of Interior)

        ORGANIZATION_NAME = 'doi:nps'

        # The URL of the National Park Service web site

        ROOT_URL = 'https://www.nps.gov'

        # @!visibility private
        RESERVATION_URI_TEMPLATE = 'https://www.recreation.gov/campgroundDetails.do?contractCode=NRSO&parkId=%d'

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::DOI::NPS::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          @states = {}
          @state_queries = {}
          @rec_areas = {}
          @rec_area_to_state = {}

          @rec_area_facilities = {}
          @facility_queries = {}
          @facilities = {}
          @facility_to_rec_area = {}

          @ridb = Cf::Scrubber::RIDB::API.new(opts)

          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # @!attribute [r] ridb
        # @return the instance of {Cf::Scrubber::RIDB::API} used by this object.

        attr_reader :ridb

        # @!attribute [r] states
        # A hash containing the list of states (and territories) that were loaded by the scrubber.
        #
        # @return [Hash] the list of states; keys are strings containing the two-letter state code, values
        #  are hashes containing the list of rec areas associated with the state.
        #  The keys in these list hashes are rec area identifiers, and the values are hashes containing
        #  the rec area data.
        #  The list of states and rec areas are cumulative across multiple calls to the scrubber: they contain
        #  the union of all the states and all rec areas that were loaded by {#rec_areas_for_state}.
        #  To get more targeted results, use {#rec_areas_for_state}, as described there.
        
        attr_reader :states

        # @!attribute [r] rec_areas
        # A hash containing the list of rec areas that were loaded by the scrubber.
        #
        # @return [Hash] the list of rec areas; the keys are rec area identifiers, and the values are hashes
        #  containing the rec area data.
        #  The list of rec areas is cumulative across multiple calls to the scrubber: it contains
        #  the union of all rec areas that were loaded by {#rec_areas_for_state}.
        #  To get more targeted results, use {#rec_areas_for_state}, as described there.
        
        attr_reader :rec_areas

        # @!attribute [r] facilities
        # A hash containing the list of facilities that were loaded by the scrubber.
        #
        # @return [Hash] the list of facilities; keys are strings containing the facility identifier, values
        #  are hashes containing facility data.
        #  The list of facilities  are cumulative across multiple calls to the scrubber: they contain
        #  the union of all the facilities that were loaded by calls to the API.
        
        attr_reader :facilities

        # Get the list of rec areas for a given state identifier.
        # Loads the list and places it in {#states} if not already loaded.
        #
        # This method generates a digest from the string representation of _params_ and uses it as the key
        # in the cached query data to check if results from the request have already been stored.
        # If so, it returns the cached value. Therefore, multiple calls to this method with the same values
        # of _state_ and _params_ are cheap.
        #
        # @param [String] state The state name, or two-letter code.
        # @param [Hash] params A hash of parameters for the request.
        #
        # @return [Hash] Returns the list of rec areas for the given state and parameters; keys are the rec
        #  area id, and values are hashes containing the rec area data.

        def rec_areas_for_state(state, params = {})
          state_code = get_state_code(state)
          if state_code
            @states[state_code] = {} unless @states.has_key?(state_code)
            @state_queries[state_code] = {} unless @state_queries.has_key?(state_code)
            md5 = digest_hash(params)
            unless @state_queries[state_code][md5].is_a?(Hash)
              p = params.merge({ state: state_code })
              ral = {}
              ridb.rec_areas_for_organization(Cf::Scrubber::RIDB::API::ORGID_NPS, p).each do |ra|
                raid = ra['RecAreaID'].to_s
                ral[raid] = ra

                @states[state_code][raid] = ra
                @rec_areas[raid] = ra
                @rec_area_to_state[raid] = state_code
              end
              @state_queries[state_code][md5] = ral
            end

            @state_queries[state_code][md5]
          else
            nil
          end
        end

        # Get the list of rec areas for a given state identifier that support given activities.
        # Calls {#rec_areas_for_state} passing an *:activity* parameter built from the list in _activities_.
        #
        # @param [String] state The state name, or two-letter code.
        # @param [Array<Integer, String>] activities An array containing the list of activities to look for.
        #  A +nil+ value maps to an array containing {Cf::Scrubber::RIDB::API::ACTIVITY_CAMPING}.
        #  A string value in the array is a string representation of the integer value.
        #
        # @return [Hash] Returns the list of rec areas for the given state and activities; keys are the rec
        #  area id, and values are hashes containing the rec area data.

        def rec_areas_for_state_and_activities(state, activities = nil)
          activities = [ Cf::Scrubber::RIDB::API::ACTIVITY_CAMPING ] unless activities.is_a?(Array)
          actlist = activities.map { |a| a.to_s }

          rec_areas_for_state(state, { activity: actlist.join(',') })
        end

        # Get a rec area by identifier.
        # If the rec area is not in the cache, request it from the API.
        #
        # @param [String, Integer] raid The rec area identifier.
        #
        # @return [Hash, nil] Returns a hash containing the descriptor of the rec area, +nil+ if no
        #  such rec area exists. As a side effect, the rec area descriptor may have been placed in the cache.

        def get_rec_area(raid)
          sraid = raid.to_s
          unless @rec_areas.has_key?(sraid)
            ra = ridb.get_rec_area(sraid)
            return nil if ra.nil?
            @rec_areas[sraid] = ra
          end

          @rec_areas[sraid]
        end

        # Get the list of facilities for a given rec area identifier.
        # Loads the list and places it in {#facilities} if not already loaded.
        #
        # This method generates a digest from the string representation of _params_ and uses it as the key
        # in the cached query data to check if results from the request have already been stored.
        # If so, it returns the cached value. Therefore, multiple calls to this method with the same values
        # of _raid_ and _params_ are cheap.
        #
        # @note It appears that there is no surefire way to query for campgrounds for a given rec area,
        #  since the API does not support the *:activity* parameter for this request. Experimental
        #  evidence seems to suggest that using the *:query* parameter and passing +camping+ may not
        #  return all records, since apparently some campgrounds do not list camping in their keywords.
        #  So, we need to do it the hard way: filter campgrounds by running individual facility queries
        #  and checking if the return value includes a list of campsites.
        #
        # @param [String, Numeric] raid The rec area's identifier.
        # @param [Hash] params A hash of parameters for the request.
        #
        # @return [Hash] Returns the list of facilities for the given state and parameters; keys are the 
        #  facility id, and values are hashes containing the facility data.

        def facilities_for_rec_area(raid, params = {})
          rakey = raid.to_s
          @rec_area_facilities[rakey] = {} unless @rec_area_facilities.has_key?(rakey)
          @facility_queries[rakey] = {} unless @facility_queries.has_key?(rakey)
          md5 = digest_hash(params)
          unless @facility_queries[rakey][md5].is_a?(Hash)
            fl = {}
            ridb.facilities_for_rec_area(rakey, params).each do |f|
              # If the facilities has already been loaded, and it contains the ORGANIZATION key, then
              # this is the full record, and we use that instead.

              fid = f['FacilityID'].to_s
              if @facilities.has_key?(fid)
                if full_facility?(@facilities[fid])
                  f = @facilities[fid]
                end
              end

              fl[fid] = f

              @rec_area_facilities[rakey][fid] = f
              @facilities[fid] = f
              @facility_to_rec_area[fid] = rakey
            end
            @facility_queries[rakey][md5] = fl
          end

          @facility_queries[rakey][md5]
        end

        # Given a list of facilities, return the ones that are (or appear to be) campgrounds.
        # This method gets the full record from the API, and determines if this is a campground facility
        # with these checks:
        # 1. The +FacilityTypeDescription+ key contains the string +Camping+.
        # 2. The +CAMPSITE+ key contains an array whose length is greater than 0.
        # 3. An element in the +ACTIVITY+ array contains an activity whose +ActivityID+ property is
        #    {Cf::Scrubber::RIDB::API::ACTIVITY_CAMPING}.
        # 4. Out of desperation, the facility name includes the word +campground+; the reason we do this is
        #    that the RIDB doesn't alwasy have complete records: some campground facilities are not marked
        #    "for camping," only reservable campsites are placed in the campsites list, and so on.
        # If any of these tests succeed, the facility is marked as being a campground.
        #
        # @param [Hash, Array<Hash>] flist The list of facilities to filter. If _flist_ is a hash, the keys
        #  are facility identifiers, and the values facility descriptors.
        #
        # @return [Hash] Returns a hash where keys are facility identifiers, and values facility descriptors.

        def extract_campgrounds(flist)
          rv = {}

          if flist.is_a?(Array)
            flist.each do |f|
              f = get_facility(f['FacilityID']) unless full_facility?(f)
              rv[f['FacilityID'].to_s] = f if is_campground?(f)
            end
          else
            flist.each do |fid, f|
              f = get_facility(fid) unless full_facility?(f)
              rv[fid.to_s] = f if is_campground?(f)
            end
          end

          rv
        end

        # Get a facility by identifier.
        # If the facility is not in the cache, or it does not have a full descriptor, request it from the API.
        #
        # @param [String, Integer] fid The facility identifier.
        #
        # @return [Hash, nil] Returns a hash containing the full descriptor of the facility, +nil+ if no
        #  such facility exists. As a side effect, the facility descriptor may have been placed in the cache.

        def get_facility(fid)
          sfid = fid.to_s
          unless @facilities.has_key?(sfid) && full_facility?(@facilities[sfid])
            f = ridb.get_facility(sfid, true)
            return nil if f.nil?
            @facilities[sfid] = f
          end

          @facilities[sfid]
        end

        # Given a list of facilities, generate standardized campground descriptions.
        #
        # @param [Hash] flist The list of facilities to use; the keys are facility identifiers, and the values
        #  facility descriptors. This is typically the return value from {#extract_campgrounds}.
        #
        # @return [Array<Hash>] Returns an array of hashes containing the list of campgrounds.
        #  The hashes contain the following standard key/value pairs:
        #  - *:signature* The park signature.
        #  - *:organization* Is +doi:nps+.
        #  - *:name* The campground name.
        #  - *:uri* The URL to the campground's details page.
        #  - *:region* The state for the campground's rec area.
        #  - *:area* The rec area name.
        #  - *:location* The geographic coordinates of the campground: *:lat*, *:lon*, and *:elevation*.
        #  - *:types* An array listing the types of campsites in the campground; often this will be a one
        #    element array, but some campgrounds have multiple site types.
        #  - *:reservation_uri* The URL to the reservation page for the campground.
        #  - *:additional_info* A hash containing additional information. The following keys are placed
        #    in the hash:
        #    - *:activities* An array containing the names of activities available in the campground.
        #    - *:keywords* An array containing the names of keywords associated with the campground.
        #    - *:description* A string containing a description of the campground.

        def convert_campgrounds(flist)
          rv = []
          flist.each do |fk, fac|
            fkey = fk.to_s
            rakey = @facility_to_rec_area[fkey]
            ra = get_rec_area(rakey)
            state = get_state_name(@rec_area_to_state[rakey])
            state = '' if state.nil?

            types, permitted, campsite_count = types_for_campground(fac, ra)
            if types.count < 1
              self.logger.warn { "no types for (#{ra['RecAreaName']}) (#{fac['FacilityName']}) - skipping campground" }
              next
            end

            nl = fac['FacilityName'].split(' ').map { |s| s.capitalize }

            c = {
              signature: "nps//#{ra['RecAreaName'].downcase}/#{fac['FacilityID']}",
              organization: ORGANIZATION_NAME,
              region: state,
              area: ra['RecAreaName'],
              name: nl.join(' '),
              types: types
            }

            uri = uri_for_campground(fac, ra)
            if uri
              c[:uri] = uri
            else
              self.logger.warn { "could not find a camping URI for (#{ra['RecAreaName']}) (#{fac['FacilityName']})" }
              self.logger.warn { "using rec area URI for (#{ra['RecAreaName']}) (#{fac['FacilityName']})" }
              c[:uri] = uri_for_rec_area(ra)
            end

            if fac['FacilityReservationURL'].length > 0
              c[:reservation_uri] = fac['FacilityReservationURL']
            else
              ruri = reservation_uri_for_campground(fac, ra)
              if ruri
                c[:reservation_uri] = ruri
              end
            end

            if fac.has_key?('FacilityLatitude') && fac.has_key?('FacilityLongitude')
              c[:location] = { lat: fac['FacilityLatitude'], lon: fac['FacilityLongitude'] }
            end

            ai = {
              description: fac['FacilityDescription']
            }

            ai[:keywords] = fac['Keywords'] if fac.has_key?('Keywords') && (fac['Keywords'].length > 0)
            if fac.has_key?('ACTIVITY') && (fac['ACTIVITY'].length > 0)
              ai[:activities] = (fac['ACTIVITY'].map { |a| a['FacilityActivityDescription'] }).join(', ')
            end
            
            ai[:campsite_count] = campsite_count if campsite_count > 0
            if permitted.count > 0
              ai[:permitted_equipment] = (permitted.keys.sort.map { |pk| "#{pk} (#{permitted[pk]})" }).join(', ')
            end

            c[:additional_info] = ai

            rv << c
          end

          rv
        end
          
        private

        def digest_hash(hash)
          s = ""
          hash.keys.sort.each do |k|
            v = (hash[k].is_a?(Hash)) ? digest_hash(hash[k]) : hash[k]
            s << "#{k}=#{v}&"
          end

          Digest::MD5.hexdigest(s)
        end

        def full_facility?(f)
          f.has_key?('ORGANIZATION')
        end

        def is_campground?(f)
          return true if f['FacilityTypeDescription'].downcase == 'camping'
          return true if f['CAMPSITE'].is_a?(Array) && (f['CAMPSITE'].length > 0)
          if f['ACTIVITY'].is_a?(Array)
            f['ACTIVITY'].each do |a|
              if a['ActivityID'] == Cf::Scrubber::RIDB::API::ACTIVITY_CAMPING
                return true
              end
            end
          end
          return true if f['FacilityName'] =~ /campground/i

          false
        end

        # @!visibility private
        CAMPING_RE_LIST = [
                           /^camping$/i
                          ]

        # @!visibility private
        CAMPING_PAGES = [
                         '/planyourvisit/camping.htm',
                         '/planyourvisit/campgrounds.htm',
                         '/planyourvisit/camping-in-campgrounds.htm',
                         '/planyourvisit/camp.htm'
                        ]

        def root_uri_for_rec_area(ra)
          "#{self.root_url}/#{ra['OrgRecAreaID'].downcase}"
        end

        def uri_for_rec_area(ra)
          "#{root_uri_for_rec_area(ra)}/index.htm"
        end

        def scrub_eating_sleeping(res, root)
          doc = Nokogiri::HTML(res.body)

          # These are all highly custom. The first two are for UT facilities

          doc.css('p.subheading').each do |psub|
            if psub.text() =~ /Camping/i
              # The page has a camping section, so we return the page itself

              return res.uri
            end
          end

          doc.css('a').each do |a|
            if a.text() =~ /Camping/i
              # The page has a link to a camping page, relative to the root

              return "#{root}#{a['href']}"
            end
          end

          # give up 

          nil
        end

        def uri_for_campground(fac, ra)
          # The NPS web site is a bit unstructured in the campground info: there may be individual campground
          # pages, but it's hard to figure them out from parsing HTML.
          # So, we look for some well-known pages within the rec area's page tree to get at least the top level
          # camping page

          # NPS rec area pages seem to have a common root: <nps_root>/<rec_area_id>.downcase

          root = root_uri_for_rec_area(ra)

          # First, we look for an element in the "plan your visit" menu that contains 'Camping'
          # Currently we look for an item with the exact 'Camping' label, but later we may add more

          res = get("#{root}/index.htm", {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })

          doc = nil
          plan = nil
          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css('ul#LocalNav > li.has-sub > a > span').each do |p|
              if p.text() =~ /plan your visit/i
                plan = p.parent.parent.css('> ul').first
                break
              end
            end

            if plan
              plan.css('li > a').each do |a|
                CAMPING_RE_LIST.each do |re|
                  if a.text().strip =~ re
                    return "#{self.root_url}#{a['href']}"
                  end
                end
              end
            end
          end

          # If we are here, let's try some standard pages. This is more or less a desperate attempt, but
          # it often works.

          CAMPING_PAGES.each do |pg|
            uri = "#{root}#{pg}"
            if exists?(uri)
              # found a page! Good enough

              return uri
            end
          end

          # Some sites put camping info into the "Eating & Sleeping" page; for example, Natural Bridges and
          # Zion (both in UT) do that. As an added twist, Zion has a link to a camping page...
          # The "Eating & Sleeping" page seems to have a standard name.

          res = get("#{root}/planyourvisit/eatingsleeping.htm", {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })
          unless res.is_a?(Net::HTTPOK)
            if plan
              eat_sleep = nil
              plan.css('li > a').each do |a|
                if a.text().strip =~ /Eating \& Sleeping/i
                  eat_sleep = a
                  break
                end
              end

              if eat_sleep
                res = get("#{self.root_url}#{eat_sleep['href']}", {
                            headers: {
                              'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                            }
                          })
              end
            end
          end

          if res.is_a?(Net::HTTPOK)
            uri = scrub_eating_sleeping(res, root)
            return (uri.nil?) ? res.uri : uri
          end

          nil
        end

        def reservation_uri_for_campground(fac, ra)
          if fac.has_key?('LegacyFacilityID') && (fac['LegacyFacilityID'].to_i > 0)
            uri = sprintf(RESERVATION_URI_TEMPLATE, fac['LegacyFacilityID'].to_i)
            match = 0
            total = 0

            # sanity check: get the page, look up the campground name, see if they match

            res = get(uri, {
                        headers: {
                          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                        }
                      })

            if res.is_a?(Net::HTTPOK)
              doc = Nokogiri::HTML(res.body)
              campname = doc.css('#campnamearea > #campname').first
              if campname
                spann = campname.css('> h2 > span').first
                if spann
                  name, state = spann.text().split(', ')
                  name.split(' ').each do |n|
                    rn = n.strip.gsub(/[^0-9a-zA-Z]/, '')
                    total += 1
                    match += 1 if fac['FacilityName'] =~ Regexp.new(rn, Regexp::IGNORECASE)
                  end

                  ra_state = @rec_area_to_state[ra['RecAreaID'].to_s]
                  total += 1
                  match += 1 if ra_state && (ra_state =~ Regexp.new(state))
                end

                part = campname.css('> div > a').first
                if part
                  part.text().split(' ').each do |n|
                    rn = n.strip.gsub(/[^0-9a-zA-Z]/, '')
                    total += 1
                    match += 1 if ra['RecAreaName'] =~ Regexp.new(rn, Regexp::IGNORECASE)
                  end
                end
              end
            end

            score = match.to_f / total.to_f
            (score > 0.5) ? uri : nil
          else
            nil
          end
        end

        KNOWN_CAMPSITE_TYPES = [
                                'STANDARD NONELECTRIC',
                                'STANDARD ELECTRIC',
                                'TENT ONLY NONELECTRIC',
                                'RV NONELECTRIC',
                                'RV ELECTRIC',
                                'GROUP TENT ONLY AREA NONELECTRIC',
                                'GROUP STANDARD NONELECTRIC',
                                'GROUP STANDARD AREA NONELECTRIC',
                                'GROUP PICNIC AREA',
                                'GROUP EQUESTRIAN',
                                'GROUP SHELTER NONELECTRIC',
                                'EQUESTRIAN NONELECTRIC',
                                'PARKING',
                                'CABIN NONELECTRIC',
                                'CABIN ELECTRIC',
                                'BOAT IN',
                                'GROUP BOAT IN',
                                'HIKE TO',
                                'GROUP HIKE TO',
                                'WALK TO',
                                'GROUP WALK TO',
                                'MANAGEMENT'
                               ]
        FACILITY_CAMPING = 'Camping'

        def types_for_campground(fac, ra)
          # The following code is not super reliable (well the code is), because the data are not super
          # reliable. Some campsites return an empty array for PERMITTEDEQUIPMENT, even though the site
          # supports RVs.
          # So we'll comment it out and do things a bit differently: the CampsiteType property seems to
          # be more consistent, although much less granular.
          # rv = [ :standard ]
          # if fac['CAMPSITE'].is_a?(Array)
          #   fac['CAMPSITE'].each do |cs|
          #     print("++++ #{fac['FacilityName']} #{cs['CampsiteName']}\n")
          #     csd = @ridb.api_call(cs['ResourceLink']).first
          #     csd['PERMITTEDEQUIPMENT'].each do |eq|
          #       n = eq['EquipmentName']
          #       if (n =~ /RV/) || (n =~ /Camper/)  || (n =~ /Fifth/)
          #         rv << :rv
          #         return rv
          #       end
          #     end
          #   end
          # end
          #
          # But of course that's still not perfect, because RIDB claims that it does not include campsites
          # that are not reservable. And by and large it keeps that promise, which causes problems, since
          # we can't check any campsite type.
          #
          # There is also at least one case (Yosemite NP, day use parking lot) of a facility being marked
          # as a campground (and returned in a facilities query with activity=9) which is not, in fact, a
          # campground, but is added because it has reservable sites (parking slots in this case).
          # This facility does list sites, but does not mark them as campsite (rather, they are marked as
          # parking).
          #
          # So a possibly more robust algorithm is:
          # 1. iterate over all campsites, collect all the different CampsiteType values.
          #    In theory, we could also iterate over all PERMITTEDEQUIPMENTS entries to determine what
          #    kind of equipment (vehicles, trailers) are allowed at the given site, but we won't.
          # 2. based on the list of different campsites, we can build a list of types.
          #    See below.
          # 3. if the list of types is empty at this point, and there were campsites, then we return an
          #    empty list, since no campsites qualified. This is the step that filters out the parking lot
          # 4. If the FacilityType indicates a camping facility, return [ :standard ] since that's the
          #    best we could do.
          # 5. If FacilityType does imply a campground, we return an empty list.
          # This algorithm may exclude valid campgrounds, but at least it won't return a parking lot as a
          # campground
          #
          # A list, possibly not complete, of CampsiteType values from a campsite descriptor, with what
          # I think it supports:
          #  STANDARD NONELECTRIC - can hold tents and vehicles, not necessarily large motorhomes but maybe
          #  STANDARD ELECTRIC - can hold tents and vehicles, not necessarily large motorhomes but maybe
          #  TENT ONLY NONELECTRIC - only tents
          #  RV NONELECTRIC - only RV, typically larget than STANDARD. NO TENTS!
          #  RV ELECTRIC - only RV, typically larget than STANDARD. NO TENTS!
          #  GROUP TENT ONLY AREA NONELECTRIC - group camping, and tent only in this case
          #  GROUP STANDARD NONELECTRIC - group camping, tents and vehicles
          #  GROUP STANDARD AREA NONELECTRIC - likely the same as GROUP STANDARD NONELECTRIC
          #  GROUP PICNIC AREA - probably a reservable picnic area
          #  GROUP EQUESTRIAN - group camping, horse trailer
          #  GROUP SHELTER NONELECTRIC - probably some kind of roofed/protected area for groups
          #  GROUP HIKE TO - not sure
          #  EQUESTRIAN NONELECTRIC - horse trailer
          #  PARKING - parking slot
          #  CABIN NONELECTRIC - a cabin
          #  CABIN ELECTRIC - a cabin
          #  BOAT IN - not sure, but sounds like you have to use a boat to get there
          #  HIKE TO - not sure, but sounds like you hike to get there
          #  WALK TO - not sure, but sounds like you walk (shorter hike?) to get there
          #  MANAGEMENT - not sure
          # To determine list of types:
          # - TENT ONLY adds :standard
          # - STANDARD adds :standard and :rv
          # - RV adds :rv
          # - GROUP (TENT)|(STANDARD)|(EQUESTRIAN) adds :group
          # - EQUESTRIAN adds :standard (at some point we may make it add :horse)
          # - PARKING adds nothing
          # - CABIN adds :cabin
          # - BOAT IN, HIKE TO, WALK TO adds :standard
          # - GROUP (BOAT IN)|(HIKE TO)|(WALK TO) adds :group
          # 
          # And as long as we are at it, we can collect the list of permitted equipment, to display in
          # additional info.

          permitted = { }
          site_types = { }
          unknown = { }
          campsites = ridb.campsites_for_facility(fac['FacilityID'])
          campsites.each do |cs|
            t = cs['CampsiteType']
            if t && (t.length > 0)
              if KNOWN_CAMPSITE_TYPES.include?(t)
                site_types[t] = true
              else
                unless unknown.has_key?(t)
                  self.logger.warn { "unknown CampsiteType (#{t}) for facility (#{ra['RecAreaName']}) (#{fac['FacilityName']})" }
                  unknown[t] = true
                end
              end
            end

            if cs['PERMITTEDEQUIPMENT']
              cs['PERMITTEDEQUIPMENT'].each do |eqp|
                e = eqp['EquipmentName']
                if permitted[e]
                  permitted[e] += 1
                else
                  permitted[e] = 1
                end
              end
            end
          end

          rv = [ ]
          if site_types.count == 0
            # no known campsite types: this is steps 3 and 4 above

            if campsites.count < 1
              ft = fac['FacilityTypeDescription']
              rv = ((ft == FACILITY_CAMPING) || (ft.length == 0)) ? [ :standard ] : [ ]
            end
          else
            site_types.each do |t, v|
              if t =~ /TENT ONLY/
                rv << Cf::Scrubber::Base::TYPE_STANDARD unless rv.include?(Cf::Scrubber::Base::TYPE_STANDARD)
              elsif t =~ /STANDARD/
                rv << Cf::Scrubber::Base::TYPE_STANDARD unless rv.include?(Cf::Scrubber::Base::TYPE_STANDARD)
                rv << Cf::Scrubber::Base::TYPE_RV unless rv.include?(Cf::Scrubber::Base::TYPE_RV)
              elsif t =~ /RV/
                rv << Cf::Scrubber::Base::TYPE_RV unless rv.include?(Cf::Scrubber::Base::TYPE_RV)
              elsif t =~ /CABIN/
                rv << Cf::Scrubber::Base::TYPE_CABIN unless rv.include?(Cf::Scrubber::Base::TYPE_CABIN)
              elsif t =~ /EQUESTRIAN/
                rv << Cf::Scrubber::Base::TYPE_STANDARD unless rv.include?(Cf::Scrubber::Base::TYPE_STANDARD)
              elsif t =~ /(BOAT IN)|(HIKE TO)|(WALK TO)/
                rv << Cf::Scrubber::Base::TYPE_GROUP unless rv.include?(Cf::Scrubber::Base::TYPE_STANDARD)
              end

              if t =~ /GROUP (TENT)|(STANDARD)|(EQUESTRIAN)|(BOAT IN)|(HIKE TO)|(WALK TO)/
                rv << Cf::Scrubber::Base::TYPE_GROUP unless rv.include?(Cf::Scrubber::Base::TYPE_GROUP)
              end
            end
          end

          [ rv, permitted, campsites.count ]
        end
      end
    end
  end
end
