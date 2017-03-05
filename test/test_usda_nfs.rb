require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/usda/script'

class TestCampgroundsScript < Cf::Scrubber::Usda::Script::Campgrounds
  class Parser < Cf::Scrubber::Usda::Script::Campgrounds::Parser
    def initialize()
      rv = super()

      p = self.parser
      p.banner = "Usage: usda_nfs_campgrounds [options]\n\nList campgrounds for one or more states and forests"
      
      rv
    end
  end

  def initialize()
    super(TestCampgroundsScript::Parser.new)
  end

  def campgrounds()
    @campgrounds
  end

  def exec()
    @campgrounds = [ ]

    cur_state = ''
    cur_forest = ''

    self.process do |nfs, s, f, c|
      @campgrounds << c
    end
  end
end

class UsdaNFSTest < Minitest::Test
  def test_state_conversion
    assert_equal 'CA', Cf::Scrubber::Usda::NationalForestService.state_code('California')
    assert_equal 'RI', Cf::Scrubber::Usda::NationalForestService.state_code('Rhode Island')

    assert_equal 'CA', Cf::Scrubber::Usda::NationalForestService.state_code('CA')
    assert_equal 'RI', Cf::Scrubber::Usda::NationalForestService.state_code('RI')

    assert_equal 'Alaska', Cf::Scrubber::Usda::NationalForestService.state_name('AK')
    assert_equal 'Alaska', Cf::Scrubber::Usda::NationalForestService.state_name('ak')
    assert_equal 'Alaska', Cf::Scrubber::Usda::NationalForestService.state_name(:AK)
    assert_equal 'Alaska', Cf::Scrubber::Usda::NationalForestService.state_name(:ak)

    assert_equal 'Rhode Island', Cf::Scrubber::Usda::NationalForestService.state_name('RI')
    assert_equal 'Rhode Island', Cf::Scrubber::Usda::NationalForestService.state_name('ri')
    assert_equal 'Rhode Island', Cf::Scrubber::Usda::NationalForestService.state_name(:RI)
    assert_equal 'Rhode Island', Cf::Scrubber::Usda::NationalForestService.state_name(:ri)

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    
    assert_equal 'CA', nfs.state_code('California')
    assert_equal 'RI', nfs.state_code('Rhode Island')

    assert_equal 'CA', nfs.state_code('CA')
    assert_equal 'RI', nfs.state_code('RI')

    assert_equal 'Alaska', nfs.state_name('AK')
    assert_equal 'Alaska', nfs.state_name('ak')
    assert_equal 'Alaska', nfs.state_name(:AK)
    assert_equal 'Alaska', nfs.state_name(:ak)

    assert_equal 'Rhode Island', nfs.state_name('RI')
    assert_equal 'Rhode Island', nfs.state_name('ri')
    assert_equal 'Rhode Island', nfs.state_name(:RI)
    assert_equal 'Rhode Island', nfs.state_name(:ri)
  end

  def test_state_list
    states = [ "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Florida", "Georgia",
               "Idaho", "Illinois", "Indiana", "Kansas", "Kentucky", "Louisiana", "Maine", "Michigan",
               "Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
               "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon",
               "Pennsylvania", "Puerto Rico", "South Carolina", "South Dakota", "Tennessee", "Texas",
               "Utah", "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming" ]

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    s = nfs.states
    assert_equal states.sort, s.keys.sort
    assert_equal 19, s["California"]
    assert_equal 15, s["Nevada"]

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    s = nfs.build_state_list
    assert_equal states.sort, s.keys.sort
    assert_equal 19, s["California"]
    assert_equal 15, s["Nevada"]
  end

  def test_forest_list
    nevada_forests = [ "Eldorado National Forest", "Humboldt-Toiyabe National Forest",
                       "Lake Tahoe Basin Management Unit" ]

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.forests_for_state('Nevada')
    assert_equal nevada_forests.sort, f.keys.sort

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.forests_for_state('NV')
    assert_equal nevada_forests.sort, f.keys.sort

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.build_forest_list('Nevada')
    assert_equal nevada_forests.sort, f.keys.sort

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.forests_for_state('NotAState')
    assert_equal Hash.new, f

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.forests_for_state('NS')
    assert_equal Hash.new, f

    # No national forests in Rhode Island

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.forests_for_state('Rhode Island')
    assert_equal Hash.new, f

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    f = nfs.forests_for_state('RI')
    assert_equal Hash.new, f
  end

  def test_forest_pages
    nfs = Cf::Scrubber::Usda::NationalForestService.new
    home = nfs.get_forest_home_page('California', 'Tahoe National Forest')
    assert home.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/tahoe', home.uri.to_s

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    home = nfs.get_forest_home_page('California', 'Unknown National Forest')
    assert home.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.fed.us/', home.uri.to_s

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    rec = nfs.get_forest_secondary_page('California', 'Tahoe National Forest', 'Recreation')
    assert rec.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/recmain/tahoe/recreation', rec.uri.to_s
    rec = nfs.get_forest_recreation_page('California', 'Tahoe National Forest')
    assert rec.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/recmain/tahoe/recreation', rec.uri.to_s

    learn = nfs.get_forest_secondary_page('California', 'Tahoe National Forest', 'Learning Center')
    assert learn.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/main/tahoe/learning', learn.uri.to_s

    nfs = Cf::Scrubber::Usda::NationalForestService.new
    candc = nfs.get_forest_recreation_subpage('California', 'Tahoe National Forest', 'Camping & Cabins')
    assert candc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins', candc.uri.to_s
    candc = nfs.get_forest_camping_page('California', 'Tahoe National Forest')
    assert candc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins', candc.uri.to_s

    cc = nfs.get_forest_camping_subpage('California', 'Tahoe National Forest', 'Campground Camping')
    assert cc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins/?recid=55444&actid=29', cc.uri.to_s

    gc = nfs.get_forest_camping_subpage('California', 'Tahoe National Forest', 'Group Camping')
    assert gc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins/?recid=55444&actid=33', gc.uri.to_s

    cc = nfs.get_forest_camping_subpage('California', 'Tahoe National Forest', 'Cabin Rentals')
    assert cc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins/?recid=55444&actid=101', cc.uri.to_s

    cc = nfs.get_forest_camping_subpage('California', 'Tahoe National Forest', 'RV Camping')
    assert cc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins/?recid=55444&actid=31', cc.uri.to_s
  end

  TAHOE_NF_CAMP_TYPES = {
    # Bowman Road
    'Bowman Campground' => [ :standard ],
    'Canyon Creek Campground' => [ :standard ],
    'Carr Lake Campground' => [ :standard ],
    'Grouse Ridge Campground' => [ :standard ],
    'Jackson Creek Campground' => [ :standard ],
    'Lindsey Lake Campground' => [ :standard ],
    'Lindsey Lake Trail' => [ :standard ],

    # Foresthill Divide Road
    'Big Reservoir Campground' => [ :standard, :group ],
    'Giant Gap Campground' => [ :standard ],
    'Joshua M. Hardt Memorial Trail at Sugar Pine' => [ :standard ],
    'Mumford Bar Campground' => [ :standard ],
    'Robinson Flat Campground' => [ :standard ],
    'Shirttail Campground' => [ :standard ],

    # Gold Lake Road
    'Berger Campground' => [ :standard ],
    'Diablo Campground' => [ :standard ],
    'Packsaddle Campground' => [ :standard ],
    'Salmon Creek Campground' => [ :standard ],
    'Sardine Campground' => [ :standard ],
    'Snag Lake Campground' => [ :standard ],

    # Hiway 20
    'Skillman Horse Campground' => [ :standard, :group ],
    'White Cloud Campground' => [ :standard ],

    # Highway 49
    'Cal Ida Campground' => [ :standard ],
    'Carlton Flat Campground' => [ :standard ],
    'Chapman Creek Campground' => [ :standard ],
    'Fiddle Creek Campground' => [ :standard ],
    'Indian Valley Campground' => [ :standard ],
    'Loganville Campground' => [ :standard ],
    'Ramshorn Campground' => [ :standard ],
    'Rocky Rest Campground' => [ :standard ],
    'Sierra Campground' => [ :standard ],
    'Union Flat Campground' => [ :standard ],
    'Wild Plum Campground' => [ :standard ],
    'Yuba Pass Campground' => [ :standard ],

    # Highway 89, North
    'Bear Valley Campground' => [ :standard, :rv ],
    'Cold Creek Campground' => [ :standard, :rv ],
    'Cottonwood Creek Campground' => [ :standard, :rv ],
    'East Meadow Campground' => [ :standard, :rv ],
    'Findley Campground' => [ :standard, :rv ],
    'Fir Top Campground' => [ :standard, :rv ],
    'Jackson Point Boat In Campground' => [ :standard ],
    'Lake of the Woods' => [ :standard ],
    'Lakeside Campground' => [ :standard ],
    'Lower Little Truckee Campground' => [ :standard, :rv ],
    'Meadow Lake Campground' => [ :standard ],
    'Pass Creek Campground' => [ :standard, :rv ],
    'Prosser Family Campground' => [ :standard ],
    'Prosser Reservoir - Water Recreation' => [ :standard, :rv ],
    'Sagehen Creek Campground' => [ :standard ],
    'Upper Little Truckee Campground' => [ :standard, :group, :rv ],
    'White Rock Lake' => [ :standard ],
    'Woodcamp Campground' => [ :standard, :rv ],

    # Highway 89, South
    'Goose Meadow Campground' => [ :standard ],
    'Granite Flat Campground' => [ :standard ],
    'Silver Creek Campground' => [ :standard ],

    # Interstate 80
    'Boca Campground' => [ :standard ],
    'Boca Reservoir - Water Recreation' => [ :standard ],
    'Boca Rest Campground' => [ :standard ],
    'Boca Springs Campground' => [ :standard ],
    'Boyington Mill Campground' => [ :standard ],
    'Hampshire Rocks Campground' => [ :standard ],
    'Indian Springs Campground' => [ :standard ],
    'Logger Campground' => [ :standard ],
    'North Fork Campground' => [ :standard ],
    'Onion Valley Campground' => [ :standard ],
    'Pierce Creek Campground' => [ :standard ],
    'Stampede Reservoir - Water Recreation' => [ :standard, :group ],
    'Sterling Lake Campground' => [ :standard ],
    'Woodchuck Campground' => [ :standard ],

    # Marysville Road
    'Bullards Lakeshore Campground' => [ :standard ],
    'Dark Day Campground' => [ :standard ],
    'Frenchy Point Campground' => [ :standard ],
    'Garden Point Campground' => [ :standard ],
    'Madrone Cove Campground' => [ :standard ],
    'Schoolhouse Campground' => [ :standard ],

    # Mosquito Ridge Road
    'Ahart Campground' => [ :standard ],
    'French Meadows Campground' => [ :standard ],
    'Lewis Campground' => [ :standard ],
    'Poppy Campground' => [ :standard ],
    'Talbot Campground' => [ :standard ],

    # Bowman Road (group)
    'Faucherie Group Campground' => [ :group ],

    # Foresthill Divide Road (group)
    'Forbes Group Campground' => [ :group ],

    # Highway 89, North (group)
    'Aspen Group Camp' => [ :group ],
    'Meadow Knolls Group Camp' => [ :group ],
    'Prosser Ranch Group Campground' => [ :group ],
    'Silver Tip Group Campground' => [ :group ],

    # Interstate 80 (group)
    'Big Bend Group Campground' => [ :group ],
    'Emigrant Group Campground' => [ :group ],
    'Tunnel Mills Group Campground' => [ :group ],

    # Marysville Road (group)
    'Hornswoggle Group Campground' => [ :group ],

    # Mosquito Ridge Road (group)
    'Coyote Group Campground' => [ :group ],
    'Gates Group Campground' => [ :group ],

    # Highway 89, North (cabin)
    'Calpine Fire Lookout' => [ :cabin ]
  }

  CHATTAHOOCHEE_NF_CAMP_TYPES = {
    # Blue Ridge Ranger District
    'Cooper Creek Recreation Area' => [ :standard ],
    'DeSoto Falls Recreation Area' => [ :standard ],
    'Deep Hole Recreation Area' => [ :standard ],
    'Dockery Lake Recreation Area' => [ :standard ],
    'Frank Gross Recreation Area' => [ :standard ],
    'Jake and Bull Mountain Trail System' => [ :standard ],
    'Lake Winfield Scott Campground' => [ :standard, :group, :cabin ],
    'Morganton Point Campground' => [ :standard ],
    'Mulky Campground' => [ :standard ],
    'Toccoa River Sandy Bottoms Recreation Area' => [ :standard ],

    # Chattooga River District
    'Andrews Cove Campground' => [ :standard ],
    'Lake Rabun Beach Recreation Area' => [ :standard, :group, :rv ],
    'Lake Russell Recreation Area' => [ :standard ],
    'Low Gap Campground' => [ :standard ],
    'Sandy Bottoms Campground' => [ :standard ],
    'Sarah\'s Creek Campground' => [ :standard ],
    'Tallulah River Campground' => [ :standard ],
    'Tate Branch Campground' => [ :standard ],
    'Upper Chattahoochee River Campground' => [ :standard, :group ],
    'West Fork Campground' => [ :standard ],
    'Wildcat Creek Campground #1 Lower' => [ :standard ],
    'Wildcat Creek Campground #2 Upper' => [ :standard ],

    # Conasauga Ranger District
    'Cottonwood Patch Campground' => [ :standard ],
    'Hickey Gap Campground' => [ :standard ],
    'Houston Valley OHV Trails' => [ :standard ],
    'Jacks River Fields Campground' => [ :standard ],

    # Lake Conasauga
    'Lake Conasauga Overflow Campground' => [ :standard ],

    'The Pocket Recreation Area' => [ :standard ],

    # Oconee Ranger District
    'Lake Sinclair Recreation Area' => [ :standard, :group, :rv ],
    'Oconee River Campground' => [ :standard ],

    # Nancytown (group)
    'Nancytown Group Campground' => [ :group ],
    'Pear Tree Hill Group Camp' => [ :group ],

    # Conasauga Ranger District (group)
    'Ball Field Dispersed Camping Area' => [ :group ]
  }

  # Alabama's Nonecuh National Forest 'Camping & Cabins' page only has 'Campground Camping'
  # and 'RV Camping' entries.
  # Also, all forests are linked to a single page that covers 'National Forests in Alabama'
  # and the campgrounds are arranged under specific national forest headings in the list e.g.
  # Talladega National Forest
  #   Shoal Creek Ranger District
  #     Coleman Lake Recreation Area

  NONECUH_NF_CAMP_TYPES = {
    # Technically in Bankhead
    'Brushy Lake Recreation Area' => [ :standard ],
    'Clear Creek Recreation Area' => [ :standard, :rv ],
    'Corinth Recreation Area' => [ :standard, :rv ],
    'Houston Recreation Area' => [ :standard ],
    'McDougle Camp' => [ :standard ],
    'Wolf Pen Hunters Camp' => [ :standard ],

    # Technically in Nonecuh
    'Open Pond Recreation Area' => [ :standard, :rv ],

    # Technically in Talladega
    'Hunting Camps (10 sites)' => [ :standard ],
    'Payne Lake Recreation Area' => [ :standard, :rv ],

    'Big Oak Physically Disabled Hunting Camp' => [ :standard ],
    'Coleman Lake Recreation Area' => [ :standard, :rv ],
    'Hunting Camps (4 sites)' => [ :standard ],
    'Pine Glen Recreation Area' => [ :standard ],

    'Hunter Camps (7 sites)' => [ :standard ],
    'Turnipseed Campground' => [ :standard ],

    # Technically in Tuskegee
    'Hunting Camps (14 sites)' => [ :standard ]
  }
 
  def test_campgrounds_list
    nfs = Cf::Scrubber::Usda::NationalForestService.new

    cl = nfs.get_forest_campgrounds('California', 'Tahoe National Forest')
    c_names = cl.map { |c| c[:name] }
    assert_equal TAHOE_NF_CAMP_TYPES.keys.sort, c_names.sort
    c_types = { }
    cl.each { |c| c_types[c[:name]] = c[:types] }
    cl.each do |c|
      assert_equal TAHOE_NF_CAMP_TYPES[c[:name]], c[:types], "Comparing campground types for '#{c[:name]}'"
    end

    standard_x = TAHOE_NF_CAMP_TYPES.keys.sort.select { |ck| TAHOE_NF_CAMP_TYPES[ck].include?(:standard) }
    cl = nfs.get_forest_campgrounds('California', 'Tahoe National Forest', [ :standard ])
    c_names = cl.map { |c| c[:name] }
    assert_equal standard_x, c_names.sort

    cl = nfs.get_forest_campgrounds('Georgia', 'Chattahoochee-Oconee National Forest')
    c_names = cl.map { |c| c[:name] }
    assert_equal CHATTAHOOCHEE_NF_CAMP_TYPES.keys.sort, c_names.sort
    c_types = { }
    cl.each { |c| c_types[c[:name]] = c[:types] }
    cl.each do |c|
      assert_equal CHATTAHOOCHEE_NF_CAMP_TYPES[c[:name]], c[:types], "Comparing campground types for '#{c[:name]}'"
    end

    cl = nfs.get_forest_campgrounds('California', 'Tahoe National Forest', nil, true)
    c_names = cl.map { |c| c[:name] }
    assert_equal TAHOE_NF_CAMP_TYPES.keys.sort, c_names.sort

    c = cl.find { |e| e[:name] == 'Prosser Family Campground' }
    assert c.is_a?(Hash)
    assert c[:location].is_a?(Hash)
    assert_equal 39.377866, c[:location][:lat]
    assert_equal -120.161783, c[:location][:lon]
    assert_equal 5800, c[:location][:elevation]

    cl = nfs.get_forest_campgrounds('Alabama', 'Conecuh National Forest')
    c_names = cl.map { |c| c[:name] }
    assert_equal NONECUH_NF_CAMP_TYPES.keys.sort, c_names.sort
    c_types = { }
    cl.each { |c| c_types[c[:name]] = c[:types] }
    cl.each do |c|
      assert_equal NONECUH_NF_CAMP_TYPES[c[:name]], c[:types], "Comparing campground types for '#{c[:name]}'"
    end
  end

  def test_campgrounds_script
    script = TestCampgroundsScript.new()
    script.parser.parse([ '--states=CA', '--forests=Tahoe National Forest' ])
    script.exec
    c_names = script.campgrounds.map { |c| c[:name] }
    assert_equal TAHOE_NF_CAMP_TYPES.keys.sort, c_names.sort

    group_cabin_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      TAHOE_NF_CAMP_TYPES[ck].any? { |t| (t == :group) || (t == :cabin) }
    end
    script = TestmpgroundsScript.new()
    script.parser.parse([ '--states=CA', '--forests=Tahoe National Forest', '--types=rv,cabin' ])
    script.exec
    c_names = script.parks.map { |c| c[:name] }
    assert_equal group_cabin_x, c_names.sort
  end
end
