Scrubbers and utilities.

California State Park System:

- ca_parks_activities
  Lists activities for CA state parks.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

- ca_parks_list
  List CA state parks
    -n, --no-details                 If present, do not emit the additional info and location info.
    -A, --all                        If present, all parks are listed; otherwise only those with campgrounds are listed.
    -t, --types=TYPES                Comma-separated list of types of campground to list. Lists all types if not given.
    -D, --data-format=DATAFORMAT     The output format to use: raw, json, or name.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

Colorado State Park System:

- co_parks_list
  List CO state parks
    -A, --all                        If present, all parks are listed; otherwise only those with campgrounds are listed.
    -t, --types=TYPES                Comma-separated list of types of campground to list. Lists all types if not given.
    -D, --data-format=DATAFORMAT     The output format to use: raw, json, or name.
    -o, --output-file=FILE           The file to use for the output. If not present, use STDOUT
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

Georgia State Park System:

- ga_parks_activities
  Lists activities for GA state parks
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

- ga_parks_list
  List GA state parks
    -A, --all                        If present, all parks are listed; otherwise only those with campgrounds are listed.
    -t, --types=TYPES                Comma-separated list of types of campground to list. Lists all types if not given.
    -D, --data-format=DATAFORMAT     The output format to use: raw, json, or name.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

Nevada State Park System:

- nv_parks_activities [options]
  Lists activities for NV state parks
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

- nv_parks_list [options]
  List NV state parks
    -A, --all                        If present, all parks are listed; otherwise only those with campgrounds are listed.
    -t, --types=TYPES                Comma-separated list of types of campground to list. Lists all types if not given.
    -D, --data-format=DATAFORMAT     The output format to use: raw, json, or name.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

Oregon State Parks System:

- or_parks_list [options]
  List OR state parks
    -A, --all                        If present, all parks are listed; otherwise only those with campgrounds are listed.
    -t, --types=TYPES                Comma-separated list of types of campground to list. Lists all types if not given.
    -D, --data-format=DATAFORMAT     The output format to use: raw, json, or name.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

National Forest Service (USDA):

- usda_nfs_campgrounds [options]
  List campgrounds for one or more states and forests
    -s, --states=STATES              Comma-separated list of states for which to list forests. Shows all states if not given. You may use two-character state codes.
    -r, --forests=FORESTS            Comma-separated list of forests for which to list campgrounds. Shows all forests (per state) if not given.
    -n, --no-details                 If present, do not load or emit the additional info and location info.
    -S, --state-format=STATEFORMAT   The output format to use for the state name: full or short (two-letter code).
    -A, --all                        If present, all parks are listed; otherwise only those with campgrounds are listed.
    -t, --types=TYPES                Comma-separated list of types of campground to list. Lists all types if not given.
    -D, --data-format=DATAFORMAT     The output format to use: raw, json, or name.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

- usda_nfs_states [options]
  Lists states with a national forest or grassland
    -F, --format=FORMAT              The output format to use: full or short (two-letter code).
    -i, --with-index                 If present, emit the state indeces as well as names
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help

- usda_nfs_forests [options]
  Lists national forests or grasslands for one or more states
    -i, --with-index                 If present, emit the state indeces as well as names
    -F, --format=FORMAT              The output format to use for the state name: full or short (two-letter code).
    -s, --states=STATES              Comma-separated list of states for which to list forests. Shows all states if not given. You may use two-character state codes.
    -l, --log-file=FILE              The file to use for the logger. If not present, use STDERR
    -v, --verbosity=LEVEL            Set the logger level; this is one of the level constants defined by the Logger class (WARN, INFO, etc...). Defaults to WARN.
    -?                               Show help
