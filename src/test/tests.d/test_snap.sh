
#!/bin/bash

export ciop_job_include="/usr/lib/ciop/libexec/ciop-functions.sh"
source ./test_common.sh

node="snap"

test_bash_n_run()
{

  bash -n ../main/app-resources/${node}/run
  res=$?
  assertEquals "bash -n run validation failed" \
  "0" "${res}"
}

test_bash_n_lib()
{

  bash -n ../main/app-resources/${node}/lib/functions.sh
  res=$?
  assertEquals "bash -n functions validation failed" \
  "0" "${res}"
}

test_application_xml()
{

  xmllint --format ../main/app-resources/application.xml &> /dev/null
  res=$?
  assertEquals "application.xml XML validation failed" \
  "0" "${res}"
}

. ${SHUNIT2_HOME}/shunit2
