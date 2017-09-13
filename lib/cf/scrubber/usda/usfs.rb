require 'cgi'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'json'
require 'logger'
require 'cf/scrubber/base'
require 'cf/scrubber/states_helper'

module Cf
  module Scrubber
    # The namespace for scrubbers for USDA sites.

    module USDA
      # @!visibility private
 
      def self.collapse_ws(s)
        s.split.join(' ')
      end

      # A node in the campground tree from the scrubbed camping page.

      class CampNode
        # The amount by which the level value changes for each level increment.
        # This is the indentation value (in pixels) of items in the HTML.

        LEVEL_DELTA = 25

        # @!visibility private
        ROOT_LEVEL = -25

        # @!attribute [r]
        # The node's label.
        #
        # @return [String] the node's label.

        attr_reader :label

        # @!attribute [r]
        # The node's URI.
        #
        # @return [String] the node's URI.

        attr_reader :uri

        # @!attribute [r]
        # The node's level (as a value of the +margin-left+ CSS parameter).
        #
        # @return [Integer] the node's level.

        attr_reader :level

        # @!attribute [r]
        # The node's parent.
        #
        # @return [Cf::Scrubber::USDA::CampNode] the node's parent.

        attr_reader :parent

        # @!attribute [r]
        # The node's children.
        #
        # @return [Array<Cf::Scrubber::USDA::CampNode>] the node's children.

        attr_reader :children

        # Initializer.
        # The node is initialized with an empty list of children and a +nil+ parent.
        #
        # @param uri [String] The URI associated with this node.
        # @param level [Integer] The node's level.

        def initialize(label, uri, level)
          @label = label.split.join(' ')
          @uri = uri
          @level = level
          @parent = nil
          @children = []
        end

        # Add a child to the node.
        # This method adds _obj_ to the list of children, sets its parent to +self+, and sets the
        # level to the level plus {LEVEL_DELTA}.
        #
        # @param obj [Cf::Scrubber::USDA::CampNode] The object to add to the children.

        def add_child(obj)
          obj.set_parent(self)
          obj.set_level(@level + LEVEL_DELTA)
          @children << obj
        end

        # Depth-first traversal of a tree.
        # Uses +self+ as the root of the tree.
        #
        # @yield [n] Gives the current node to the block.

        def depth_first(&blk)
          @children.each { |c| c.depth_first(&blk) }
          blk.call(self)
        end

        # Width-first traversal of a tree.
        # Uses +self+ as the root of the tree.
        #
        # @yield [n] Gives the current node to the block.

        def width_first(&blk)
          blk.call(self)
          @children.each { |c| c.width_first(&blk) }
        end

        protected

        # Set the parent.
        #
        # @param parent [Cf::Scrubber::USDA::CampNode] The node's parent.

        def set_parent(parent)
          @parent = parent
        end

        # Set the level.
        #
        # @return [Integer] the node's level.

        def set_level(level)
          @level = level
        end
      end

      # Container for the scrubbed contents of a camping page.
      # Instances of this class hold the scrubbed information from one of the camping subpages.
      # A camping subpage contains a +ul+ element whose +li+ elements list the campgrounds associated
      # with the page (for example, <tt>Campground Camping</tt> campgrounds in the Tahoe National Forest).
      # This list is flat in the HTML (all +li+ elements are siblings), but it may be visually hierarchical,
      # since the +li+ are generated with custom +style+ attributes that indent some.
      # We are interested in this hierarchy, because the campgrounds will be at its leaves; therefore, the
      # scrubber extracts that information from the CSS properties of each element.
      # Another reason we are interested in the hierarchy is that some states lump all campgrounds for
      # all national forests in one page, where the root (0 level) nodes are national forest names.
      # In that case, we want to be able to access the root elements alone for heuristic checks.
      #
      # The scrubbed contents contain the following data structures:
      # - An array of strings containing the URIs to the scrubbed +li+ elements.
      # - A hash whose keys are URIs, and whose values are hashes containing each +li+ element's scrubbed
      #   information (*:name* and *:uri*).
      # - The root node of the hierarchy, which is the entry point of the campground tree.
      #
      # Note that the +actid+ parameter has been stripped from the URIs; this makes it easier to compare
      # scrubbed results from multiple camping subpages (and eventually to share the hash of campgrounds).

      class CampingPage
        # @!attribute [r]
        # The name of the subpage (for example, <tt>Campground Camping</tt>).
        #
        # @return [String] the name of the subpage.

        attr_reader :name

        # @!attribute [r]
        # The list of campgrounds. This is the flat list corresponding to the +li+items, and it contains
        # the URIs to the campgrounds.
        #
        # @return [Array<String>] the list of campground URIs.

        attr_reader :camp_list

        # @!attribute [r]
        # The campground properties. This hash is keyed by campground URI, and contains hashes with the
        # campground properties.
        #
        # @return [Hash] the campground properties.

        attr_reader :campgrounds

        # @!attribute [r]
        # The root of the campground hierarchy.
        #
        # @return [Cf::Scrubber::USDA::CampNode] the root node for the +li+ hierarchy.

        attr_reader :root

        # Initializer.
        # The page is initialized with an empty root node.
        #
        # @param name [Hash] The page name.
        # @param campgrounds [Hash] An optional hash of campgrounds that have already been loaded; used
        #  to avoid picking up campground data multiple times. The keys are campground URLs, and the
        #  values are hashes containing the campground name and URI.

        def initialize(name, campgrounds = {})
          @name = name
          @campgrounds = campgrounds
          @camp_list = []
          @root = nil
        end

        # Scrub a page content.
        #
        # @param res [Net::HTTPResponse] The response containing the page to scrub.

        def scrub(res)
          @root = Cf::Scrubber::USDA::CampNode.new('root', nil, Cf::Scrubber::USDA::CampNode::ROOT_LEVEL)
          @camp_list = []

          cur_node = @root

          doc = Nokogiri::HTML(res.body)

          # the list of campgrounds is in the <ul> immediately below <td> from the third row in the
          # centercolumn table

          root_element = doc.css("div#centercol > table > tr")[2]
          home_element = root_element.css("td > ul")

          # iterate over all children of <ul>, so that we get only the <li> that are immediate children

          home_element.children.each do |n|
            if n.name.downcase == 'li'
              a = nil
              n.children.each do |e|
                if e.name.downcase == 'a'
                  a = e
                  break
                end
              end

              unless a.nil?
                camp_name = a.text()
                camp_url = Cf::Scrubber::Base.adjust_href(a['href'], res.uri, [ 'actid' ])
                camp_level = margin_level(n)

                if campgrounds.has_key?(camp_url)
                  c = @campgrounds[camp_url]
                else
                  c = { name: camp_name, uri: camp_url }
                  @campgrounds[camp_url] = c
                end

                @camp_list << c

                # OK now the tough part: figure out where this guy goes in the tree.
                # A negative delta means the node is uplevel from current, so we need to walk back
                # up the tree.
                # A zero delta means it is at the same level as current, so we also need to walk back, once
                # A positive delta means the node is downlevel, and we place in the children of current;
                # however, if there are skipped levels, we need to create dummy nodes for them

                delta = camp_level - cur_node.level
                if delta <= 0
                  while delta <= 0
                    cur_node = cur_node.parent
                    delta += Cf::Scrubber::USDA::CampNode::LEVEL_DELTA
                  end
                else
                  nl = cur_node.level
                  while delta > Cf::Scrubber::USDA::CampNode::LEVEL_DELTA
                    nl += Cf::Scrubber::USDA::CampNode::LEVEL_DELTA
                    nn = Cf::Scrubber::USDA::CampNode.new('dummy', nil, nl)
                    delta -= Cf::Scrubber::USDA::CampNode::LEVEL_DELTA
                    cur_node.add_child(nn)
                    cur_node = nn
                  end
                end

                # OK, now we can add it in the right place

                nc = Cf::Scrubber::USDA::CampNode.new(camp_name, camp_url, camp_level)
                cur_node.add_child(nc)
                cur_node = nc
              end
            end
          end
        end

        private

        def parse_style(style)
          h = {}
          style.split(';').each do |e|
            idx = e.index(':')
            k = e[0,idx].to_sym
            v = e[idx+1,e.length]
            h[k] = v
          end
          h
        end

        def margin_level(node)
          hs = parse_style(node['style'])
          ((hs[:margin].split(' '))[3]).to_i
        end
      end

      # Scrubber for national forest campgrounds.
      # This scrubber walks the National Forest Service web site to extract information about campgrounds.

      class USFS < Cf::Scrubber::Base
        include Cf::Scrubber::StatesHelper

        # The name of the organization dataset (the National Forest Service, which is part of USDA)

        ORGANIZATION_NAME = 'usda:nfs'

        # The URL of the National Forest Service web site

        ROOT_URL = 'https://www.fs.fed.us'

        # The name of the forest camping subpage listing cabin rentals.

        CAMPGROUND_CABINS_SUBPAGE = 'Cabin Rentals'

        # The name of the forest camping subpage listing campgrounds.

        CAMPGROUND_CAMPING_SUBPAGE = 'Campground Camping'

        # The name of the forest camping subpage listing dispersed camping campgrounds.
        # This page seems to list areas that allow off-campground camping more than organized campgrounds.

        CAMPGROUND_DISPERSED_CAMPING_SUBPAGE = 'Dispersed Camping'

        # The name of the forest camping subpage listing group camping campgrounds.

        CAMPGROUND_GROUP_CAMPING_SUBPAGE = 'Group Camping'

        # The name of the forest camping subpage listing campgrounds that can hold RVs.

        CAMPGROUND_RV_CAMPING_SUBPAGE = 'RV Camping'

        # @!visibility private
        CAMPGROUND_TYPES = {
          :standard => {
            page: CAMPGROUND_CAMPING_SUBPAGE,
            actid: 29
          },
          :group => {
            page: CAMPGROUND_GROUP_CAMPING_SUBPAGE,
            actid: 33
          },
          :cabin => {
            page: CAMPGROUND_CABINS_SUBPAGE,
            actid: 101
          },
          :rv => {
            page: CAMPGROUND_RV_CAMPING_SUBPAGE,
            actid: 31
          }
        }

        # Key translations.
        # This array maps the normalized labels in the "At a Glance" section to standard keys in a
        # campground's info hash.
        # Note that +:lon+, +:lat+, and +:elevation+ are actually placed outside the info hash,
        # in a campground's +:location+ attribute instead.

        KEYS_MAP = {
          area_amenities: :amenities,
          best_season: :best_season,
          busiest_season: :busiest_season,
          closest_towns: :closest_towns,
          current_conditions: :current_conditions,
          elevation: :elevation,
          fees: :fees,
          information_center: :information_center,
          latitude: :lat,
          length: :length,
          longitude: :lon,
          open_season: :open_season,
          operated_by: :operated_by,
          operational_hours: :hours_of_operation,
          passes: :passes,
          permit_info: :permit_info,
          'rentals_&_guides': :rentals_and_guides,
          reservations: :reservations,
          restrictions: :restrictions,
          restroom: :restroom,
          usage: :usage,
          water: :water
        }

        # @!visibility private

        ADDITIONAL_INFO_KEYS = [ :amenities, :closest_towns, :hours_of_operation, :information_center,
                                 :open_season, :rentals_and_guides, :reservations, :restrictions, :restroom,
                                 :water ]

        # Initializer.
        #
        # @param root_url [String] The root URL for the web site to scrub; if not defined, it uses the
        #  value of {Cf::Scrubber::USDA::USFS::ROOT_URL}
        # @param opts [Hash] Additional configuration options for the scrubber.
        #  See {Cf::Scrubber::Base#initializer}.

        def initialize(root_url = nil, opts = {})
          @states = nil
          @forests = {}

          root_url = ROOT_URL unless root_url.is_a?(String)
          super(root_url, opts)
        end

        # @!attribute [r] states
        # A hash containing the list of states (and territories) from the NFS web site.
        #
        # @return [Hash] the list of states; keys are strings containing the state name, and values are the
        #  corresponding state identifiers. If the current value is not defined, calls {#build_state_list}
        #  to load it.
        
        def states()
          build_state_list() if @states.nil?
          @states
        end

        # Get the list of forests for a given state identifier.
        # If the list has not been loaded, calls {#build_forest_list} to load it.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        #
        # @return [Hash] Returns the list of forests in the given state; keys are strings containing the
        #  forest name, and values are the corresponding forest identifiers.
        #  If the current value is not defined, calls {#build_forest_list} to load it.
        #  If <i>state_id</i> contains a bad state, or there are no forests in the given state, returns
        #  an empty hash.

        def forest_ids_for_state(state_id)
          state_id = normalize_state_id(state_id)
          
          # we have to account for states that don't have any forests (and therefore are not in the
          # states list): if state_id is nil, then there is no such state in the state list

          if state_id
            build_forest_list(state_id) unless @forests.has_key?(state_id)
            @forests[state_id]
          else
            {}
          end
        end

        # Get the list of states and state IDs.
        # Scans the main page of the NFS web site, looking for the states selector element, and
        # builds the states list from its +option+ elements.
        #
        # @return [Hash] Returns a hash where the keys are state names (as strings), and the values are the
        #  corresponding state identifiers. This hash is also cached and is available after the call via
        #  the attribute {#states}.

        def build_state_list()
          @states = {}

          res = get(self.root_url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })

          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("#find-a-forest-state option").each do |n|
              if n['value'].length > 0
                k = n['value']
                s = ''
                n.search('text()').each { |t| s << t.serialize }
                @states[s] = k.to_i
              end
            end
          end

          @states
        end

        # Get the list of forests for a given state IDs.
        # Makes an Ajax call into the NFS Ajax API to get the HTML fragment containing the forest selector
        # element, and extracts forest name and identifier from its +option+ elements.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        #
        # @return [Hash] the list of forests in the given state; keys are strings containing the forest name,
        #  and values are the corresponding forest identifiers. If the current value is not defined, calls
        #  {#build_forest_list} to load it.
        #  This hash is also cached and is available after the call via {#forest_ids_for_state}.

        def build_forest_list(state_id)
          state_id = normalize_state_id(state_id)

          # It looks like we need to send a valid :form_build_id and :form_id, so we first get the home
          # page and extract those two values, and them supply them to the POST

          form_id, form_build_id = get_form_identifiers()
          js_cookie = CGI::Cookie.new("has_js", "1")
          url = self.root_url + '/system/ajax'
          res = post(url, {
                       'state' => state_id,
                       'name' => '',
                       'form_build_id' => form_build_id,
                       'form_id' => form_id,
                       '_triggering_element_name' => 'state'
                     }, {
                       headers: {
                         'Accept' => 'application/json, text/javascript, */*; q=0.01',
                         'Accept-Encoding' => 'gzip, deflate, br'
                       },
                       cookies: [ js_cookie.to_s]
                     })

          if res.is_a?(Net::HTTPOK)
            forests = {}
            cmd = find_insert_command(JSON.parse(res.body))
            unless cmd.nil?
              doc = Nokogiri::HTML(cmd['data'])
              doc.css("#wrapper-state-parks select option").each do |n|
                if n['value'].length > 0
                  k = n['value']
                  s = ''
                  n.search('text()').each { |t| s << t.serialize }
                  
                  # We normalize the forest name by collapsing whitespace. This makes the code a bit
                  # more forgiving to typos both in the USFS site, and from the client.

                  s = Cf::Scrubber::USDA.collapse_ws(s)
                  forests[s] = k.to_i
                end
              end
            end

            @forests[state_id] = forests
            forests
          else
            nil
          end
        end

        # Get the home page for a given forest identifier.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        #
        # @return [Net::HTTPResponse] Returns a response object containing the home page for the forest.

        def get_forest_home_page(state_id, forest_id)
          if forest_id.is_a?(Hash)
            res = get(forest_id[:url], {
                        headers: {
                          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                        }
                      })
          else
            state_id = normalize_state_id(state_id)
            forest_id = normalize_forest_id(state_id, forest_id)
            js_cookie = CGI::Cookie.new("has_js", "1")
            res = post(self.root_url, {
                         'state' => state_id,
                         'name' => forest_id,
                         'form_build_id' => 'form-MJQbK6EUpm0ALbpFKBEvxv7MUTTSy2St78gYr7JEkpQ',
                         'form_id' => 'fs_search_form_find_a_forest',
                         'op' => 'Go'
                       }, {
                         headers: {
                           'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                         },
                         cookies: [ js_cookie.to_s ]
                       })

            if res.is_a?(Net::HTTPRedirection)
              res = get(res['Location'], {
                          headers: {
                            'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                          }
                        })
            end
          end

          res
        end

        # Get a secondary page for a given forest identifier.
        # Secondary pages are accessible from the +Home+ list in the main page, which contains links to the
        # secondary pages.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        # @param page_name [String] The name of the secondary page to load; this is the label of the list item
        #  that holds the link to the page.
        #
        # @return [Net::HTTPResponse, nil] Returns a response object containing a secondary page for the
        #  forest, or +nil+ if the forest was not found.

        def get_forest_secondary_page(state_id, forest_id, page_name)
          r_res = nil
          f_res = get_forest_home_page(state_id, forest_id)
          if f_res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(f_res.body)
            elem, href = get_forest_left_menu_node(f_res, doc, page_name)
            return nil if href.nil?
            r_res = get(href)
          end

          r_res
        end

        # Get the "recreation" page for a given forest identifier.
        # This method is a wrapper for {#get_forest_secondary_page} with page name set to +Recreation+.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        #
        # @return [Net::HTTPResponse] Returns a response object containing the recreation page for the forest.

        def get_forest_recreation_page(state_id, forest_id)
          get_forest_secondary_page(state_id, forest_id, 'Recreation')
        end

        # Get a "recreation" subpage for a given forest identifier.
        # This method looks up the given named item in the recreation list, and returns its associated page.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        # @param subpage_name [String] The name of the recreation subpage to load; this is the label of the list
        #  item that holds the link to the page.
        #
        # @return [Net::HTTPResponse] Returns a response object containing the recreation subpage for the forest.

        def get_forest_recreation_subpage(state_id, forest_id, subpage_name)
          s_res = nil
          r_res = get_forest_recreation_page(state_id, forest_id)
          if r_res.is_a?(Net::HTTPOK)
            s_href = nil
            doc = Nokogiri::HTML(r_res.body)
            elem, href = get_forest_left_menu_node(r_res, doc, subpage_name)
            s_res = get(href)
          end

          s_res
        end

        # Get the camping page for a given forest identifier.
        # This method is a wrapper for {#get_forest_recreation_subpage} with page name set to
        # <tt>Camping & Cabins</tt>.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        #
        # @return [Net::HTTPResponse] Returns a response object containing the camping subpage for the forest.

        def get_forest_camping_page(state_id, forest_id)
          # See the discussion in {#get_forest_camping_subpage_urls} for why we do this

          if forest_id.is_a?(Hash) && forest_id[:facility]
            r_res = get(forest_id[:url])
            if r_res.is_a?(Net::HTTPOK)
              s_href = nil
              doc = Nokogiri::HTML(r_res.body)
              elem, href = get_forest_left_menu_node(r_res, doc, 'Camping & Cabins')
              s_res = get(href)
            end
          else
            get_forest_recreation_subpage(state_id, forest_id, 'Camping & Cabins')
          end
        end

        # Get a camping subpage for a given forest identifier.
        # This method grabs the camping page using {#get_forest_camping_page}, extracts the link to the
        # page labeled <i>subpage_name</i>, and returns that page.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        # @param subpage_name [String] The name of the camping subpage to load; this is the label of the list
        #  item that holds the link to the page.
        #
        # @return [Net::HTTPResponse] Returns a response object containing the camping subpage for the forest.

        def get_forest_camping_subpage(state_id, forest_id, subpage_name)
          self.logger.debug { "get_forest_camping_subpage (#{state_id}) (#{forest_id}) (#{subpage_name})" }

          s_res = nil
          c_res = get_forest_camping_page(state_id, forest_id)
          if c_res.is_a?(Net::HTTPOK)
            s_href = nil
            doc = Nokogiri::HTML(c_res.body)
            elem, href = get_forest_center_menu_node(c_res, doc, subpage_name, [ ])
            s_res = get(href) if href
          end

          s_res
        end

        # Get the list of campgrounds for a given forest identifier.
        # This method calls {#get_forest_camping_subpage} for {CAMPGROUND_CAMPING_SUBPAGE} and parses its
        # contents to build the list of campgrounds.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state 
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param forest_id [Integer, String, Hash] The forest identifier. If a string, this is assumed to
        #  be a forest name, and the corresponding identifier is obtained from {#forest_ids_for_state}.
        #  If a hash, this is assumed to be a forest descriptor ase returned by
        #  {Cf::Scrubber::USDA::USFSHelper.forest_descriptors_for_state}; in this case the URL for the
        #  home page is available in the *:url* property of <i>forest_id</i>
        # @param types [Array<Symbol,String>] An array listing the campsite types to include in the list;
        #  campgrounds that offer campsites from the list are added to the return set.
        #  A +nil+ value indicates that all camping types are to be included.
        # @param with_details [Boolean] If +true+, also load the data from the campground details page.
        #
        # @return [Array<Hash>] Returns an array of hashes containing the list of campgrounds.
        #  The hashes contain the following standard key/value pairs:
        #  - *:signature* The park signature.
        #  - *:organization* Is +usda:nfs+.
        #  - *:name* The campground name.
        #  - *:uri* The URL to the campground's details page.
        #  - *:region* The state for the campground's national forest.
        #  - *:area* The national forest name.
        #  - *:location* The geographic coordinates of the campground: *:lat*, *:lon*, and *:elevation*.
        #    Only present if <i>with_details</i> is +true+.
        #  - *:types* An array listing the types of campsites in the campground; often this will be a one
        #    element array, but some campgrounds have multiple site types.
        #  - *:reservation_uri* The URL to the reservation page for the campground.
        #  - *:blurb* A short description of the campground.
        #  - *:additional_info* A hash containing essentially a subsection of the "At a Glance" scrubbed
        #    components. Only present if <i>with_details</i> is +true+.
        #  They also contain scrubber-specific keys:
        #  - *:state* The name of the state in which the campground is located.
        #  - *:state_id* The identifier of the state in which the campground is located.
        #  - *:forest* The name of the forest (or grassland) in which the campground is located.
        #  - *:forest_id* The identifier of the forest (or grassland) in which the campground is located.
        #  - *:at_a_glance* A hash containing all the key/value pairs extracted from the "At a Glance"
        #    part of the details page.

        def get_forest_campgrounds(state_id, forest_id, types = nil, with_details = false)
          tt = ((types.is_a?(Array)) ? types : Cf::Scrubber::Base::CAMPSITE_TYPES).map { |e| e.to_sym }

          state_id = normalize_state_id(state_id)
          state_name = normalize_state_name(state_id)
          if forest_id.is_a?(Hash)
            forest_name = forest_id[:name]
          else
            forest_id = normalize_forest_id(state_id, forest_id)
            forest_name = normalize_forest_name(state_id, forest_id)
          end

          @campgrounds_map = { }
          @campgrounds = [ ]

          # OK so the first thing we do is scan the camping page (once!) to get the URLs of the listed
          # subpages: not all national forest sites have all 4 links

          get_forest_camping_subpage_urls(state_id, forest_id, tt).each do |t, url|
            scan_camping_subpage(url, t, state_name, state_id, forest_name, forest_id, with_details)
          end

          # At this point, we have scanned all the pages for all the required types.
          # @campgrounds contains the list of campground URIs, and @campgrounds_map the map from URIs
          # to campground data

          @campgrounds.map { |uri| @campgrounds_map[uri] }
        end

        # Get the list of campgrounds for a given state identifier.
        # This method calls {#get_forest_campgrounds} for each
        # forest in the state with the given identifier, and merges the return value in a single array.
        #
        # @param state_id [Integer, String] The state identifier. If a string, this is assumed to be a state
        #  name, and the corresponding identifier is obtained from the hash in the {#states} attribute.
        # @param types [Array<Symbol,String>] An array listing the campsite types to include in the list;
        #  campgrounds that offer campsites from the list are added to the return set.
        #  A +nil+ value indicates that all camping types are to be included.
        # @param with_details [Boolean] If +true+, also load the data from the campground details page.
        #
        # @return [Array<Hash>] Returns an array of hashes containing the list of campgrounds.
        #  See {#get_forest_campgrounds} for a description of the hash contents.

        def get_state_campgrounds(state_id, types = nil, with_details = false)
          camps = []
          forest_ids_for_state(state_id).each do |forest_id|
            camps.concat(get_forest_campgrounds(state_id, forest_id, types, with_details))
          end

          camps
        end

        # Given a campground hash, extract details from its details page.
        #
        # @param campground [Hash] The campground hash, as returned by {#get_forest_campgrounds}.
        # @option campground [String] :name The campground name.
        # @option campground [String] :uri The URL to the campground detail page.
        #
        # @return [Hash] Returns a hash of campground properties.

        def get_campground_details(campground)
          dh = {}
          res = get(campground[:uri])
          if res.is_a?(Net::HTTPOK)
            self.logger.info { "get_campground_details((#{campground[:name]}) (#{campground[:state]}) (#{campground[:forest]}))" }

            doc = Nokogiri::HTML(res.body)

            dh[:at_a_glance] = extract_at_a_glance_details(doc, campground)
            activities = extract_activities_details(doc, campground)
# still needs some work
#            dh[:blurb] = extract_blurb_details(doc, campground)
            dh[:location] = {}

            loc_box = doc.css("div#rightcol div.box > p.boxheading")
            loc_box.each do |n|
              if n.text() == 'Location'
                dh[:location] = extract_location_details(n.parent, campground)
                break
              end
            end

            dh[:additional_info] = convert_at_a_glance_details(dh[:at_a_glance], doc, campground)
            dh[:additional_info][:activities] = activities.join(', ') if activities.length > 0
          else
            self.logger.warn { "get_campground_details((#{campground[:name]}) (#{campground[:state]}) (#{campground[:forest]})) gets #{res}" }
          end

          dh
        end

        # Normalize the state identifier.
        # If <i>state_id</i> is an integer, returns its value; if it is a string, looks up the corresponding
        # state identifier from the states map in {#states}.
        #
        # @param state_id [Integer, String, Symbol] The state identifier (if an integer), or the state name
        #  (if a string or symbol).
        #
        # @return [Integer] Returns the state identifier, as described above.

        def normalize_state_id(state_id)
          if state_id.is_a?(String) || state_id.is_a?(Symbol)
            sid = state_id.to_s
            if sid.length == 2
              sc = sid.upcase.to_sym
              s = STATE_CODES[sc]
              self.logger.warn("unknown state code: #{sc}") if s.nil?
              state_id = self.states()[s]
            else
              sid = state_id
              state_id = self.states()[state_id]
              self.logger.warn("unknown state name: #{sid}") if state_id.nil?
            end
          end
          state_id
        end

        # Normalize the forest or grassland identifier.
        # If <i>forest_id</i> is an integer, returns its value; if it is a string, looks up the corresponding
        # forest identifier from the forests map in {#forest_ids_for_state}.
        #
        # @param state_id [Integer, String] The state identifier (if an integer), or the state name
        #  (if a string).
        # @param forest_id [Integer, String] The forest/grassland identifier (if an integer), or the
        #  forest/grassland name (if a string).
        #
        # @return [Integer] Returns the forest/grassland identifier, as described above.

        def normalize_forest_id(state_id, forest_id)
          if forest_id.is_a?(String)
            s = Cf::Scrubber::USDA.collapse_ws(forest_id)
            f = forest_ids_for_state(state_id)
            forest_id = f[s]
            self.logger.warn("unknown forest or grassland name: #{s}") if forest_id.nil?
          end
          forest_id
        end

        # Normalize the state name.
        # If <i>state_name</i> is a string, returns its value; if it is an integer, looks up the corresponding
        # state name from the states map in {#states}.
        #
        # @param state_name [String, Integer] The state name (if a string), or the state identfier
        #  (if an integer).
        #
        # @return [String] Returns the state name, as described above.

        def normalize_state_name(state_name)
          return state_name if state_name.is_a?(String)

          # let's do a linear search: there are more or less 50 entries in the map.

          s = state_name
          self.states.each do |sk, sv|
            return sk if sv == state_name
          end
          self.logger.warn("unknown state identifier: #{state_name}")
          nil
        end

        # Normalize the forest or grassland name.
        # If <i>forest_name</i> is a string, returns its value; if it is an integer, looks up the corresponding
        # forest name from the forests map in {#forest_ids_for_state}.
        #
        # @param state_id [Integer, String] The state identifier (if an integer), or the state name
        #  (if a string).
        # @param forest_name [String, Integer] The forest/grassland name (if a string), or the
        #  forest/grassland identifier (if an integer).
        #
        # @return [String] Returns the forest/grassland name, as described above.

        def normalize_forest_name(state_id, forest_name)
          return Cf::Scrubber::USDA.collapse_ws(forest_name) if forest_name.is_a?(String)

          # There are no more than a couple dozen forests per state, so we can do a linear search

          forest_ids_for_state(state_id).each do |fk, fv|
            return Cf::Scrubber::USDA.collapse_ws(fk) if forest_name == fv
          end

          self.logger.warn("unknown forest or grassland identifier: #{forest_name}")
          nil
        end
          
        private
        
        def get_form_identifiers()
          form_build_id = ''
          form_id = ''

          res = get(self.root_url, {
                      headers: {
                        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
                      }
                    })

          if res.is_a?(Net::HTTPOK)
            doc = Nokogiri::HTML(res.body)
            doc.css("#fs-search-form-find-a-forest input[name=form_build_id]").each do |n|
              if n['value'].length > 0
                form_build_id = n['value']
              end
            end
            doc.css("#fs-search-form-find-a-forest input[name=form_id]").each do |n|
              if n['value'].length > 0
                form_id = n['value']
              end
            end
          end

          [ form_id, form_build_id ]
        end

        def find_insert_command(json_res)
          json_res.each do |e|
            return e if (e['command'] == 'insert') && e['method'].nil?
          end

          nil
        end

        def get_forest_left_menu_node(res, doc, node_label, qf = [ ])
          root_element = doc.css("div#leftcol > table > tr")[2]
          unless root_element.nil?
            home_element = root_element.css("div.navleft ul")
            home_element.css('li > a > span').each do |n|
              t = n.text()
              if t == node_label
                return [ n.parent.parent, adjust_href(n.parent['href'], res.uri, qf) ]
              end
            end
          end

          [ nil, nil ]
        end

        def get_forest_center_menu_node(res, doc, node_label, qf = [ ])
          self.logger.debug { "get_forest_center_menu_node (#{node_label}) (#{res.uri})" }
          root_element = doc.css("div#centercol > table > tr")[1]
          self.logger.debug { "get_forest_center_menu_node root: #{root_element}" }
          root_element.css('ul li > a > strong').each do |n|
            self.logger.debug { "get_forest_center_menu_node li_a_strong: #{n}" }
            t = n.text()
            if t == node_label
              self.logger.debug { "get_forest_center_menu_node href: #{n.parent['href']}" }
              self.logger.debug { "get_forest_center_menu_node adjusted: #{adjust_href(n.parent['href'], res.uri, qf)}" }
              return [ n.parent.parent, adjust_href(n.parent['href'], res.uri, qf) ]
            end
          end

          [ nil, nil ]
        end

        # Scans the camping page for a given state/forest and returns the available subpage links.

        def get_forest_camping_subpage_urls(state_id, forest_id, types)
          urls = { }

          if forest_id.is_a?(Hash)
            # if neither :label nor :container_label is present, this is not a USFS URL (typically it is
            # a wilderness URL) and therefore we can skip it

            if forest_id[:label] || forest_id[:container_label]
              # A hash contains all the information we need to generate the URLs; there is no need to
              # scrub HTML code

              types.each do |t|
                url = "http://#{Cf::Scrubber::USDA::USFSHelper::USFS_WEB_SITE_HOST}/activity/"
                url += (forest_id[:container_label]) ? forest_id[:container_label] : forest_id[:label]
                url += "/recreation/camping-cabins/?recid=#{forest_id[:usfs_id]}&actid=#{CAMPGROUND_TYPES[t][:actid]}"
                urls[t] = url
              end
            end
          else
            c_res = get_forest_camping_page(state_id, forest_id)
            if c_res.is_a?(Net::HTTPOK)
              doc = Nokogiri::HTML(c_res.body)
              types.each do |t|
                elem, href = get_forest_center_menu_node(c_res, doc, CAMPGROUND_TYPES[t][:page], [ ])
                urls[t] = href unless href.nil?
              end
            end
          end

          urls
        end

        def add_signature(c)
          recid = nil
          c[:uri].query.split('&').each do |q|
            k, v = q.split('=')
            if k == 'recid'
              recid = v
              break
            end
          end

          unless recid.nil?
            c[:signature] = "usfs/#{c[:area].downcase}/#{c[:name].downcase}/#{recid}"
          end
        end

        def scan_camping_subpage(url, type, state_name, state_id, forest_name, forest_id, with_details)
          page_name = CAMPGROUND_TYPES[type][:page]
          res = get(url)
          if res.is_a?(Net::HTTPOK)
            self.logger.info { "scan_camping_subpage((#{page_name}) (#{state_name}) (#{forest_name}))" }

            boilerplate = {
              organization: ORGANIZATION_NAME,
              region: state_name,
              area: forest_name,
              state: state_name,
              state_id: state_id,
              forest: forest_name,
              forest_id: forest_id
            }

            pg = CampingPage.new(page_name)
            pg.scrub(res)

            # Hack time! Some states use a common page for the campgrounds for all forests in the state
            # (see, for example, NC). In this case, it seems that the forests are the 0-level items,
            # and campgrounds are nested underneath. (The 0-level items are pg.root's children.)
            # So we need to detect that structure: if the labels of the 0-levels look like
            # "... National Forest" or "... National Grassland", then we assume we are in the multiple
            # forest situation. In this case, we look for a child whose label is *forest_name*, and if
            # we extract its leaves.
            # Otherwise, we extract root's leaves.
            #
            # Note that we must do the label check, because the absence of *forest_name* does not necessarily
            # indicate that this is not a multiple-forest situation, since the specific forest may not have
            # any campgrounds for this page.

            multiple_forests = true
            forest_root = nil
            pg.root.children.each do |c|
              # some national forest names have multiple spaces, surely as a consequence of typos

              if (c.label !~ /National\s+Fore$/i) && (c.label !~ /National\s+Grass$/i)
                multiple_forests = false
              end
              forest_root = c if c.label == forest_name
            end

            # decision time! If we have no forest_root and it seems to be multiple forests, we deduce
            # (hopefully correctly!) that this forest does not have entries of this type and therefore we
            # can skip the traversal

            return if forest_root.nil? && multiple_forests

            # Otherwise, we traverse either the forest_root (this should be a multiple forests case),
            # or the page root (this is a single forest)

            scan_root = (forest_root) ? forest_root : pg.root
            scan_root.depth_first do |n|
              # OK so we only emit leaf nodes.
              # That's the heuristic here: we assume that the USFS web pages list campgrounds in the
              # leaf nodes

              if n.uri && (n.children.count == 0)
                if @campgrounds_map.has_key?(n.uri)
                  # So this campground has already been loaded (from a different page type), so we
                  # don't need to duplicate the work. All we have to do is update the :types

                  c = @campgrounds_map[n.uri]
                  c[:types] << type
                else
                  # not there yet: pick up the data

                  c = pg.campgrounds[n.uri]
                  c.merge!(boilerplate)
                  c.merge!(get_campground_details(c)) if with_details
                  c[:types] = [ type ]
                  add_signature(c)

                  @campgrounds << n.uri
                  @campgrounds_map[n.uri] = c
                end
              end
            end
          else
            self.logger.warn { "get_forest_campgrounds((#{state_name}) (#{forest_name})) gets #{res}" }
          end
        end

        def extract_location_details(box, campground)
          h = {}
          cur = nil
          box.css('div.right-box').each do |n|
            k = n.text().strip
            if cur.is_a?(Symbol)
              h[cur] = k
              cur = nil
            else
              if k =~ /([A-Z][a-z]+) :/
                m = Regexp.last_match
                cur = m[1].downcase.to_sym
                if KEYS_MAP.has_key?(cur)
                  cur = KEYS_MAP[cur].to_sym
                else  
                  self.logger.warn("unsupported location key '#{m[1]}' for campground (#{campground[:state]}) (#{campground[:forest]}) (#{campground[:name]})")
                end
                
              end
            end
          end

          h
        end

        def extract_at_a_glance_details(doc, campground)
          h = {}
          doc.css("div#centercol td > h2").each do |n|
            if n.text() == 'At a Glance'
              g = n
              while true do
                g = g.next_sibling()
                if (g.name == 'div') && (g['class'] == 'tablecolor')
                  g.css('table > tr').each do |tr|
                    th = tr.css('th')[0]
                    td = tr.css('td')[0]
                    ths = th.text()
                    s = ths.gsub(/\s+/, ' ').strip.gsub(/:$/, '').gsub(' ', '_').downcase.to_sym
                    if KEYS_MAP.has_key?(s)
                      s = KEYS_MAP[s].to_sym
                    else
                      self.logger.warn("unsupported at-a-glance key '#{ths}' for campground (#{campground[:state]}) (#{campground[:forest]}) (#{campground[:name]})")
                    end
                    h[s] = td.inner_html().strip
                  end
                  break
                end
              end
              break
            end
          end

          h
        end

        def extract_activities_details(doc, campground)
          activities = [ ]
          doc.css("div#centercol td > h2").each do |n|
            if n.text() == 'Activities'
              g = n
              h3_current = nil
              while true do
                g = g.next_sibling()
                break if g.nil?
                if g.name == 'h3'
                  h3_current = g
                elsif g.name == 'div'
                  g.css('h4').each do |ah4|
                    activities << ah4.text()
                  end
                end
              end
              break
            end
          end

          activities
        end

        def extract_blurb_details(doc, campground)
          blurb = ''
          hline = doc.css("div#centercol td > dif.hline")[0]
          cur = hline
          loop = true
          while loop
            cur.next_sibling
            if cur.name.downcase == 'p'
              # As a heuristic, if the paragraph contains <strong> elements, we assume it's a special
              # note and we skip it.

              if cur.css("strong").length < 1
                blurb = cur.text()
                loop = false
              end
            end
          end

          blurb
        end

        def convert_at_a_glance_details(at_a_glance, doc, campground)
          h = {}
          
          ADDITIONAL_INFO_KEYS.each do |k|
            h[k] = at_a_glance[k] if at_a_glance.has_key?(k)
          end

          h
        end
      end
    end
  end
end
