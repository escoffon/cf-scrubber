# -*-ruby-*-

Gem::Specification.new do |s|
  s.name        = 'cf-scrubber'
  s.version     = '0.3.14'
  s.date        = '2017-02-27'
  s.summary     = "Campfinder scrubbers"
  s.description = "A gem of scrubbers for various web sites that contain campground information."
  s.authors     = [ "Emil Scoffone" ]
  s.email       = 'emil@scoffone.com'
  s.files       = [ "lib/cf/scrubber.rb", 'lib/cf/scrubber/base.rb', 'lib/cf/scrubber/script.rb',
                    'lib/cf/scrubber/usda/national_forest_service.rb', 'lib/cf/scrubber/usda/script.rb',
                    'lib/cf/scrubber/usda/script/campgrounds.rb', 'lib/cf/scrubber/usda/script/forests.rb',
                    'lib/cf/scrubber/usda/script/states.rb',
                    'lib/cf/scrubber/ca/state_parks.rb', 'lib/cf/scrubber/ca/script.rb',
                    'lib/cf/scrubber/ca/script/activities.rb', 'lib/cf/scrubber/ca/script/park_list.rb',
                    'lib/cf/scrubber/nv/state_parks.rb', 'lib/cf/scrubber/nv/script.rb',
                    'lib/cf/scrubber/nv/script/activities.rb', 'lib/cf/scrubber/nv/script/park_list.rb',
                    'bin/usda_nfs_states', 'bin/usda_nfs_forests', 'usda_nfs_campgrounds',
                    'bin/ca_parks_activities', 'bin/ca/parks_list',
                    'bin/nv_parks_activities', 'bin/nv/parks_list',
                    'Rakefile',
                    'test/test_usda_nfs.rb',
                    '.yardopts'
                  ]
  s.homepage    = 'http://rubygems.org/gems/cf-scrubber'
  s.license     = 'MIT'
  s.add_runtime_dependency 'nokogiri', '~> 1.6'
  s.add_runtime_dependency 'json', '~> 1.8'
end
