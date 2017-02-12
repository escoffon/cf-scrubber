require 'minitest/autorun'
require 'cf/scrubber'

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
    cc = nfs.get_forest_campgrounds_page('California', 'Tahoe National Forest')
    assert cc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins/?recid=55444&actid=29', cc.uri.to_s

    gc = nfs.get_forest_camping_subpage('California', 'Tahoe National Forest', 'Group Camping')
    assert gc.is_a?(Net::HTTPOK)
    assert_equal 'https://www.fs.usda.gov/activity/tahoe/recreation/camping-cabins/?recid=55444&actid=33', gc.uri.to_s
  end

  def test_campgrounds_list
    nfs = Cf::Scrubber::Usda::NationalForestService.new
    cl = nfs.get_forest_campgrounds('California', 'Tahoe National Forest')
    c0 = cl[0]
    assert c0[:area]
    assert_equal 'Bowman Road', c0[:name]
    c1 = cl[1]
    assert !c1[:area]
    assert_equal 'Bowman Campground', c1[:name]
    assert !c1.has_key?(:location)
    assert !c1.has_key?(:additional_info)

    cl = nfs.get_forest_campgrounds('California', 'Tahoe National Forest', true)
    c0 = cl[0]
    assert c0[:area]
    assert_equal 'Bowman Road', c0[:name]
    c1 = cl[1]
    assert !c1[:area]
    assert_equal 'Bowman Campground', c1[:name]
    assert c1.has_key?(:location)
    assert c1.has_key?(:additional_info)
    loc = c1[:location]
    assert_equal 39.459317, loc[:lat]
    assert_equal -120.612392, loc[:lon]
    x = c1[:additional_info]
    assert_equal 'No', x[:reservations]
  end
end
