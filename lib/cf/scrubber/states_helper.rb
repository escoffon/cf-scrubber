module Cf::Scrubber
  # A mixin module that implements state (and territories) utilities.

  module StatesHelper
    # State codes and state names.

    STATE_CODES = {
      AL: 'Alabama',
      AK: 'Alaska',
      AZ: 'Arizona',
      AR: 'Arkansas',
      CA: 'California',
      CO: 'Colorado',
      CT: 'Connecticut',
      DE: 'Delaware',
      FL: 'Florida',
      GA: 'Georgia',
      HI: 'Hawaii',
      ID: 'Idaho',
      IL: 'Illinois',
      IN: 'Indiana',
      IA: 'Iowa',
      KS: 'Kansas',
      KY: 'Kentucky',
      LA: 'Louisiana',
      ME: 'Maine',
      MD: 'Maryland',
      MA: 'Massachusetts',
      MI: 'Michigan',
      MN: 'Minnesota',
      MS: 'Mississippi',
      MO: 'Missouri',
      MT: 'Montana',
      NE: 'Nebraska',
      NV: 'Nevada',
      NH: 'New Hampshire',
      NJ: 'New Jersey',
      NM: 'New Mexico',
      NY: 'New York',
      NC: 'North Carolina',
      ND: 'North Dakota',
      OH: 'Ohio',
      OK: 'Oklahoma',
      OR: 'Oregon',
      PA: 'Pennsylvania',
      RI: 'Rhode Island',
      SC: 'South Carolina',
      SD: 'South Dakota',
      TN: 'Tennessee',
      TX: 'Texas',
      UT: 'Utah',
      VT: 'Vermont',
      VA: 'Virginia',
      WA: 'Washington',
      WV: 'West Virginia',
      WI: 'Wisconsin',
      WY: 'Wyoming',

      AS: 'American Samoa',
      DC: 'District of Columbia',
      FM: 'Federated States of Micronesia',
      GU: 'Guam',
      MH: 'Marshall Islands',
      MP: 'Northern Mariana Islands',
      PW: 'Palau',
      PR: 'Puerto Rico',
      VI: 'Virgin Islands'

      # AE: 'Armed Forces Africa',
      # AA: 'Armed Forces Americas',
      # AE: 'Armed Forces Canada',
      # AE: 'Armed Forces Europe',
      # AE: 'Armed Forces Middle East',
      # AP: 'Armed Forces Pacific'
    }

    # The methods in this module will be installed as class methods of the including class.

    module ClassMethods
      # Get the state code from a state name.
      #
      # @param [String] name The state name (+Arkansas+, +California+, <tt>American Samoa</tt>, etc...).
      #  If a two-letter name is given, the method checks if it is a valid state code and returns it.
      #
      # @return [String, nil] Returns the two-letter code for the state or territory. If _name_ does not map
      #  to a valid code, returns +nil+.

      def get_state_code(name)
        n = name.to_s
        code = @name_to_state_map[n.downcase]
        return code unless code.nil?
        return n.upcase if (n.length == 2) && @state_to_name_map.has_key?(n.upcase)
        nil
      end

      # Get the state name from a state code.
      #
      # @param [String, Symbol] code A two-letter string or symbol containing the state code (+AR+, +CA+,
      #  +AS+, etc...).
      #
      # @return [String, nil] Returns the canonical name for the state or territory. If _name_ does not map
      #  to a valid code, returns +nil+.

      def get_state_name(code)
        @state_to_name_map[code.to_s.upcase]
      end
    end

    # The methods in this module are installed as instance method of the including class.

    module InstanceMethods
      # Get the state code from a state name.
      # Forwards the call to the class method.
      #
      # @param [String] name The state name (+Arkansas+, +California+, +American Samoa+, etc...).
      #
      # @return [String] Returns the two-letter code for the state or territory. If _name_ does not map
      #  to a valid code, returns +nil+.

      def get_state_code(name)
        self.class.get_state_code(name)
      end

      # Get the state name from a state code.
      # Forwards the call to the class method.
      #
      # @param [String, Symbol] code A two-letter string or symbol containing the state code (+AR+, +CA+,
      #  +AS+, etc...).
      #
      # @return [String] Returns the canonical name for the state or territory. If _name_ does not map
      #  to a valid code, returns +nil+.

      def get_state_name(code)
        self.class.get_state_name(code)
      end
    end

    # Perform actions when the module is included.
    # - Sets up the state maps.
    # - Injects the class and instance methods.

    def self.included(base)
      base.extend ClassMethods

      base.instance_eval do
      end

      base.send(:include, InstanceMethods)

      base.class_eval do
        @name_to_state_map = {}
        @state_to_name_map = {}

        STATE_CODES.each do |sk, sv|
          @name_to_state_map[sv.downcase] = sk.to_s
          @state_to_name_map[sk.to_s] = sv
        end
      end
    end
  end
end
