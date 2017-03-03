require 'minitest/autorun'
require 'cf/scrubber'

class BaseTest < Minitest::Test
  def test_adjust_href
    base = 'http://www.s.com/a/b/c?p1=10&p2=20'
    base_uri = URI(base)

    href = 'http://www.t.com/f/g?p4=40&p5=50'
    assert_equal href, Cf::Scrubber::Base.adjust_href(href, base)
    assert_equal href, Cf::Scrubber::Base.adjust_href(href, base_uri)
    assert_equal 'http://www.t.com/f/g?p5=50', Cf::Scrubber::Base.adjust_href(href, base, [ 'p4' ])
    assert_equal 'http://www.t.com/f/g?p5=50', Cf::Scrubber::Base.adjust_href(href, base_uri, [ 'p4' ])

    href = '/f/g?p4=40&p5=50'
    assert_equal 'http://www.s.com/f/g?p4=40&p5=50', Cf::Scrubber::Base.adjust_href(href, base)
    assert_equal 'http://www.s.com/f/g?p4=40&p5=50', Cf::Scrubber::Base.adjust_href(href, base_uri)
    assert_equal 'http://www.s.com/f/g?p5=50', Cf::Scrubber::Base.adjust_href(href, base, [ 'p4' ])
    assert_equal 'http://www.s.com/f/g?p5=50', Cf::Scrubber::Base.adjust_href(href, base_uri, [ 'p4' ])

    href = '/f/g?p4=40&p5=50&p6=60#frag'
    assert_equal 'http://www.s.com/f/g?p4=40&p5=50&p6=60#frag', Cf::Scrubber::Base.adjust_href(href, base)
    assert_equal 'http://www.s.com/f/g?p4=40&p5=50&p6=60#frag', Cf::Scrubber::Base.adjust_href(href, base_uri)
    assert_equal 'http://www.s.com/f/g?p4=40&p6=60#frag', Cf::Scrubber::Base.adjust_href(href, base, [ 'p5' ])
    assert_equal 'http://www.s.com/f/g?p4=40&p6=60#frag', Cf::Scrubber::Base.adjust_href(href, base_uri, [ 'p5' ])
  end
end
