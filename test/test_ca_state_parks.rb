# -*- coding: utf-8 -*-
require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/ca/script'

class TestParkListScript < Cf::Scrubber::Ca::Script::ParkList
  class Parser < Cf::Scrubber::Ca::Script::ParkList::Parser
    def initialize()
      rv = super()

      p = self.parser
      p.banner = "Usage: ca_parks_list_tester [options]\n\nTest list CA state parks"

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

class CAStateParkTest < Minitest::Test
  def test_get_activity_list
    sp = Cf::Scrubber::Ca::StateParks.new
    alist = sp.get_activity_list.map { |a| a[:activity_id] }
    assert_equal Cf::Scrubber::Ca::StateParks::ACTIVITY_CODES.keys.sort, alist.sort
  end

  CAMPS_BY_FEATURE = {
    # 104 : Boat Ramps
    '104' => [
              'Ahjumawi Lava Springs State Park',
              'Angel Island State Park',
              'Bethany Reservoir State Recreation Area',
              'Bidwell-Sacramento River State Park',
              'Brannan Island State Recreation Area',
              'Castaic Lake State Recreation Area',
              'China Camp State Park',
              'Clear Lake State Park',
              'Colusa-Sacramento River State Recreation Area',
              'Folsom Lake State Recreation Area',
              'Great Valley Grasslands State Park',
              'Hearst San Simeon State Park',
              'Humboldt Lagoons State Park',
              'Jedediah Smith Redwoods State Park',
              'Lake Del Valle State Recreation Area',
              'Lake Oroville State Recreation Area',
              'Lake Perris State Recreation Area',
              'Marconi Conference Center State Historic Park',
              'McArthur-Burney Falls Memorial State Park',
              'Mendocino Headlands State Park',
              'Millerton Lake State Recreation Area',
              'Morro Bay State Park',
              'Picacho State Recreation Area',
              'Salton Sea State Recreation Area',
              'San Luis Reservoir State Recreation Area',
              'Silverwood Lake State Recreation Area',
              'Sonoma Coast State Park',
              'Tolowa Dunes  State Park',
              'Tomales Bay State Park',
              'Turlock Lake State Recreation Area'
            ],

    # Horseback Riding
    '110' => [
           'Andrew Molera State Park',
           'Anza-Borrego Desert State Park',
           'Armstrong Redwoods State Natural Reserve',
           'Auburn State Recreation Area',
           'Austin Creek State Recreation Area',
           'Big Basin Redwoods State Park',
           'Border Field State Park',
           'Burleigh H. Murray Ranch Park Property',
           'Butano State Park',
           'Castaic Lake State Recreation Area',
           'Castle Crags State Park',
           'Castle Rock State Park',
           'China Camp State Park',
           'Chino Hills State Park',
           'Colonel Allensworth State Historic Park',
           'Colusa-Sacramento River State Recreation Area',
           'Crystal Cove State Park',
           'Cuyamaca Rancho State Park',
           'Del Norte Coast Redwoods State Park',
           'Empire Mine State Historic Park',
           'Folsom Lake State Recreation Area',
           'Gaviota State Park',
           'Half Moon Bay State Beach',
           'Heber Dunes State Vehicular Recreation Area',
           'Henry Cowell Redwoods State Park',
           'Henry W. Coe State Park',
           'Humboldt Redwoods State Park',
           'Hungry Valley State Vehicular Recreation Area',
           'Indio Hills Palms Park Property',
           'Jack London State Historic Park',
           'Jedediah Smith Redwoods State Park',
           'Kenneth Hahn State Recreation Area',
           'La Purísima Mission State Historic Park',
           'Lake Del Valle State Recreation Area',
           'Lake Oroville State Recreation Area',
           'Lake Perris State Recreation Area',
           'Little River State Beach',
           'Los Angeles State Historic Park',
           'MacKerricher State Park',
           'Malakoff Diggins State Historic Park',
           'Malibu Creek State Park',
           'McArthur-Burney Falls Memorial State Park',
           'Mendocino Headlands State Park',
           'Millerton Lake State Recreation Area',
           'Monta&ntilde;a de Oro State Park',
           'Montara State Beach',
           'Morro Strand State Beach',
           'Moss Landing State Beach',
           'Mount Diablo State Park',
           'Mount San Jacinto State Park',
           'Mount Tamalpais State Park',
           'Oceano Dunes State Vehicular Recreation Area',
           'Ocotillo Wells State Vehicular Recreation Area',
           'Old Sacramento State Historic Park',
           'Olompali State Historic Park',
           'Pacheco State Park',
           'Pismo State Beach',
           'Point Mugu State Park',
           'Red Rock Canyon State Park',
           'Russian Gulch State Park',
           'Saddleback Butte State Park',
           'Salinas River State Beach',
           'Samuel P. Taylor State Park',
           'San Bruno Mountain State Park',
           'San Luis Reservoir State Recreation Area',
           'San Timoteo Canyon Park Property',
           'Santa Susana Pass State Historic Park',
           'Silverwood Lake State Recreation Area',
           'Sinkyone Wilderness State Park',
           'Sonoma Coast State Park',
           'Sugarloaf Ridge State Park',
           'Tolowa Dunes  State Park',
           'Topanga State Park',
           'Trione-Annadel State Park',
           'Wilder Ranch State Park',
           'Wildwood Canyon Park Property',
           'Will Rogers State Historic Park',
           'Woodson Bridge State Recreation Area'
          ],

    # Family Campsites, Group Campsites, Horseback Riding
    '83,84,110' => [
                    'Anza-Borrego Desert State Park',
                    'Big Basin Redwoods State Park',
                    'Castaic Lake State Recreation Area',
                    'Chino Hills State Park',
                    'Colusa-Sacramento River State Recreation Area',
                    'Cuyamaca Rancho State Park',
                    'Folsom Lake State Recreation Area',
                    'Half Moon Bay State Beach',
                    'Henry W. Coe State Park',
                    'Humboldt Redwoods State Park',
                    'Hungry Valley State Vehicular Recreation Area',
                    'Lake Del Valle State Recreation Area',
                    'Lake Oroville State Recreation Area',
                    'Lake Perris State Recreation Area',
                    'MacKerricher State Park',
                    'Malakoff Diggins State Historic Park',
                    'Malibu Creek State Park',
                    'Millerton Lake State Recreation Area',
                    'Mount Diablo State Park',
                    'Mount Tamalpais State Park',
                    'Oceano Dunes State Vehicular Recreation Area',
                    'Ocotillo Wells State Vehicular Recreation Area',
                    'Point Mugu State Park',
                    'Russian Gulch State Park',
                    'Saddleback Butte State Park',
                    'Samuel P. Taylor State Park',
                    'San Luis Reservoir State Recreation Area',
                    'Silverwood Lake State Recreation Area',
                    'Sugarloaf Ridge State Park',
                    'Woodson Bridge State Recreation Area'
                   ]
  }

  def test_activity_list_filter
    sp = Cf::Scrubber::Ca::StateParks.new
    sl = sp.any_park_list([ '104' ]).map { |pd| pd[:name] }
    assert_equal CAMPS_BY_FEATURE['104'].sort, sl.sort

    sl = sp.any_park_list([ '110' ]).map { |pd| pd[:name] }
    assert_equal CAMPS_BY_FEATURE['110'].sort, sl.sort

    sl = sp.all_park_list('83,84,110'.split(',')).map { |pd| pd[:name] }
    assert_equal CAMPS_BY_FEATURE['83,84,110'].sort, sl.sort
  end

  ALL_CAMP_TYPES = {
    'Ahjumawi Lava Springs State Park' => [ :standard ],
    'Andrew Molera State Park' => [ :standard ],
    'Angel Island State Park' => [ :standard, :group ],
    'Anza-Borrego Desert State Park' => [ :standard, :group, :rv, :cabin ],
    'Armstrong Redwoods State Natural Reserve' => [ :rv ],
    'Asilomar State Beach' => [ :cabin ],
    'Auburn State Recreation Area' => [ :standard ],
    'Austin Creek State Recreation Area' => [ :standard ],
    'Benbow State Recreation Area' => [ :standard, :rv ],
    'Benicia State Recreation Area' => [ :rv ],
    'Big Basin Redwoods State Park' => [ :standard, :group, :rv, :cabin ],
    'Bolsa Chica State Beach' => [ :standard, :rv ],
    'Bothe-Napa Valley State Park' => [ :standard, :group, :rv, :cabin ],
    'Brannan Island State Recreation Area' => [ :standard, :group, :rv, :cabin ],
    'Butano State Park' => [ :standard, :rv ],
    'Calaveras Big Trees State Park' => [ :standard, :group, :rv, :cabin ],
    'Carlsbad State Beach' => [ :rv ],
    'Carnegie State Vehicular Recreation Area' => [ :standard, :rv ],
    'Carpinteria State Beach' => [ :standard, :group, :rv ],
    'Castaic Lake State Recreation Area' => [ :standard, :group, :rv ],
    'Castle Crags State Park' => [ :standard, :rv ],
    'Castle Rock State Park' => [ :standard ],
    'Caswell Memorial State Park' => [ :standard, :group, :rv ],
    'China Camp State Park' => [ :standard ],
    'Chino Hills State Park' => [ :standard, :group, :rv ],
    'Clear Lake State Park' => [ :standard, :group, :rv, :cabin ],
    'Colonel Allensworth State Historic Park' => [ :standard, :rv ],
    'Columbia State Historic Park' => [ :rv, :cabin ],
    'Colusa-Sacramento River State Recreation Area' => [ :standard, :group, :rv ],
    'Corona del Mar State Beach' => [ :rv ],
    'Crystal Cove State Park' => [ :standard, :rv, :cabin ],
    'Cuyamaca Rancho State Park' => [ :standard, :group, :rv, :cabin ],
    'D. L. Bliss State Park' => [ :standard, :group, :rv ],
    'Del Norte Coast Redwoods State Park' => [ :standard, :rv ],
    'Dockweiler State Beach' => [ :standard, :rv ],
    'Doheny State Beach' => [ :standard, :group, :rv ],
    'Donner Memorial State Park' => [ :standard, :rv ],
    'Eastern Kern County Onyx Ranch State Vehicular Recreation Area' => [ :standard ],
    'Ed Z\'berg Sugar Pine Point State Park' => [ :standard, :group, :rv ],
    'El Capitán State Beach' => [ :standard, :group, :rv ],
    'Emerald Bay State Park' => [ :standard, :rv ],
    'Emma Wood  State Beach' => [ :standard, :group, :rv ],
    'Folsom Lake State Recreation Area' => [ :standard, :group, :rv ],
    'Fort Ross State Historic Park' => [ :standard, :rv ],
    'Fort Tejon State Historic Park' => [ :standard, :group, :rv ],
    'Fremont Peak State Park' => [ :standard, :group, :rv ],
    'Gaviota State Park' => [ :standard, :rv ],
    'George J. Hatfield State Recreation Area' => [ :standard, :group, :rv ],
    'Grizzly Creek Redwoods State Park' => [ :standard, :group, :rv ],
    'Grover Hot Springs State Park' => [ :standard, :rv ],
    'Half Moon Bay State Beach' => [ :standard, :group, :rv ],
    'Hearst San Simeon State Park' => [ :standard, :rv ],
    'Hendy Woods State Park' => [ :standard, :rv, :cabin ],
    'Henry Cowell Redwoods State Park' => [ :standard, :rv ],
    'Henry W. Coe State Park' => [ :standard, :group, :rv ],
    'Hollister Hills State Vehicular Recreation Area' => [ :standard, :group, :rv ],
    'Humboldt Lagoons State Park' => [ :standard ],
    'Humboldt Redwoods State Park' => [ :standard, :group, :rv ],
    'Hungry Valley State Vehicular Recreation Area' => [ :standard, :group, :rv ],
    'Indian Grinding Rock State Historic Park' => [ :standard, :rv ],
    'Jedediah Smith Redwoods State Park' => [ :standard, :rv, :cabin ],
    'Julia Pfeiffer Burns State Park' => [ :standard ],
    'Kruse Rhododendron State Natural Reserve' => [ :rv ],
    'Lake Del Valle State Recreation Area' => [ :standard, :group, :rv ],
    'Lake Oroville State Recreation Area' => [ :standard, :group, :rv ],
    'Lake Perris State Recreation Area' => [ :standard, :group, :rv ],
    'Leo Carrillo State Park' => [ :standard, :group, :rv ],
    'Limekiln State Park' => [ :standard, :rv ],
    'MacKerricher State Park' => [ :standard, :group, :rv ],
    'Malakoff Diggins State Historic Park' => [ :standard, :group, :rv, :cabin ],
    'Malibu Creek State Park' => [ :standard, :group, :rv ],
    'Manchester State Park' => [ :standard, :group, :rv ],
    'Manresa State Beach' => [ :standard ],
    'Marconi Conference Center State Historic Park' => [ :cabin ],
    'McArthur-Burney Falls Memorial State Park' => [ :standard, :rv, :cabin ],
    'McConnell State Recreation Area' => [ :standard, :group, :rv ],
    'McGrath State Beach' => [ :standard, :group, :rv ],
    'Mendocino Woodlands State Park' => [ :cabin ],
    'Millerton Lake State Recreation Area' => [ :standard, :group, :rv ],
    'Monta&ntilde;a de Oro State Park' => [ :standard, :rv ],
    'Morro Bay State Park' => [ :standard, :group, :rv ],
    'Morro Strand State Beach' => [ :standard, :rv ],
    'Mount Diablo State Park' => [ :standard, :group, :rv ],
    'Mount San Jacinto State Park' => [ :standard, :rv ],
    'Mount Tamalpais State Park' => [ :standard, :group, :cabin ],
    'Navarro River Redwoods State Park' => [ :standard, :rv ],
    'New Brighton State Beach' => [ :standard, :group, :rv ],
    'Oceano Dunes State Vehicular Recreation Area' => [ :standard, :group, :rv ],
    'Ocotillo Wells State Vehicular Recreation Area' => [ :standard, :group, :rv ],
    'Old Sacramento State Historic Park' => [ :rv ],
    'Old Town San Diego State Historic Park' => [ :cabin ],
    'Pacheco State Park' => [ :standard ],
    'Palomar Mountain State Park' => [ :standard, :group, :rv ],
    'Patrick&#39;s Point State Park' => [ :standard, :group, :rv, :cabin ],
    'Pfeiffer Big Sur State Park' => [ :standard, :group, :rv, :cabin ],
    'Picacho State Recreation Area' => [ :standard, :group, :rv ],
    'Pigeon Point Light Station State Historic Park' => [ :cabin ],
    'Pismo State Beach' => [ :standard, :rv ],
    'Placerita Canyon State Park' => [ :group ],
    'Plumas-Eureka State Park' => [ :standard, :group, :rv ],
    'Point Cabrillo Light Station State Historic Park' => [ :cabin ],
    'Point Mugu State Park' => [ :standard, :group, :rv ],
    'Portola Redwoods State Park' => [ :standard, :group, :rv ],
    'Prairie City State Vehicular Recreation Area' => [ :rv ],
    'Prairie Creek Redwoods State Park' => [ :standard, :rv, :cabin ],
    'Providence Mountains State Recreation Area' => [ :standard, :rv ],
    'Red Rock Canyon State Park' => [ :standard, :rv ],
    'Refugio State Beach' => [ :standard, :group, :rv ],
    'Richardson Grove State Park' => [ :standard, :group, :rv ],
    'Russian Gulch State Park' => [ :standard, :group, :rv ],
    'Saddleback Butte State Park' => [ :standard, :group, :rv ],
    'Salt Point State Park' => [ :standard, :group, :rv ],
    'Salton Sea State Recreation Area' => [ :standard, :group, :rv ],
    'Samuel P. Taylor State Park' => [ :standard, :group, :rv, :cabin ],
    'San Bruno Mountain State Park' => [ :group ],
    'San Clemente State Beach' => [ :standard, :group, :rv ],
    'San Elijo State Beach' => [ :standard, :rv ],
    'San Luis Reservoir State Recreation Area' => [ :standard, :group, :rv ],
    'San Onofre State Beach' => [ :standard, :group, :rv ],
    'Seacliff State Beach' => [ :rv ],
    'Silver Strand State Beach' => [ :standard, :rv ],
    'Silverwood Lake State Recreation Area' => [ :standard, :group, :rv ],
    'Sinkyone Wilderness State Park' => [ :standard, :cabin ],
    'Sonoma Coast State Park' => [ :standard, :rv ],
    'South Carlsbad State Beach' => [ :standard, :rv ],
    'Standish-Hickey State Recreation Area' => [ :standard, :rv ],
    'Sugarloaf Ridge State Park' => [ :standard, :group, :rv ],
    'Sunset State Beach' => [ :standard, :group, :rv ],
    'Tahoe State Recreation Area' => [ :standard, :rv ],
    'The Forest of Nisene Marks State Park' => [ :standard ],
    'Topanga State Park' => [ :group ],
    'Torrey Pines State Beach' => [ :rv ],
    'Turlock Lake State Recreation Area' => [ :standard, :rv ],
    'Van Damme State Park' => [ :standard, :group, :rv ],
    'Westport-Union Landing State Beach' => [ :standard, :rv ],
    'Will Rogers State Beach' => [ :rv ],
    'Woodson Bridge State Recreation Area' => [ :standard, :group, :rv ]
  }

  def test_campgrounds_list
    sp = Cf::Scrubber::Ca::StateParks.new

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
