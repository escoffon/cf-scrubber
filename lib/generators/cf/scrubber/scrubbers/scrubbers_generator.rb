module Cf::Scrubber
  class ScrubbersGenerator < Rails::Generators::Base
    README = 'README.txt'
    SCRUBBERS = [ 'ca_parks_activities', 'ca_parks_list',
                  'co_parks_list',
                  'ga_parks_activities', 'ga_parks_list',
                  'nc_parks_list',
                  'nps_campgrounds', 'nps_rec_areas',
                  'nv_parks_activities', 'nv_parks_list',
                  'or_parks_list',
                  'ridb_activities', 'ridb_organizations',
                  'usda_nfs_campgrounds', 'usda_nfs_forests', 'usda_nfs_states',
                  'ut_parks_list' ]

    desc <<-DESC
  This generator installs scrubber utilities into the scrubbers folder.

  For example:
    rails generate cf:scrubber:scrubbers -S=ca_*

  The generator will create:
    scrubbers/ca_park_activities
    scrubbers/ca_parks_list
DESC

    source_root File.expand_path('../../../../../../bin', __FILE__)

    class_option :scrubbers, aliases: "-S", type: :array,
    	desc: "Select specific scrubbers to generate (#{SCRUBBERS.join(', ')})\nUse globbing to specifiy groups of scrubbers."

    def create_scrubbers
      cwd = Dir.getwd
      Dir.chdir(self.class.source_root)
      scrubbers = options[:scrubbers] || SCRUBBERS
      scrubbers.each do |name|
        Dir.glob(name) do |fn|
          target = "scrubbers/#{fn}"
          outfile = File.join(destination_root, target)
          template("#{fn}", outfile)
          chmod(outfile, 0755, { verbose: true })
        end
      end

      outfile = File.join(destination_root, 'scrubbers', README)
      template(README, outfile)
    end
  end
end
