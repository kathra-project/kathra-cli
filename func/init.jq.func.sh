#!/bin/bash

function initInstallJQ() {
    command -v jq 2> /dev/null > /dev/null && return 0
    printDebug "Install jq"
    [ ! -d $TEMP_DIRECTORY/bin ] && mkdir $TEMP_DIRECTORY/bin
    curl -L -s https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 > $TEMP_DIRECTORY/bin/jq
    chmod +x $TEMP_DIRECTORY/bin/jq
    export PATH="$TEMP_DIRECTORY/bin:$PATH"
    jq --version 2> /dev/null > /dev/null
    [ $? -ne 0 ] && printError "Unable to install jq" && return 1
    printDebug "jq $(jq --version) installed"
    return 0
}
export -f initInstallJQ