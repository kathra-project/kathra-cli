#!/bin/bash
function initInstallJQ() {
    command -v jq 2> /dev/null > /dev/null && return 0
    printDebug "Install jq"
    [ ! -d $TEMP_DIRECTORY/bin ] && mkdir $TEMP_DIRECTORY/bin

    local system="linux64"
    local ext=""
    local basePlugin=$SCRIPT_DIR/.terraform/plugins
    [ "$OSTYPE" == "win32" ] && system="win32" && ext=".exe"
    [ "$OSTYPE" == "msys" ]  && system="win64" && ext=".exe"

    curl -L -s https://github.com/stedolan/jq/releases/download/jq-1.6/jq-$system${ext} > $TEMP_DIRECTORY/bin/jq${ext}
    chmod +x $TEMP_DIRECTORY/bin/jq
    export PATH="$TEMP_DIRECTORY/bin:$PATH"
    jq --version 2> /dev/null > /dev/null
    [ $? -ne 0 ] && printError "Unable to install jq" && return 1
    printDebug "jq $(jq --version) installed"
    return 0
}
export -f initInstallJQ


function initInstallJson2yaml() {
    command -v json2yaml 2> /dev/null > /dev/null && return 0
    printDebug "Install json2yaml"
    [ ! -d $TEMP_DIRECTORY/bin ] && mkdir $TEMP_DIRECTORY/bin
    
    local system="linux_amd64"
    local ext=""
    local basePlugin=$SCRIPT_DIR/.terraform/plugins
    [ "$OSTYPE" == "win32" ] && system="windows_386" && ext=".exe"
    [ "$OSTYPE" == "msys" ]  && system="windows_amd64" && ext=".exe"

    curl -L -s https://github.com/bronze1man/json2yaml/releases/download/1.0/json2yaml_${system}_amd64${ext} > $TEMP_DIRECTORY/bin/json2yaml${ext}
    chmod +x $TEMP_DIRECTORY/bin/json2yaml${ext}
    export PATH="$TEMP_DIRECTORY/bin:$PATH"
    jq --version 2> /dev/null > /dev/null
    [ $? -ne 0 ] && printError "Unable to install json2yaml" && return 1
    printDebug "json2yaml $(json2yaml --version) installed"
    return 0
}
export -f initInstallJQ