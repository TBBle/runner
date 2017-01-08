require_relative '../../src/all_avatars_names'

module OsHelper

  module_function

  include AllAvatarsNames

  def kata_id_env_vars_test
    printenv_cmd = 'printenv CYBER_DOJO_KATA_ID'
    env_kata_id = assert_cyber_dojo_sh_no_stderr printenv_cmd
    assert_equal kata_id, env_kata_id.strip

    printenv_cmd = 'printenv CYBER_DOJO_AVATAR_NAME'
    env_avatar_name = assert_cyber_dojo_sh_no_stderr printenv_cmd
    assert_equal avatar_name, env_avatar_name.strip

    printenv_cmd = 'printenv CYBER_DOJO_SANDBOX'
    env_sandbox = assert_cyber_dojo_sh_no_stderr printenv_cmd
    assert_equal sandbox, env_sandbox.strip
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def refute_avatar_users_exist
    etc_passwd = assert_docker_exec 'cat /etc/passwd'
    all_avatars_names.each do |name|
      uid = runner.user_id(name).to_s
      refute etc_passwd.include?(uid), "#{name}:#{uid}"
    end
  end

  def assert_group_exists
    stdout = assert_docker_exec "getent group #{group}"
    assert stdout.start_with?(group), stdout
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def new_avatar_sandbox_setup_test
    # sandbox exists
    assert_docker_exec "[ -d #{sandbox} ]"

    # sandbox is not empty
    ls = assert_docker_exec "ls -A #{sandbox}"
    refute_equal '', ls

    # sandbox's is owned by avatar
    stat_user = assert_docker_exec "stat -c '%u' #{sandbox}"
    assert_equal user_id, stat_user.strip

    # sandbox's group is set
    stat_group = assert_docker_exec "stat -c '%G' #{sandbox}"
    assert_equal group, stat_group.strip

    # sandbox's permissions are set
    stat_perms = assert_docker_exec("stat -c '%A' #{sandbox}").strip

    alpine_perm = 'drwxr-sr-x'
    ubuntu_perm = 'drwxr-xr-x'
    assert [alpine_perm, ubuntu_perm].include?(stat_perms), stat_perms

  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def new_avatar_starting_files_test
    # kata_setup has already called new_avatar() which
    # has setup a salmon. So I create a new avatar with
    # known ls-starting-files. Note that kata_teardown
    # calls old_avatar and old_kata
    new_avatar({ avatar_name:'lion', starting_files:ls_starting_files })
    begin
      sss_run({ avatar_name:'lion', changed_files:{} })
      assert_equal success, status
      assert_equal '', stderr
      ls_stdout = stdout
      ls_files = ls_parse(ls_stdout)
      assert_equal ls_starting_files.keys.sort, ls_files.keys.sort
      lion_uid = user_id('lion')
      assert_equal_atts('empty.txt',     '-rw-r--r--', lion_uid, group,  0, ls_files)
      assert_equal_atts('cyber-dojo.sh', '-rw-r--r--', lion_uid, group, 29, ls_files)
      assert_equal_atts('hello.txt',     '-rw-r--r--', lion_uid, group, 11, ls_files)
      assert_equal_atts('hello.sh',      '-rw-r--r--', lion_uid, group, 16, ls_files)
    ensure
      old_avatar({ avatar_name:'lion' })
    end
  end

  def assert_equal_atts(filename, permissions, user, group, size, ls_files)
    atts = ls_files[filename]
    refute_nil atts, filename
    assert_equal user,  atts[:user ], { filename => atts }
    assert_equal group, atts[:group], { filename => atts }
    assert_equal size,  atts[:size ], { filename => atts }
    assert_equal permissions, atts[:permissions], { filename => atts }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def unchanged_files_test
    named_args = { changed_files:ls_starting_files }
    before_ls = assert_run_succeeds_no_stderr(named_args)
    named_args = { changed_files:{} }
    after_ls = assert_run_succeeds_no_stderr(named_args)
    assert_equal before_ls, after_ls
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def deleted_files_test
    named_args = { changed_files:ls_starting_files }
    ls_stdout = assert_run_succeeds_no_stderr(named_args)
    before = ls_parse(ls_stdout)
    before_filenames = before.keys

    deleted_filenames = ['hello.txt']
    named_args = {
      changed_files:{},
      deleted_filenames:deleted_filenames
    }
    ls_stdout = assert_run_succeeds_no_stderr(named_args)
    after = ls_parse(ls_stdout)
    after_filenames = after.keys

    actual_deleted_filenames = before_filenames - after_filenames
    assert_equal deleted_filenames, actual_deleted_filenames
    after.each { |filename, attr| assert_equal before[filename], attr }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def new_files_test
    named_args = { changed_files:ls_starting_files }
    ls_stdout = assert_run_succeeds_no_stderr(named_args)
    before = ls_parse(ls_stdout)
    before_filenames = before.keys

    new_filename = 'fizz_buzz.h'
    new_file_content = '#ifndef...'
    named_args = { changed_files:{ new_filename => new_file_content } }
    ls_stdout = assert_run_succeeds_no_stderr(named_args)
    after = ls_parse(ls_stdout)
    after_filenames = after.keys

    actual_new_filenames = after_filenames - before_filenames
    assert_equal [ new_filename ], actual_new_filenames
    attr = after[new_filename]
    assert_equal '-rw-r--r--', attr[:permissions]
    assert_equal user_id,      attr[:user]
    assert_equal group,        attr[:group]
    assert_equal new_file_content.size, attr[:size]
    before.each { |filename, attr| assert_equal after[filename], attr }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def changed_file_test
    named_args = { changed_files:ls_starting_files }
    ls_stdout = assert_run_succeeds_no_stderr(named_args)
    before = ls_parse(ls_stdout)

    sleep 2

    hello_txt = ls_starting_files['hello.txt']
    extra = "\ngreetings"
    named_args = { changed_files:{ 'hello.txt' => hello_txt + extra } }
    ls_stdout = assert_run_succeeds_no_stderr(named_args)
    after = ls_parse(ls_stdout)

    assert_equal before.keys, after.keys
    before.each do |filename, was_attr|
      now_attr = after[filename]
      same = lambda { |sym| assert_equal was_attr[sym], now_attr[sym] }
      same.call(:permissions)
      same.call(:user)
      same.call(:group)
      if filename == 'hello.txt'
        refute_equal now_attr[:time_stamp], was_attr[:time_stamp]
        assert_equal now_attr[:size], was_attr[:size] + extra.size
      else
        same.call(:time_stamp)
        same.call(:size)
      end
    end
  end

  private

  def ls_starting_files
    {
      'cyber-dojo.sh' => ls_cmd,
      'empty.txt'     => '',
      'hello.txt'     => 'hello world',
      'hello.sh'      => 'echo hello world',
    }
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def ls_cmd;
    # Works on Ubuntu and Alpine
    'stat -c "%n %A %u %G %s %z" *'
    # hiker.h  -rw-r--r--  40045  nogroup 136  2016-06-05 07:03:14.000000000
    # |        |           |      |       |    |          |
    # filename permissions user   group   size date       time
    # 0        1           2      3       4    5          6
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  def ls_parse(ls_stdout)
    Hash[ls_stdout.split("\n").collect { |line|
      attr = line.split
      [filename = attr[0], {
        permissions: attr[1],
               user: attr[2],
              group: attr[3],
               size: attr[4].to_i,
         time_stamp: attr[6],
      }]
    }]
  end

end
