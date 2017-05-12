# -*- coding: utf-8 -*-
require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/ga/script'

class TestParkListScript < Cf::Scrubber::Ga::Script::ParkList
  class Parser < Cf::Scrubber::Ga::Script::ParkList::Parser
    def initialize()
      rv = super()

      p = self.parser
      p.banner = "Usage: ga_parks_list_tester [options]\n\nTest list GA state parks"

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

class GAStateParkTest < Minitest::Test
  def test_get_activity_list
    sp = Cf::Scrubber::Ga::StateParks.new
    alist = sp.get_activity_list.map { |ak, av| ak.to_s }
    assert_equal Cf::Scrubber::Ga::StateParks::ACTIVITY_CODES.keys.sort, alist.sort
  end

  ALL_CAMP_TYPES = {
    'A.H. Stephens State Park' => [:cabin, :standard, :group],
    'Amicalola Falls State Park and Lodge' => [:cabin, :standard],
    'Black Rock Mountain State Park' => [:cabin, :standard, :group],
    'Chattahoochee Bend State Park' => [:standard],
    'Chief Vann House Historic Site' => [],
    'Cloudland Canyon State Park' => [:cabin, :standard, :group],
    'Crooked River State Park' => [:cabin, :standard, :group],
    'Dahlonega Gold Museum Historic Site' => [],
    'Don Carter State Park' => [:cabin, :standard],
    'Elijah Clark State Park' => [:cabin, :standard, :group],
    'Etowah Indian Mounds Historic Site' => [],
    'F.D. Roosevelt State Park' => [:cabin, :standard, :group],
    'Florence Marina State Park' => [:cabin, :standard],
    'Fort King George Historic Site' => [],
    'Fort McAllister State Park' => [:cabin, :standard, :group],
    'Fort Morris Historic Site' => [],
    'Fort Mountain State Park' => [:cabin, :standard, :group],
    'Fort Yargo State Park' => [:cabin, :standard, :group],
    'General Coffee State Park' => [:cabin, :standard, :group],
    'George L. Smith State Park' => [:cabin, :standard, :group],
    'George T. Bagby State Park and Lodge' => [:cabin],
    'Georgia Veterans State Park & Resort' => [:cabin, :standard, :group],
    'Gordonia-Alatamaha State Park' => [:cabin, :standard],
    'Hamburg State Park' => [:standard, :group],
    'Hard Labor Creek State Park' => [:cabin, :standard, :group],
    'Hardman Farm Historic Site' => [],
    'Hart Outdoor Recreation Area' => [:standard],
    'High Falls State Park' => [:cabin, :standard, :group],
    'Hofwyl-Broadfield Plantation Historic Site' => [],
    'Indian Springs State Park' => [:cabin, :standard, :group],
    'James H. (Sloppy) Floyd State Park' => [:cabin, :standard, :group],
    'Jarrell Plantation Historic Site' => [],
    'Jefferson Davis Memorial Historic Site' => [],
    'Kolomoki Mounds State Park' => [:standard, :group],
    'Lapham-Patterson House Historic Site' => [],
    'Laura S. Walker State Park' => [:standard, :group],
    'Len Foote Hike Inn at Amicalola Falls' => [:cabin],
    'Little Ocmulgee State Park and Lodge' => [:cabin, :standard, :group],
    'Magnolia Springs State Park' => [:cabin, :standard, :group],
    'Mistletoe State Park' => [:cabin, :standard, :group],
    'Moccasin Creek State Park' => [:standard],
    'New Echota Historic Site' => [],
    'Panola Mountain State Park' => [:standard],
    'Pickett\'s Mill Battlefield Historic Site' => [],
    'Providence Canyon Outdoor Recreation Area' => [:standard, :group],
    'Red Top Mountain State Park' => [:cabin, :standard, :group],
    'Reed Bingham State Park' => [:standard, :group],
    'Sapelo Island and Reynolds Mansion' => [:cabin, :group],
    'Richard B. Russell State Park' => [:cabin, :standard],
    'Robert Toombs House Historic Site' => [],
    'Rocky Mountain Recreation & Public Fishing Area' => [],
    'Roosevelt\'s Little White House Historic Site' => [],
    'SAM Shortline Excursion Train' => [],
    'Seminole State Park' => [:cabin, :standard, :group],
    'Skidaway Island State Park' => [:standard, :cabin, :group],
    'Smithgall Woods State Park' => [:cabin, :group],
    'Stephen C. Foster State Park' => [:cabin, :standard, :group],
    'Sweetwater Creek State Park' => [:cabin, :standard],
    'Tallulah Gorge State Park' => [:standard, :group],
    'Traveler\'s Rest Historic Site' => [],
    'Tugaloo State Park' => [:cabin, :standard],
    'Unicoi State Park and Lodge' => [:cabin, :standard],
    'Victoria Bryant State Park' => [:cabin, :standard, :group],
    'Vogel State Park' => [:cabin, :standard, :group],
    'Watson Mill Bridge State Park' => [:standard, :group],
    'Wormsloe Historic Site' => []
  }

  def test_campgrounds_list
    sp = Cf::Scrubber::Ga::StateParks.new

    cl = sp.build_full_park_list
    c_names = cl.map { |c| c[:name] }
    assert_equal ALL_CAMP_TYPES.keys.sort, c_names.sort
    cl.each do |c|
      assert_equal ALL_CAMP_TYPES[c[:name]], c[:types], "Comparing campground types for '#{c[:name]}'"
    end
  end

  def test_campgrounds_script
    script = TestParkListScript.new()
    script.parser.parse([ '--all' ])
    script.exec
    c_names = script.parks.map { |c| c[:name] }
    assert_equal ALL_CAMP_TYPES.keys.sort, c_names.sort

    rv_camp_x = ALL_CAMP_TYPES.keys.sort.select do |ck|
      ALL_CAMP_TYPES[ck].count > 0
    end
    script = TestParkListScript.new()
    script.parser.parse([ ])
    script.exec
    c_names = script.parks.map { |c| c[:name] }
    assert_equal rv_camp_x, c_names.sort

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
