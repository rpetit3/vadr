#!/bin/bash

RETVAL=0;

$VADRSCRIPTSDIR/v-test.pl -f --rmout $VADRSCRIPTSDIR/testfiles/noro.r3.sub.testin vt-noro.r3.sub
if [ "$?" -eq 0 ]; then
   echo "Success: all tests passed [do-sub-tests.sh]"
   exit 0
else 
   echo "FAIL: at least one test failed [do-sub-tests.sh]"
   exit 1
fi
