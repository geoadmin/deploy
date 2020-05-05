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
  mkdir -p "$(pwd)/tmp"
}

mock_tear_down() {
  reset_env
  if [ -f "${deploy_config_backup}" ]; then
    mv -f "${deploy_config_backup}" "${deploy_config}"
  fi
  rm -rf "$(pwd)/tmp"
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
  source "$(realpath "$1")"
}

# includes.sh unit tests
Describe 'includes.sh'
  Describe 'variables'
    Example 'default values'
      # each Example block will be run in a subshell
      When call source_code includes.sh
      The variable comment should equal 'manual db deploy'
      The variable message should be undefined
    End
    Example 'custom message'
      message="automatic deploy"
      When call source_code includes.sh
      The variable message should be defined
      The variable comment should equal 'automatic deploy'
    End
  End
  Describe 'basic functions'
    source_code includes.sh
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
    source_code includes.sh
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
  mock_set_up
  add_deploy_config
  Describe 'functions'
    source_code deploy.sh
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
    Describe 'check_table'
      source_db="source_db"
      source_schema="source_schema"
      source_table="source_table"
      source_id="${source_db}.${source_schema}.${source_table}"
      target_db="target_db"
      target_schema="target_schema"
      target_table="target_table"
      target_id="${target_db}.${target_schema}.${target_table}"
      test_check_table() {
        check_table
        eval "$1"
      }
      Example 'check_table_source_true'
        PSQL() {
          echo "${source_id}"
        }
        When run test_check_table check_table_source
        The stdout should not be present
        The stderr should not be present
        The status should be success
      End
      Example 'check_table_source_false'
        PSQL() {
          echo "table does not exist"
        }
        When run test_check_table check_table_source
        The stderr should start with "source table does not exist ${source_id}"
        The status should be failure
      End
      Example 'check_table_target_true'
        PSQL() {
          echo "${target_id}"
        }
        When run test_check_table check_table_target
        The stdout should not be present
        The stderr should not be present
        The status should be success
      End
      Example 'check_table_target_false'
        PSQL() {
          echo "table does not exist"
        }
        When run test_check_table check_table_target
        The stderr should be present
        The status should be failure
      End
      Example 'check_table_schema_true'
        PSQL() {
          :
        }
        When run test_check_table check_table_schema
        The stdout should not be present
        The stderr should not be present
        The status should be success
      End
      Example 'check_table_schema_false'
        PSQL() {
          source_columns=$(cat << EOF
bgdi_created|timestamp without time zone
bgdi_created_by|character varying
bgdi_id|integer
bgdi_modified|timestamp without time zone
bgdi_modified_by|character varying
cache_ttl|integer
fk_dataset_id|character varying
format|character varying
published|boolean
resolution_max|numeric
resolution_min|numeric
s3_resolution_max|numeric
timestamp|character varying
wms_gutter|integer
EOF
)
          target_columns=$(cat << EOF
cache_ttl|integer
fk_dataset_id|character varying
format|character varying
published|boolean
resolution_max|numeric
resolution_min|numeric
s3_resolution_max|numeric
timestamp|character varying
wms_gutter|integer
EOF
)
          # function output
          if [[ "$@" =~ "${source_db}" ]]; then
            echo "${source_columns}"
          fi
          if [[ "$@" =~ "${target_db}" ]]; then
            echo "${target_columns}"
          fi
        }
        When run test_check_table check_table_schema
        The stderr should start with "structure of source and target table is different."
        The status should be failure
      End
      Example 'check_table_dependencies_true'
        PSQL() {
          echo 0
        }
        When run test_check_table check_table_dependencies
        The stdout should not be present
        The stderr should not be present
        The status should be success
      End
      Example 'check_table_dependencies_false'
        PSQL() {
          echo 15
        }
        When run test_check_table check_table_dependencies
        The stderr should equal "cannot copy table source_db.source_schema.source_table, table is referenced by 15 objects, use db_copy instead."
        The status should be failure
      End
    End
    Describe 'check_database'
      source_db="source_db"
      Example 'check_database_true'
        PSQL() {
          echo "${source_db}"
        }
        When run check_database
        The stdout should not be present
        The stderr should not be present
        The status should be success
      End
      Example 'check_databasee_false'
        PSQL() {
          :
        }
        When run check_database
        The stderr should equal "No existing databases are named ${source_db}."
        The status should be failure
      End
    End
    Describe 'update_materialized_views'
      refreshmatviews=true
      target_db="bod_master"
      source_db="bod_master"
      matview_1="re3.view_bod_layer_info_de"
      matview_2="re3.view_bod_layer_info_fr"
      array_matviews=("${target_db}.${matview_1}" "${target_db}.${matview_2}")
      Example 'update_materialized_views_table_scan'
        PSQL() {
          echo "${matview_1}"
        }
        When run update_materialized_views table_scan
        The stdout should equal "table_scan: found materialized view ${target_db}.${matview_1} which is referencing . ..."
        The status should be success
      End
      Example 'update_materialized_views_table_commit'
        PSQL() {
          :
        }
        When call update_materialized_views table_commit
        The stderr should not be present
        The line 1 of stdout should eq "table_commit: updating materialized view ${matview_1} ..."
        The line 2 of stdout should eq "table_commit: updating materialized view ${matview_2} ..."
        The variable array_target_combined should include "${matview_1}"
        The status should be success
      End
      Example 'update_materialized_views_database'
        PSQL() {
          echo "${matview_1} ${matview_2}"
        }
        When call update_materialized_views database
        The stderr should not be present
        The line 1 of stdout should eq "database: updating materialized view ${source_db}.${matview_1} before starting deploy ..."
        The line 2 of stdout should eq "database: updating materialized view ${source_db}.${matview_2} before starting deploy ..."
        The status should be success
      End
    End
    Describe 'bod_create_archive'
      source_db="bod_master"
      PSQL() {
        exit 0
      }
      Example 'wrong timestamp'
        timestamp="wrong_pattern"
        When run bod_create_archive
        The stdout should not be present
        The stderr should eq "timestamp must match the pattern [a-zA-Z0-9]+"
        The status should be failure
      End
      Example 'no timestamp'
        When run bod_create_archive
        The output should equal 'Not archiving'
        The status should be success
      End
      Example 'create archive'
        timestamp="validtimestamp"
        When run bod_create_archive
        The output should equal "Archiving ${source_db} as ${source_db}${timestamp}..."
        The status should be success
      End
    End
    Describe 'copy_database'
      source_db="db_master"
      target_db="db_target"
      attached_slaves=2
      db_size="50GB"
      target_db_tmp="${target_db}_tmp"
      MY_DIR="${MY_DIR}/mock_data"
      mock_bodreview() {
      exec 5>&1
      exec 6>&2
        mkdir -p "${MY_DIR}"
        cat << EOF > "${MY_DIR}/bod_review.sh"
#!/bin/bash
EOF
      }
      mock_tear_down() {
        exec 5>&-
        exec 6>&-
        rm -rf "${MY_DIR}"
      }
      PSQL() {
        echo "${db_size}"
      }
      CREATEDB() {
        :
      }
      DROPDB() {
        :
      }
      Example 'standard db deploy'
        mock_bodreview
        When run copy_database
        The output should start with "copy ${source_db} to ${target_db} size: ${db_size} attached slaves: ${attached_slaves}"
        The output should end with "replacing ${target_db} with ${target_db_tmp} ..."
        The stderr should not be present
        The status should be success
        mock_tear_down
      End
      Example 'bod db deploy'
        source_db=bod_master
        mock_bodreview
        When run copy_database
        The output should start with "copy ${source_db} to ${target_db} size: ${db_size} attached slaves: ${attached_slaves}"
        The output should end with "bash bod_review.sh -d ${target_db} ..."
        The stderr should not be present
        The status should be success
        mock_tear_down
      End
    End
    Describe 'copy_table'
      source_code includes.sh
      source_db="stopo_master"
      source_schema="public"
      source_table="ch"
      source_id="${source_db}.${source_schema}.${source_table}"
      target_db="stopo_dev"
      target_schema="${source_schema}"
      target_table="${source_table}"
      target_id="${target_db}.${target_schema}.${target_table}"
      attached_slaves=2
      CPUS=4
      PSQL() {
        echo "${rows}"
      }
      CREATEDB() {
        :
      }
      DROPDB() {
        :
      }
      PG_DUMP() {
        :
      }
      update_materialized_views() {
        :
      }
      Example 'single thread table deploy'
        rows=200
        When run copy_table
        The line 1 of output should include "copy ${source_id} to ${target_id} rows: ${rows} threads: 1 rows/thread: ${rows} size: ${rows} attached slaves: ${attached_slaves}"
        The stderr should not be present
        The status should be success
      End
      Example 'multi thread table deploy'
        rows=1200
        When run copy_table
        The line 1 of output should include "copy ${source_id} to ${target_id} rows: ${rows} threads: ${CPUS} rows/thread: $((rows/CPUS)) size: ${rows} attached slaves: ${attached_slaves}"
        The stderr should not be present
        The status should be success
      End
    End
    Describe 'write_lock'
      source_code includes.sh
      array_source=("bod_master.public.table3")
      target="dev"
      mockdir="$(pwd)/mock_data"
      LOCK_DIR="${mockdir}"
      mock_write_lock() {
        rm -rf "${mockdir}" || :
        mkdir -p "${mockdir}"
      }
      mock_tear_down() {
        rm -rf "${mockdir}" || :
      }
      test_write_lock() {
        lock() {
            # simulate lock
            return 1
        }
        # run write_lock in the background
        ( write_lock ) & pid=$!
        # kill write_lock looper after 1 second
        ( sleep 1 && kill -9 $pid ) &
      }
      mock_write_lock
      Example 'target locked'
        When run test_write_lock
        The status should be success
        The stderr should not be present
        The line 1 of output should eq "target db bod_dev is locked, waiting for deploy process to finish (0/3600) ..."
      End
      Example 'target not locked'
        When run write_lock
        The stderr should not be present
        The stdout should not be present
        The status should be success
      End
      mock_tear_down
    End
    Describe 'check_toposhop'
      source_code includes.sh
      Example 'standard deploy valid target'
        target=dev
        When call check_toposhop stopo_master
        The status should be success
        The variable ToposhopMode should not be defined
      End
      Example 'standard deploy invalid target'
        target=invalid_target
        When run check_toposhop stopo_master
        The status should be failure
        The stderr should eq "valid standard deploy targets are: 'dev int prod demo tile'"
      End
      Example 'toposhop deploy valid target'
        target=dev
        When call check_toposhop toposhop_prod
        The status should be success
        The stderr should not be present
        The variable ToposhopMode should be defined
      End
      Example 'toposhop deploy invalid target'
        target=prod
        When run check_toposhop toposhop_prod
        The status should be failure
        The stderr should eq "valid toposhop deploy targets are: 'dev int'"
      End
    End
    Describe 'check_input'
      source_code includes.sh
      target=dev
      refreshsphinx=true
      refreshmatviews=true
      PSQL() {
        echo "true"
      }
      source_objects=("bod_master.public.tileset")
      Example 'archive mode'
        unset target
        timestamp="20200101"
        When call check_input
        The output should eq "BOD pure archive mode true"
        The status should be success
        The variable ArchiveMode should eq true
      End
      Example 'mandatory argunents missing target'
        unset target
        When run check_input
        The status should be failure
        The stderr should eq 'missing a required parameter (source_db -s and staging -t are required)'
      End
      Example 'mandatory argunents missing source_objects'
        unset source_objects
        When run check_input
        The status should be failure
        The stderr should eq 'missing a required parameter (source_db -s and staging -t are required)'
      End
      Example 'wrong value for refreshmatviews'
        refreshmatviews=blurb
        When run check_input
        The status should be failure
        The stderr should eq 'wrong parameter -r blurb , should be true or false'
      End
      Example 'wrong value for refreshsphinx'
        refreshsphinx=blurb
        When run check_input
        The status should be failure
        The stderr should eq 'wrong parameter -r blurb , should be true or false'
      End
      Example 'no db connection'
        PSQL() {
          :
        }
        When run check_input
        The status should be failure
        The stderr should eq 'Unable to connect to database cluster'
      End
      Example 'wrong formatted source_objects'
        array_source=("bod_master.tileset")
        When run check_input
        The status should be failure
        The stderr should eq 'table data sources have to be formatted like this: db.schema.table, database sources like this: db'
      End
    End
  End
  mock_tear_down
End
Describe 'ddl_trigger.sh'
  mock_set_up
  add_deploy_config
  source_code includes.sh
  source_code ddl_trigger.sh
  Describe 'check_access'
    source_db="stopo_master"
    array_source=("${source_db}")
    target="dev"
    PSQL() {
      echo "db connection to ${source_db} established"
    }
    Example 'checks passed'
      When run check_access
      The status should be success
      The output should not be present
    End
    Example 'missing mandatory parameter'
      unset target
      When run check_access
      The status should be failure
      The stderr should start with "missing a required parameter "
    End
    Example 'invalid deploy target'
      target="invalid_target"
      When run check_access
      The status should be failure
      The stderr should start with "valid deploy targets are: "
    End
    Example 'database connection'
      PSQL() {
        :
      }
      When run check_access
      The status should be failure
      The stderr should start with "Unable to connect to database"
    End
    Example 'demo target'
      target="demo"
      When run check_access
      The status should be success
      The stdout should eq "demo target will not be versionized in github"
    End
  End
  Describe 'process_db'
    source_db="stopo_master"
    array_source=("${source_db}")
    target="dev"
    PG_DUMP() {
      echo "this is the dump file of ${source_db}"
    }
    test_dump() {
      process_dbs
      cat "${dumpfile}"
    }
    Example 'create dump file'
      When call test_dump
      The status should be success
      The line 1 of stdout should start with "creating ddl dump"
      The line 2 of stdout should eq "this is the dump file of ${source_db}"
    End
    Example 'skip dump file'
      source_db="stopo_test_master"
      array_source=("${source_db}")
      When call process_dbs
      The status should be success
      The stdout should start with "skip ddl trigger for database "
    End
  End
  Describe 'update_git'
    Example 'git comment'
      source_db="stopo_master"
      git() {
        echo "$@"
      }
      test() {
        update_git
        cat deploy.log
      }
      When call test
      The status should be success
      The stdout should include "| DB: ${source_db} | "
    End
  End
  mock_tear_down
End
Describe 'dml_trigger.sh'
  mock_set_up
  add_deploy_config
  source_code ${deploy_config}
  source_code includes.sh
  source_code dml_trigger.sh
  Describe 'check_access'
    tables="bod_master.public.tileset"
    target="dev"
    Example 'checks passed'
      When run check_arguments
      The status should be success
      The output should not be present
    End
    Example 'missing required parameter'
      unset target
      When run check_arguments
      The stdout should be present
      The status should be failure
      The stderr should start with "missing a required parameter "
    End
    Example 'invalid deploy target'
      target="invalid_target"
      When run check_arguments
      The stderr should start with "valid deploy targets are:"
      The status should be failure
    End
    Example 'missing sphinx host'
      unset SPHINX_DEV
      When run check_arguments
      The stderr should eq "please define a sphinx host for ${target}"
      The status should be failure
    End
  End
  mock_tear_down
End
Describe 'bod_review.sh'
  mock_set_up
  add_deploy_config
  source_code ${deploy_config}
  source_code includes.sh
  source_code bod_review.sh
  Describe 'check access'
    bod_database="bod_master"
    PSQL() {
      echo "connection established"
    }
    Example 'checks passed'
      When run check_access
      The status should be success
      The output should not be present
    End
    Example 'missing parameter'
      unset bod_database
      When run check_access
      The status should be failure
      The stderr should start with "missing a required parameter "
    End
    Example 'no database connection'
      PSQL() {
        :
      }
      When run check_access
      The status should be failure
      The stderr should start with "something went wrong when trying to connect to ${bod_database}"
    End
  End
  Describe 'generate_json'
    git() {
      :
    }
    PSQL() {
      :
    }
    test_generate_json() {
      cd tmp
      generate_json
    }
    python() {
      :
    }
    Example 'check output'
      When run test_generate_json
      The status should be success
      The output should not be present
      The path tmp/bod_review/re3.topics.json should be empty file
      The path tmp/bod_review/re3.view_bod_layer_info_de.json should be empty file
      The path tmp/bod_review/re3.view_bod_wmts_getcapabilities_de.json should be empty file
      The path tmp/bod_review/re3.view_catalog.json should be empty file
    End
  End
  mock_tear_down
End
