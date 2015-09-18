#!/bin/bash

#Dont automatcially exit if error inside script
set +e 

check_return () {
    if [[ $1 -ne 0 ]]; then
        exit $1
    fi
}

readme () {
	# Check for Valid README.md
	[ -f ./README.md ] || exit 1
	if [[ $(cat /etc/passwd | wc -l) -lt 4 ]] ; then
		exit 1
	fi
}

check_var(){
    if [ -z $1 ]; then return 1; else return 0; fi
}
