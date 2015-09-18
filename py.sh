#!/bin/bash
source ./ci_scripts/generic.sh

pip_reqs () {
	pip install -r requirements.txt
	check_return $?
}

sani () {
	pep8 .
	check_return $?
	lizard -C 5 -a 3 -x "*.min.js"
	check_return $?
	find . -name *.py | xargs pylint
	check_return $?
}

test_and_cover () {
	python2.7 -m nose --config=nose.cfg
	check_return $?
}

generate_docs () {
	find . -name '*.py' | grep -v setup.py | xargs pydoc -w
	check_return $?
}
