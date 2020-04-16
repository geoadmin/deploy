#shellcheck shell=bash
# shell output is english
export LC_ALL=C

Describe 'data_includes.sh'
  mock_set_up() {
    source ./includes.sh
  }
  Describe 'variables'
    Example 'default values'
      # each Example block will be run in a subshell
      When call mock_set_up
      The variable comment should equal 'manual db deploy'
      The variable message should be undefined
    End
    Example 'custom message'
      message="automatic deploy"
      When call mock_set_up
      The variable message should be defined
      The variable comment should equal 'automatic deploy'
    End
  End
  Describe 'basic functions'
    mock_set_up
    Example 'Ceiling'
      # each Example block will be run in a subshell
      When run Ceiling  15 4
      The stdout should equal '4'
    End
    Example 'format_milliseconds'
      When run format_milliseconds "600060"
      The stdout should start with '0h:10m:0s.60 - 600060 milliseconds'
    End
  End
End
