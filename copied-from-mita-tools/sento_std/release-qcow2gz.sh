#!/bin/bash
#
# requires:
#  bash
#

cd ${BASH_SOURCE[0]%/*}

[[ -f alternative.conf ]] && . alternative.conf

../../vmbuilder/kvm/rhel/6/misc/raw2qcow2.sh ${alternative}.raw

echo "[INFO] Compressing ${alternative}.qcow2"
gzip -c ${alternative}.qcow2 > ${alternative}.qcow2.gz

echo "[INFO] Generated => ${alternative}.qcow2.gz"
echo "[INFO] Complete!"
