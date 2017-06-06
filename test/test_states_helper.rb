require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/states_helper'

class Container
  include Cf::Scrubber::StatesHelper
end

class StatestHelperTest < Minitest::Test
  def test_state_conversion
    assert_equal 'CA', Container.get_state_code('California')
    assert_equal 'CA', Container.get_state_code('california')
    assert_equal 'RI', Container.get_state_code('Rhode Island')
    assert_equal 'RI', Container.get_state_code('RHODE ISLAND')

    assert_equal 'CA', Container.get_state_code('CA')
    assert_equal 'CA', Container.get_state_code('ca')
    assert_equal 'CA', Container.get_state_code(:ca)
    assert_equal 'CA', Container.get_state_code(:CA)
    assert_equal 'RI', Container.get_state_code('RI')
    assert_equal 'RI', Container.get_state_code('ri')
    assert_equal 'RI', Container.get_state_code(:ri)
    assert_equal 'RI', Container.get_state_code(:RI)

    assert_nil Container.get_state_code('No state')

    assert_equal 'Alaska', Container.get_state_name('AK')
    assert_equal 'Alaska', Container.get_state_name('ak')
    assert_equal 'Alaska', Container.get_state_name(:AK)
    assert_equal 'Alaska', Container.get_state_name(:ak)

    assert_equal 'Rhode Island', Container.get_state_name('RI')
    assert_equal 'Rhode Island', Container.get_state_name('ri')
    assert_equal 'Rhode Island', Container.get_state_name(:RI)
    assert_equal 'Rhode Island', Container.get_state_name(:ri)

    assert_nil Container.get_state_name('XX')

    container = Container.new
    
    assert_equal 'CA', container.get_state_code('California')
    assert_equal 'CA', container.get_state_code('california')
    assert_equal 'RI', container.get_state_code('Rhode Island')
    assert_equal 'RI', container.get_state_code('RHODE ISLAND')

    assert_equal 'CA', container.get_state_code('CA')
    assert_equal 'CA', container.get_state_code('ca')
    assert_equal 'CA', container.get_state_code(:CA)
    assert_equal 'CA', container.get_state_code(:ca)
    assert_equal 'RI', container.get_state_code('RI')
    assert_equal 'RI', container.get_state_code('ri')
    assert_equal 'RI', container.get_state_code(:RI)
    assert_equal 'RI', container.get_state_code(:ri)

    assert_nil container.get_state_code('No state')

    assert_equal 'Alaska', container.get_state_name('AK')
    assert_equal 'Alaska', container.get_state_name('ak')
    assert_equal 'Alaska', container.get_state_name(:AK)
    assert_equal 'Alaska', container.get_state_name(:ak)

    assert_equal 'Rhode Island', container.get_state_name('RI')
    assert_equal 'Rhode Island', container.get_state_name('ri')
    assert_equal 'Rhode Island', container.get_state_name(:RI)
    assert_equal 'Rhode Island', container.get_state_name(:ri)

    assert_nil container.get_state_name('XX')
  end
end
