#!/bin/bash
source ./ci/generic.sh

apt_install() {
	sudo apt-get update
	sudo apt-get install mktemp
}

script_config () {
	mkdir -p $GOPATH/src/github.com/JoePortlandME/
	/bin/cp -Rf $(pwd) $GOPATH/src/github.com/JoePortlandME || true
	cd $GOPATH/src/github.com/JoePortlandME/$APP
	export BRANCH=`git rev-parse --abbrev-ref HEAD`
	export PATH=$PATH:$GOPATH/bin
}

sani_reqs () {
	go get -u github.com/axw/gocov/gocov
	go get -u golang.org/x/tools/cmd/cover
	go get -u github.com/marinbek/gocov-xml
	go get -u github.com/jstemmer/go-junit-report
	go get -u golang.org/x/tools/cmd/vet
	go get -u github.com/alecthomas/gometalinter
	$GOPATH/bin/gometalinter --install --update
}

static_analysis() {
	sani_reqs
	echo Running static analysis in dir $(pwd)
	go vet ./...
	check_return $?
	$GOPATH/bin/gometalinter ./... --disable=gotype --cyclo-over=5
	check_return $?
}

checkjunitvar () {
	if check_var $JUNIT_XML_PATH; then
	    echo "JUNIT_XML_PATH set"
	    return 1
	else 
	    echo "JUNIT_XML_PATH not set"
	    return 0
	fi
}

unit_test () {
	echo Running unit tests in dir $(pwd)
	checkjunitvar
	JUNIT_DIR=${JUNIT_XML_PATH%/*}
	mkdir -p $JUNIT_DIR
	go test -v ./... | $GOPATH/bin/go-junit-report > $JUNIT_XML_PATH
	check_return $?
}

build () {
	echo building in dir $(pwd)
	go build .
	check_return $?
	cp -R $APP ./shippable/$APP
}

# Based on https://gist.github.com/mitchellh/6531113
# Due to a bug in Go, you can't `go get` a private Bitbucket repository
# (issue #5375, linked below). This means you can't `go get ./...` ANY project
# that might depend on a private Bitbucket repository.
#
# This script works around it by detecting Bitbucket imports and using
# `git` directly to clone into it. This will not work if you use private
# Mercurial repositories on Bitbucket.
#
# To use this, just call it as if it is `go get`. Example: "./get.sh ./..."
#
# Go issue: https://code.google.com/p/go/issues/detail?id=5375
 
# This file will be our "set" data structure.
SETFILE=$(mktemp -t hc.XXXXXX)
 
# Support both Darwin and Linux so we have to determine what sed flags to use
SEDFLAGS=""
case $OSTYPE in
    darwin*)
        SEDFLAGS="-E"
        ;;
    *)
        SEDFLAGS="-r"
        ;;
esac
 
# This gets a single dependency.
function get {
    case "$1" in
        bitbucket*)
            local repo=$(echo $1 | \
                sed ${SEDFLAGS} \
                -e 's/^bitbucket.org\/([^\/]+)\/([^\/]+).*$/git@bitbucket.org:\1\/\2.git/')
            local dst=$(echo $1 | sed ${SEDFLAGS} -e 's/^(bitbucket.org\/[^\/]+\/[^\/]+).*$/\1/')
            dst="${GOPATH}/src/${dst}"
            echo "+ Bitbucket: $repo"

            if [ ! -d "$dst" ]; then
                command="git clone $repo $dst"
                echo $command
                $command
            fi
            ;;
        *)
            echo "+ Getting: $1"
            go get $1
            ;;
    esac
}

# This will get all the dependencies for a given package.
function getall {
    local imports=$(go list \
        -f '{{range .Imports}}{{.}} {{end}}' ./...)
    local testImports=$(go list \
        -f '{{range .TestImports}}{{.}} {{end}}' ./...)
    imports="${imports} ${testImports}"
 
    for import in $imports; do
        case $import in
            *.biz*|*.com*|*.org*)
                ;;
            *)
                continue
                ;;
        esac
 
        # Verify that we haven't processed this import yet
        cat $SETFILE | grep "^${import}$" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            continue
        fi
 
        # Add the import to our set file so we don't do it again
        echo $import >>${SETFILE}
 
        # If we're importing "C" then it is cgo, and don't worry about that
        if [ "$import" = "C" ]; then
            continue
        fi
 
        # Get the import and then recurse into it
        get $import
        getall $import
    done
}

#based on https://raw.githubusercontent.com/mlafeldt/chef-runner/v0.7.0/script/coverage
#!/bin/sh
# Generate test coverage statistics for Go packages.
#
# Works around the fact that `go test -coverprofile` currently does not work
# with multiple packages, see https://code.google.com/p/go/issues/detail?id=6909
#
# Usage: script/coverage [--html|--coveralls]
#
#     --html      Additionally create HTML report and open it in browser
#     --coveralls Push coverage statistics to coveralls.io
#

generate_cover_data() {

    workdir=.cover
    profile="$workdir/cover.out"
    mode=set

    rm -rf "$workdir"
    mkdir "$workdir"

    for pkg in "$@"; do
        f="$workdir/$(echo $pkg | tr / -).cover"
        go test -covermode="$mode" -coverprofile="$f" "$pkg"
    done

    echo "mode: $mode" >"$profile"
    grep -h -v "^mode:" "$workdir"/*.cover >>"$profile"
}

cover() {
    echo Running coverage in dir $(pwd)
    COV_DIR=${COV_XML_PATH%/*}
    mkdir -p $COV_DIR
    generate_cover_data $(go list ./...)
    gocov convert .cover/cover.out | gocov-xml > $COV_XML_PATH
    coverage_check
}

coverage_check() {
    # Shell scripts in general do not support float comparisons.
    # Due to that this is a hack which compares the first value after the decimal
    # to 5. This means a coverage of 1.0 will fail (highly unlikely). and
    # coverage of .5999999999999 will fail.

    threshold=5 # 50%
    #Pull coverage line out of XML
    cov=$(grep -o 'coverage line-rate="[0-9]\.*[0-9]*"' $COV_XML_PATH)
    #get first decimal digit number will be 1 or less
    cov=$(echo $cov | grep -o '\.[0-9]')
    # remove decimal point
    cov=$(echo $cov | grep -o '[0-9]')
    # check if value is above threshold
    if [ $cov -ge $threshold ]; then
        return 0
    else
        echo "Coverage check failed. Code coverage is too low."
        return 1
    fi
}
