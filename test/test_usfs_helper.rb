# Tests to add:

# - CA has all separate NFs
# - FL has three NFs from the facilities
# - NC has shared NFs
# - ND has duplicate facilities
# - ND has some group camping sites that are not under any NF heading (ND has shared NFs)
# - NY has one NF, but it's NOT in the RIDB. Same for VT (same NF)

# Should write a sanity checker that compares lists of NFs from the USFS web site to lists from the RIDB dump

require 'minitest/autorun'
require 'cf/scrubber'
require 'cf/scrubber/usda/usfs_helper'

class USFSHelperTest < Minitest::Test
  def dnames(dl)
    dl.map { |d| d[:name] }
  end

  def test_convert_forest_descriptors
    # simple conversions

    nf = [ 'Angeles National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal nf.sort, dnames(dl).sort

    nf = [ 'Angeles National Forest', 'Conecuh National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal nf.sort, dnames(dl).sort

    nf = [ 'Angeles National Forest', 'NoName National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 1, ul.count
    assert_equal [ 'NoName National Forest' ], ul[0]
    assert_equal [ 'Angeles National Forest' ].sort, dnames(dl).sort

    nf = [ 'Angeles National Forest', 'Tahoe National Forest', 'Angeles National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal [ 'Angeles National Forest', 'Tahoe National Forest' ].sort, dnames(dl).sort

    # remaps

    nf = [ 'Arapaho National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal [ 'Arapaho & Roosevelt National Forests Pawnee NG' ].sort, dnames(dl).sort

    nf = [ 'Arapaho National Forest', 'Roosevelt National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal [ 'Arapaho & Roosevelt National Forests Pawnee NG' ].sort, dnames(dl).sort

    nf = [ 'Arapaho National Forest', 'Roosevelt National Forest', 'Comanche National Grassland' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal [ 'Arapaho & Roosevelt National Forests Pawnee NG', 'PSICC' ].sort, dnames(dl).sort

    # multiple remaps

    nf = [ 'Nebraska National Forest' ]
    dl, ul = Cf::Scrubber::USDA::USFSHelper.convert_forest_descriptors(nf)
    assert_equal 0, ul.count
    assert_equal [ 'Nebraska National Forest at Halsey', 
                   'Nebraska National Forest at Chadron' ].sort, dnames(dl).sort
  end
end
