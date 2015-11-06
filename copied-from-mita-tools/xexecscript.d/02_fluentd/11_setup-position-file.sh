#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

chroot $1 $SHELL -ex <<'EOS'
  posfiles="
    httpd_access_log.pos
    httpd_error_log.pos
    mysql_log.pos
    messages.pos
    custom1.pos
    custom2.pos
    custom3.pos
    custom4.pos
    custom5.pos
    custom6.pos
    custom7.pos
    custom8.pos
    custom9.pos
    custom10.pos
  "

  [[ -d /var/log/td-agent/position_files ]] || mkdir -p /var/log/td-agent/position_files
  chown td-agent:td-agent /var/log/td-agent/position_files

  for posfile in ${posfiles}; do
    posfile_path=/var/log/td-agent/position_files/${posfile}
    [[ -f "${posfile_path}" ]] || { : >  ${posfile_path} ; }
    chown td-agent:td-agent ${posfile_path}
    ls -l ${posfile_path}
  done
EOS
