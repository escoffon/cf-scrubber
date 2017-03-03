# -*- coding: utf-8 -*-
require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/nv/script'

class TestParkListScript < Cf::Scrubber::Nv::Script::ParkList
  class Parser < Cf::Scrubber::Nv::Script::ParkList::Parser
    def initialize()
      rv = super()

      p = self.parser
      p.banner = "Usage: nv_parks_list_tester [options]\n\nTest list NV state parks"

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

class NVStateParkTest < Minitest::Test
  def test_get_activity_list
    sp = Cf::Scrubber::Nv::StateParks.new
    alist = sp.get_activity_list.map { |a| a[:activity_id].to_s }
    assert_equal Cf::Scrubber::Nv::StateParks::ACTIVITY_CODES.keys.sort, alist.sort
  end

  CAMPS_BY_FEATURE = {
    'boat-launch' => [
                      'Big Bend of the Colorado',
                      'Cave Lake',
                      'Cave Rock',
                      'Echo Canyon',
                      'Lahontan',
                      'Rye Patch',
                      'Sand Harbor',
                      'South Fork',
                      'Spring Valley',
                      'Washoe Lake',
                      'Wild Horse'
                     ],

    'fishing' => [
                  'Beaver Dam',
                  'Big Bend of the Colorado',
                  'Cave Lake',
                  'Cave Rock',
                  'Dayton',
                  'Echo Canyon',
                  'Lahontan',
                  'Rye Patch',
                  'Sand Harbor',
                  'South Fork',
                  'Spooner Lake & Backcountry',
                  'Spring Valley',
                  'Washoe Lake',
                  'Wild Horse'
                ],

    'campsites,equestrian,rv-dump-station' => [
                                               'Berlin-Ichthyosaur',
                                               'Cathedral Gorge',
                                               'Cave Lake',
                                               'Echo Canyon',
                                               'Fort Churchill',
                                               'Lahontan',
                                               'Rye Patch',
                                               'South Fork',
                                               'Spring Valley',
                                               'Washoe Lake',
                                               'Wild Horse'
                                              ]
  }

  def test_activity_list_filter
    sp = Cf::Scrubber::Nv::StateParks.new

    sl = sp.any_park_list([ 'boat-launch' ]).map { |pd| pd[:name] }
    assert_equal CAMPS_BY_FEATURE['boat-launch'].sort, sl.sort

    sl = sp.any_park_list([ 'fishing' ]).map { |pd| pd[:name] }
    assert_equal CAMPS_BY_FEATURE['fishing'].sort, sl.sort

    sl = sp.all_park_list('campsites,equestrian,rv-dump-station'.split(',')).map { |pd| pd[:name] }
    assert_equal CAMPS_BY_FEATURE['campsites,equestrian,rv-dump-station'].sort, sl.sort
  end

  ALL_CAMP_TYPES = {
    'Beaver Dam' => [ :standard ],
    'Berlin-Ichthyosaur' => [ :standard ],
    'Big Bend of the Colorado' => [ :standard ],
    'Cathedral Gorge' => [ :standard, :rv ],
    'Cave Lake' => [ :standard, :cabin ],
    'Dayton' => [ :standard ],
    'Echo Canyon' => [ :standard, :rv ],
    'Fort Churchill' => [ :standard ],
    'Kershaw-Ryan' => [ :standard ],
    'Lahontan' => [ :standard, :rv ],
    'Rye Patch' => [ :standard ],
    'South Fork' => [ :standard, :rv ],
    'Spooner Lake & Backcountry' => [ :cabin ],
    'Spring Valley' => [ :standard ],
    'Valley of Fire' => [ :standard, :rv ],
    'Ward Charcoal Ovens' => [ :standard ],
    'Washoe Lake' => [ :standard ],
    'Wild Horse' => [ :standard ]
  }

  def test_campgrounds_list
    sp = Cf::Scrubber::Nv::StateParks.new

    cl = sp.select_campground_list
    c_names = cl.map { |c| c[:name] }
    assert_equal ALL_CAMP_TYPES.keys.sort, c_names.sort
    cl.each do |c|
      assert_equal ALL_CAMP_TYPES[c[:name]], c[:types], "Comparing campground types for '#{c[:name]}'"
    end

    standard_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:standard) }
    cl = sp.select_campground_list([ :standard ])
    c_names = cl.map { |c| c[:name] }
    assert_equal standard_x, c_names.sort

    group_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:group) }
    cl = sp.select_campground_list([ :group ])
    c_names = cl.map { |c| c[:name] }
    assert_equal group_x, c_names.sort

    rv_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:rv) }
    cl = sp.select_campground_list([ :rv ])
    c_names = cl.map { |c| c[:name] }
    assert_equal rv_x, c_names.sort

    cabin_x = ALL_CAMP_TYPES.keys.sort.select { |ck| ALL_CAMP_TYPES[ck].include?(:cabin) }
    cl = sp.select_campground_list([ :cabin ])
    c_names = cl.map { |c| c[:name] }
    assert_equal cabin_x, c_names.sort

    group_rv_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :group) || (t == :rv) }
    end
    cl = sp.select_campground_list([ :group, :rv ])
    c_names = cl.map { |c| c[:name] }
    assert_equal group_rv_x, c_names.sort

    rv_cabin_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :rv) || (t == :cabin) }
    end
    cl = sp.select_campground_list([ :rv, :cabin ])
    c_names = cl.map { |c| c[:name] }
    assert_equal rv_cabin_x, c_names.sort

    rv_group_cabin_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].any? { |t| (t == :rv) || (t == :group) || (t == :cabin) }
    end
    cl = sp.select_campground_list([ :rv, :group, :cabin ])
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
