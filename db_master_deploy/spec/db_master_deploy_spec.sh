#shellcheck shell=bash
# shell output is english
export LC_ALL=C

# global functions and variables
deploy_config="$(pwd)/deploy.cfg"
deploy_config_backup="$(pwd)/deploy.cfg.orig"

mock_set_up() {
  mock_tear_down || :
  if [ -f "${deploy_config}" ]; then
    mv -f "${deploy_config}" "${deploy_config_backup}"
  fi
  touch "${deploy_config}"
}

mock_tear_down() {
  reset_env
  if [ -f "${deploy_config_backup}" ]; then
    mv -f "${deploy_config_backup}" "${deploy_config}"
  fi
}

# overwrite whoami
whoami() {
  echo -n "geodata"
}

default_env() {
  PGUSER="www-data"
  SPHINX_DEV="ip-dev"
  SPHINX_INT="ip-int"
  SPHINX_PROD="ip-prod-1 ip-prod-2"
  SPHINX_DEMO="ip-demo"
  PUBLISHED_SLAVES="ip-1|ip-2|ip-3|ip-4"
}

add_deploy_config() {
  cat << EOF > ${deploy_config}
export SPHINX_DEV="10.220.4.141"
export SPHINX_DEMO="10.220.4.145" #DEMO == DEV since at the moment not demo instance is active
export SPHINX_INT="10.220.5.245"
export SPHINX_PROD="10.220.5.253 10.220.6.26"
export PGUSER=pgkogis
#                        <-------pg.bgdi.ch------> <--pg-sandbox.bgdi.ch-->
export PUBLISHED_SLAVES="10.220.5.122|10.220.6.137|10.220.5.87|10.220.6.129"
EOF
}

reset_env() {
  unset PGUSER
  unset SPHINX_DEV
  unset SPHINX_INT
  unset SPHINX_PROD
  unset SPHINX_DEMO
  unset PUBLISHED_SLAVES
}

source_code() {
  source ./includes.sh
}

# includes.sh unit tests
Describe 'includes.sh'
  Describe 'variables'
    Example 'default values'
      # each Example block will be run in a subshell
      When call source_code
      The variable comment should equal 'manual db deploy'
      The variable message should be undefined
    End
    Example 'custom message'
      message="automatic deploy"
      When call source_code
      The variable message should be defined
      The variable comment should equal 'automatic deploy'
    End
  End
  Describe 'basic functions'
    source_code
    Example 'Ceiling'
      When run Ceiling  15 4
      The stdout should equal '4'
    End
    Example 'format_milliseconds'
      When run format_milliseconds "600060"
      The stdout should start with '0h:10m:0s.60 - 600060 milliseconds'
    End
  End
  Describe 'check_env'
    source_code
    mock_set_up
    Example 'no deploy.cfg and no env'
      # have to run in subshell because function exit
      When run check_env
      The stderr should include 'you can set the variables in'
      The status should be failure
    End
    Example 'valid env from deploy.cfg'
      mock_set_up
      add_deploy_config
      When run check_env
      The status should be success
      The stdout should not be present
      The stderr should not be present
      mock_tear_down
    End
    Example 'valid env from env variables'
      mock_set_up
      default_env
      When run check_env
      The status should be success
      The stdout should not be present
      The stderr should not be present
      mock_tear_down
    End
    Example 'missed PGUSER'
      mock_set_up
      default_env
      unset PGUSER
      When run check_env
      The status should be failure
      The stderr should include 'export PGUSER=xxx'
      mock_tear_down
    End
    Example 'missed SPHINX_DEV'
      mock_set_up
      default_env
      unset SPHINX_DEV
      When run check_env
      The status should be failure
      The stderr should include 'export SPHINX_DEV='
      mock_tear_down
    End
    Example 'missed SPHINX_INT'
      mock_set_up
      default_env
      unset SPHINX_INT
      When run check_env
      The status should be failure
      The stderr should include 'export SPHINX_INT='
      mock_tear_down
    End
    Example 'missed SPHINX_PROD'
      mock_set_up
      default_env
      unset SPHINX_PROD
      When run check_env
      The status should be failure
      The stderr should include 'export SPHINX_PROD='
      mock_tear_down
    End
    Example 'missed SPHINX_DEMO'
      mock_set_up
      default_env
      unset SPHINX_DEMO
      When run check_env
      The status should be failure
      The stderr should include 'export SPHINX_DEMO='
      mock_tear_down
    End
    Example 'missed PUBLISHED_SLAVES'
      mock_set_up
      default_env
      unset PUBLISHED_SLAVES
      When call check_env
      The status should be success
      The variable PUBLISHED_SLAVES should eq '.*'
      mock_tear_down
    End
    Example 'wrong user'
      mock_set_up
      default_env
      whoami() { echo 'wrong_user'; }
      When run check_env
      The status should be failure
      The stderr should eq 'This script must be run as geodata!'
      mock_tear_down
    End
    # remove mock folders and env
    mock_tear_down
  End
End


# deploy.sh unit tests
Describe 'deploy.sh'
  source_code() {
    source ./deploy.sh
  }
  mock_set_up
  add_deploy_config
  Describe 'functions'
    source_code
    Describe 'check_source'
      target_db="testdb_dev"
      source_db="testdb_dev"
      Example 'same source and target'
        When run check_source
        The stderr should start with 'You may not copy a db or table over itself'
        The status should be failure
      End
      Example 'source is not _master - n'
        target_db="testdb_prod"
        answer="n"
        When run check_source
        The stdout should start with 'Master is not the selected source'
        The status should be failure
      End
      Example 'source is not _master - y'
        target_db="testdb_prod"
        answer="y"
        When run check_source
        The stdout should start with 'Master is not the selected source'
        The status should be success
      End
    End
  End
  mock_tear_down
End
