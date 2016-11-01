require_relative './nearest_external'
require 'timeout'

class DockerRunner

  def initialize(parent)
    @parent = parent
  end

  attr_reader :parent

  def pulled_image?(image_name)
    ['', '', image_names.include?(image_name)]
  end

  def pull_image(image_name)
    assert_exec("docker pull #{image_name}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def new_avatar(kata_id, avatar_name)
    assert_exec("docker volume create --name #{volume_name(kata_id, avatar_name)}")
  end

  def old_avatar(kata_id, avatar_name)
    assert_exec("docker volume rm #{volume_name(kata_id, avatar_name)}")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run(image_name, kata_id, avatar_name, max_seconds, deleted_filenames, changed_files)
    cid = create_container(image_name, kata_id, avatar_name)
    begin
      delete_files(cid, deleted_filenames)
      change_files(cid, changed_files)
      run_cyber_dojo_sh(cid, max_seconds)
    ensure
      remove_container(cid)
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def create_container(image_name, kata_id, avatar_name)
    args = [
      '--detach',                          # get the cid
      '--interactive',                     # later execs
      '--net=none',                        # security - no network
      '--pids-limit=64',                   # security - no fork bombs
      '--security-opt=no-new-privileges',  # security - no escalation
      "--workdir=#{sandbox}",
      '--user=root',
      "--volume=#{volume_name(kata_id, avatar_name)}:#{sandbox}"
    ].join(space = ' ')
    stdout,_,_ = assert_exec("docker run #{args} #{image_name} sh")
    cid = stdout.strip
    assert_docker_exec(cid, "chown #{user}:#{group} #{sandbox}")
    # Some languages need the current user to have a home. They are all
    # Ubuntu image based, eg C#-NUnit. The nobody user does not have a
    # home dir in Ubuntu. usermod solves this.
    assert_docker_exec(cid, "cat /etc/issue | grep Alpine || usermod --home #{sandbox} #{user}")
    cid
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def delete_files(cid, filenames)
    filenames.each do |filename|
      assert_docker_exec(cid, "rm #{sandbox}/#{filename}")
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def change_files(cid, files)
    Dir.mktmpdir('runner') do |tmp_dir|
      files.each do |filename, content|
        host_filename = tmp_dir + '/' + filename
        disk.write(host_filename, content)
        assert_exec("chmod +x #{host_filename}") if filename.end_with?('.sh')
      end
      assert_exec("docker cp #{tmp_dir}/. #{cid}:#{sandbox}")
    end
    files.keys.each do |filename|
      assert_docker_exec(cid, "chown #{user}:#{group} #{sandbox}/#{filename}")
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def run_cyber_dojo_sh(cid, max_seconds)
    cmd = "docker exec --user=#{user} --interactive #{cid} sh -c './cyber-dojo.sh'"
    r_stdout, w_stdout = IO.pipe
    r_stderr, w_stderr = IO.pipe
    pid = Process.spawn(cmd, pgroup:true, out:w_stdout, err:w_stderr)
    begin
      Timeout::timeout(max_seconds) do
        Process.waitpid(pid)
        w_stdout.close
        w_stderr.close
        [r_stdout.read, r_stderr.read, completed]
      end
    rescue Timeout::Error
      Process.kill(-9, pid)
      Process.detach(pid)
      ['', '', timed_out]
    ensure
      w_stdout.close unless w_stdout.closed?
      w_stderr.close unless w_stderr.closed?
      r_stdout.close
      r_stderr.close
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def remove_container(cid)
    assert_exec("docker rm --force #{cid}")
    # The docker daemon responds to [docker rm] asynchronously.
    # This means an 'immeadiate' old_avatar()'s [docker volume rm]
    # might fail since the container is not quite dead yet.
    # This is unlikely to happen in real use but very likely in tests.
    # Doing the wait in the tests only would mean exposing the cid.
    # I choose instead to wait at most 2 seconds for verification
    # that the container really is dead.
    tries = 0
    removed = false
    while tries < 200 && !removed
      removed = container_dead?(cid)
      sleep(1.0 / 100.0) unless removed
      tries += 1
    end
    log << "Failed:remove_container(#{cid})" unless removed
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def user; 'nobody'; end
  def group; 'nogroup'; end
  def sandbox; '/sandbox'; end

  def completed;   0; end
  def timed_out; 128; end

  private

  def image_names
    stdout,_,_ = assert_exec('docker images')
    lines = stdout.split("\n")
    lines.shift # REPOSITORY TAG IMAGE ID CREATED SIZE
    lines.collect { |line| line.split[0] }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def container_dead?(cid)
    cmd = "docker inspect --format='{{ .State.Running }}' #{cid}"
    _,stderr,status = exec(cmd, logging = false)
    expected_stderr = "Error: No such image, container or task: #{cid}"
    (status == 1) && (stderr.strip == expected_stderr)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_docker_exec(cid, cmd)
    assert_exec("docker exec #{cid} sh -c '#{cmd}'")
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def assert_exec(cmd)
    stdout,stderr,status = exec(cmd)
    fail "exited(#{status}):#{stdout}:#{stderr}" unless status == success
    [stdout, stderr, status]
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def volume_name(kata_id, avatar_name)
    "cyber_dojo_#{kata_id}_#{avatar_name}"
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  include NearestExternal
  def shell; nearest_external(:shell); end
  def  disk; nearest_external(:disk);  end
  def   log; nearest_external(:log);   end

  def exec(cmd, logging = true); shell.exec(cmd, logging); end
  def success; shell.success; end

end
