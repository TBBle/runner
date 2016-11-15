require_relative './runner_test_base'
require_relative './mock_sheller'

class DockerRunnerKataMockShellerTest < RunnerTestBase

  def self.hex_prefix; 'BB7'; end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def shell; @shell ||= MockSheller.new(nil); end

  test '36C',
  'when image_name is valid and has not been pulled',
  'then new_kata(image_name, kata_id) pulls it' do
    image_name = 'cdf/ruby_mini_test'
    stdout = [
      'REPOSITORY     TAG    IMAGE ID     CREATED    SIZE',
      'cdf/gcc_assert latest 28683e525ad3 9 days ago 95.97 MB'
    ].join("\n")
    shell.mock_exec('docker images', stdout, '', 0)
    shell.mock_exec("docker pull #{image_name}", '','',0)
    runner.new_kata(image_name, kata_id)
    shell.teardown
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'DFA',
  'when image_name is valid has been pulled',
  'then new_kata(image_name, kata_id) does not pull it' do
    image_name = 'cdf/gcc_assert'
    stdout = [
      'REPOSITORY     TAG    IMAGE ID     CREATED    SIZE',
      "#{image_name}  latest 28683e525ad3 9 days ago 95.97 MB"
    ].join("\n")
    shell.mock_exec('docker images', stdout, '', 0)
    runner.new_kata(image_name, kata_id)
    shell.teardown
  end

end