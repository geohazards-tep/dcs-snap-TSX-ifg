#!/bin/bash

# define the exit codes
SUCCESS=0
ERR_NO_URL=5
ERR_NO_MASTER=8
ERR_NO_SLAVE=9
ERR_SNAP=15
ERR_COMPRESS=20
ERR_GDAL=25
ERR_PUBLISH=40

node="snap"

# add a trap to exit gracefully
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_NO_URL}) msg="The TerraSAR-X product online resource could not be resolved";;
    ${ERR_NO_MASTER}) msg="The TerraSAR-X master product could not be retrieved";;
    ${ERR_NO_SLAVE}) msg="The TerraSAR-X slave product could not be retrieved";;
    ${ERR_SNAP}) msg="SNAP GPT failed";;
    ${ERR_GDAL}) msg="GDAL failed to convert result to tif";;
    ${ERR_COMPRESS}) msg="Failed to compress results";;
    ${ERR_PUBLISH}) msg="Failed to publish the results";;
    *) msg="Unknown error";;
 esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

trap cleanExit EXIT

function set_env() {

  SNAP_REQUEST=${_CIOP_APPLICATION_PATH}/${node}/etc/snap_request.xml

  params=$( xmlstarlet sel -T -t -m "//parameters/*" -v . -n ${SNAP_REQUEST} | grep '${' | grep -v '${in1}' | grep -v '${in2}' | grep -v '${out}' | sed 's/\${//' | sed 's/}//' )

  touch ${TMPDIR}/snap.params

  for param in ${params} 
  do 
    value="$( ciop-getparam $param)"
    [[ ! -z "${value}" ]] && echo "$param=${value}" >> ${TMPDIR}/snap.params
  done
  
  ciop-publish -m ${TMPDIR}/snap.params

  export SNAP_HOME=/opt/snap
  export PATH=${SNAP_HOME}/bin:${PATH}
  export SNAP_VERSION=$( cat ${SNAP_HOME}/VERSION.txt )

  return 0
  
}

function main() {

  set_env || exit $?
  
  slave=$( cat /dev/stdin ) 
  master=$( ciop-getparam master )

  cd ${TMPDIR}

  num_steps=8

  ciop-log "INFO" "(1 of ${num_steps}) Resolve TerraSAR-X master online resource"
  online_resource="$( opensearch-client ${master} enclosure )"
  [[ -z ${online_resource} ]] && return ${ERR_NO_URL}

  ciop-log "INFO" "(2 of ${num_steps}) Retrieve TerraSAR-X master product from ${online_resource}"
  local_master="$( ciop-copy -U -o ${TMPDIR} ${online_resource} )"
  [[ -z ${local_master} ]] && return ${ERR_NO_MASTER} 

  identifier="$( opensearch-client ${master} identifier )"
  local_master_xml=$( tar xvfz ${local_master} | grep "${identifier}.xml" )
  rm -f ${local_master}

  ciop-log "INFO" "(3 of ${num_steps}) Resolve TerraSAR-X slave online resource"
 
  online_resource="$( opensearch-client ${slave} enclosure )"
  [[ -z ${online_resource} ]] && return ${ERR_NO_URL}

  ciop-log "INFO" "(4 of ${num_steps}) Retrieve TerraSAR-X slave product from ${online_resource}"
  local_slave="$( ciop-copy -U -o ${TMPDIR} ${online_resource} )"
  [[ -z ${local_slave} ]] && return ${ERR_NO_SLAVE}

  identifier="$( opensearch-client ${slave} identifier )"
  local_slave_xml=$( tar xvfz ${local_slave} | grep "${identifier}.xml" )
  rm -f ${local_slave} 

  out=${TMPDIR}/TSX_IFG

  ciop-log "INFO" "(5 of ${num_steps}) Invoke SNAP GPT"

  gpt ${SNAP_REQUEST} \
    -Pin1=${local_master_xml} \
    -Pin2=${local_slave_xml} \
    -Pout=${out} \
    -p ${TMPDIR}/snap.params 1>&2 || return ${ERR_SNAP} 

  rm -fr $( dirname ${local_master_xml} )
  rm -fr $( dirname ${local_slave_xml} ) 

  ciop-log "INFO" "(6 of ${num_steps}) Compress results"  
  tar -C ${TMPDIR} -czf ${out}.tgz $( basename ${out}).dim $( basename ${out}).data || return ${ERR_COMPRESS}
  ciop-publish -m ${out}.tgz || return ${ERR_PUBLISH}  
 
  rm -fr ${out}.tgz
 
  ciop-log "INFO" "(7 of ${num_steps}) Convert to geotiff and PNG image formats"
  
  # Convert to GeoTIFF
  for img in $( find ${out}.data -name '*.img' )
  do 
    target=${out}_$( basename ${img} | sed 's/.img//' )
    
    gdal_translate ${img} ${target}.tif || return ${ERR_GDAL}
    ciop-publish -m ${target}.tif || return ${ERR_PUBLISH}
  
    gdal_translate -of PNG -a_nodata 0 -scale 0 1 0 255 ${target}.tif ${target}.png || return ${ERR_GDAL_QL}
    ciop-publish -m ${target}.png || return ${ERR_PUBLISH}
  
    listgeo -tfw ${target}.tif 
    [[ -e ${target}.tfw ]] && {
      mv ${target}.tfw ${target}.pngw
      ciop-publish -m ${target}.pngw || return ${ERR_PUBLISH}
      rm -f ${target}.pngw  
    }

    rm -fr ${target}.tif ${target}.png 
 
  done
  
  ciop-log "INFO" "(8 of ${num_steps}) Clean up" 
  # clean-up
  rm -fr ${out}*
  
}
