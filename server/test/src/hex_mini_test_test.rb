require_relative 'test_base'

class HexMiniTestTest < TestBase

  def self.hex_prefix; '898'; end

  test 'C80',
  'hex_test_id is available via environment variable' do
    assert_equal '898C80', ENV['CYBER_DOJO_HEX_TEST_ID']
  end

end
