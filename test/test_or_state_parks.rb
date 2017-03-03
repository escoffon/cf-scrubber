# -*- coding: utf-8 -*-
require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/or/script'

class TestParkListScript < Cf::Scrubber::Or::Script::ParkList
  class Parser < Cf::Scrubber::Or::Script::ParkList::Parser
    def initialize()
      rv = super()

      p = self.parser
      p.banner = "Usage: or_parks_list_tester [options]\n\nTest list OR state parks"

      rv
    end
  end

  def initialize()
    super(TestParkListScript::Parser.new)
  end

  def parks()
    @parks
  end

  def exec()
    @parks = [ ]
    self.process do |sp, pd|
      @parks << pd
    end
  end
end

class ORStateParkTest < Minitest::Test
  ALL_CAMP_TYPES = {
    'Ainsworth State Park' => [ :standard, :rv ],
    'Alfred A. Loeb State Park' => [ :standard, :cabin, :rv ],
    'Bates State Park' => [ :standard ],
    'Beachside State Recreation Site' => [ :standard, :cabin, :rv ],
    'Beverly Beach State Park' => [ :standard, :cabin, :rv ],
    'Bullards Beach State Park' => [ :standard, :cabin, :rv ],
    'Cape Blanco State Park' => [ :standard, :cabin, :rv ],
    'Cape Lookout State Park' => [ :standard, :cabin, :rv ],
    'Carl G. Washburne Memorial State Park' => [ :standard, :cabin, :rv ],
    'Cascadia State Park' => [ :standard ],
    'Catherine Creek State Park' => [ :standard, :rv ],
    'Champoeg State Heritage Area' => [ :standard, :cabin, :rv ],
    'Collier Memorial State Park' => [ :standard, :rv ],
    'Cottonwood Canyon State Park' => [ :standard ],
    'Deschutes River State Recreation Area' => [ :standard, :rv ],
    'Detroit Lake State Recreation Area' => [ :standard, :rv ],
    'Devil\'s Lake State Recreation Area' => [ :standard, :cabin, :rv ],
    'Emigrant Springs State Heritage Area' => [ :standard, :cabin, :rv ],
    'Fall Creek State Recreation Area' => [ :standard, :rv ],
    'Farewell Bend State Recreation Area' => [ :standard, :cabin, :rv ],
    'Fort Stevens State Park' => [ :standard, :cabin, :rv ],
    'Goose Lake State Recreation Area' => [ :standard, :rv ],
    'Government Island State Recreation Area' => [ :standard ],
    'Harris Beach State Park' => [ :standard, :cabin, :rv ],
    'Hilgard Junction State Park' => [ :standard, :rv ],
    'Humbug Mountain State Park' => [ :standard, :rv ],
    'Jackson F. Kimball State Recreation Site' => [ :standard ],
    'Jasper Point (Prineville Reservoir)' => [ :standard, :cabin, :rv ],
    'Jessie M. Honeyman Memorial State Park' => [ :standard, :cabin, :rv ],
    'Joseph H. Stewart State Recreation Area' => [ :standard, :rv ],
    'L.L. Stub Stewart State Park' => [ :standard, :cabin, :rv ],
    'LaPine State Park' => [ :standard, :cabin, :rv ],
    'Lake Owyhee State Park' => [ :standard, :cabin, :rv ],
    'Memaloose State Park' => [ :standard, :rv ],
    'Milo McIver State Park' => [ :standard, :rv ],
    'Minam State Recreation Area' => [ :standard, :rv ],
    'Nehalem Bay State Park' => [ :standard, :cabin, :rv ],
    'Prineville Reservoir State Park' => [ :standard, :cabin, :rv ],
    'Red Bridge State Wayside' => [ :standard, :rv ],
    'Saddle Mountain State Natural Area' => [ :standard ],
    'Silver Falls State Park' => [ :standard, :cabin, :rv ],
    'Smith Rock State Park' => [ :standard ],
    'South Beach State Park' => [ :standard, :cabin, :rv ],
    'Succor Creek State Natural Area' => [ :standard ],
    'Sunset Bay State Park' => [ :standard, :cabin, :rv ],
    'The Cove Palisades State Park' => [ :standard, :cabin, :rv ],
    'Tumalo State Park' => [ :standard, :cabin, :rv ],
    'Ukiah-Dale Forest State Scenic Corridor' => [ :standard ],
    'Umpqua Lighthouse State Park' => [ :standard, :cabin, :rv ],
    'Valley of the Rogue State Park' => [ :standard, :cabin, :rv ],
    'Viento State Park' => [ :standard, :rv ],
    'Wallowa Lake State Park' => [ :standard, :cabin, :rv ],
    'Willamette Mission State Park' => [ :standard ],
    'Clyde Holliday State Recreation Site' => [ :standard, :cabin, :rv ],
    'North Santiam State Recreation Area' => [ :standard ],
    'Unity Lake State Recreation Site' => [ :standard, :cabin, :rv ],
    'William M. Tugman State Park' => [ :standard, :cabin, :rv ],
    'Frenchglen Hotel State Heritage Site' => [ :cabin ]
  }

  def test_campgrounds_list
    sp = Cf::Scrubber::Or::StateParks.new

    cl = sp.build_overnight_park_list
    c_names = cl.map { |c| c[:name] }
    assert_equal ALL_CAMP_TYPES.keys.sort, c_names.sort
    cl.each do |c|
      assert_equal ALL_CAMP_TYPES[c[:name]], c[:types], "Comparing campground types for '#{c[:name]}'"
    end

    standard_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:standard) }
    cl = sp.build_overnight_park_list([ :standard ])
    c_names = cl.map { |c| c[:name] }
    assert_equal standard_x, c_names.sort

    group_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:group) }
    cl = sp.build_overnight_park_list([ :group ])
    c_names = cl.map { |c| c[:name] }
    assert_equal group_x, c_names.sort

    rv_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:rv) }
    cl = sp.build_overnight_park_list([ :rv ])
    c_names = cl.map { |c| c[:name] }
    assert_equal rv_x, c_names.sort

    cabin_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:cabin) }
    cl = sp.build_overnight_park_list([ :cabin ])
    c_names = cl.map { |c| c[:name] }
    assert_equal cabin_x, c_names.sort

    group_rv_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :group) || (t == :rv) }
    end
    cl = sp.build_overnight_park_list([ :group, :rv ])
    c_names = cl.map { |c| c[:name] }
    assert_equal group_rv_x, c_names.sort

    rv_cabin_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :rv) || (t == :cabin) }
    end
    cl = sp.build_overnight_park_list([ :rv, :cabin ])
    c_names = cl.map { |c| c[:name] }
    assert_equal rv_cabin_x, c_names.sort

    rv_group_cabin_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :rv) || (t == :group) || (t == :cabin) }
    end
    cl = sp.build_overnight_park_list([ :rv, :group, :cabin ])
    c_names = cl.map { |c| c[:name] }
    assert_equal rv_group_cabin_x, c_names.sort
  end

  def test_campgrounds_script
    script = TestParkListScript.new()
    script.parser.parse([ ])
    script.exec
    c_names = script.parks.map { |c| c[:name] }
    assert_equal ALL_CAMP_TYPES.keys.sort, c_names.sort

    rv_cabin_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :rv) || (t == :cabin) }
    end
    script = TestParkListScript.new()
    script.parser.parse([ '--types=rv,cabin' ])
    script.exec
    c_names = script.parks.map { |c| c[:name] }
    assert_equal rv_cabin_x, c_names.sort
  end
end
