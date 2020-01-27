#!/bin/bash
set -euo pipefail

retry=0
maxRetries=20
retryInterval=5
until [ ${retry} -ge ${maxRetries} ]
do
	packpack/packpack && break
	retry=$[${retry}+1]
	echo "Retrying [${retry}/${maxRetries}] in ${retryInterval}(s) "
	sleep ${retryInterval}
done

if [ ${retry} -ge ${maxRetries} ]; then
  echo "Failed after ${maxRetries} attempts!"
  exit 1
fi
