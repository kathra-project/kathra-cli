#!/bin/bash
function checkApiIsReady() {
    printDebug "checkApiIsReady($*)"
    local swaggerUrl=$1
    curl --fail $swaggerUrl 2> /dev/null > /dev/null
    [ $? -ne 0 ] && printError "Unable to find $swaggerUrl" && return 1
    return 0
}
export -f checkApiIsReady


function defineVar() {
    local varName=$1
    local msg=$2
    local override
    read -p "$(printInfo $msg [default:${!varName}] ?)" override
    [ ! "$override" == "" ] && eval "$varName=$override"
}
export -f defineVar

function defineSecretVar() {
    local varName=$1
    local msg=$2
    local override
    read -s -p "$(printInfo $msg [default:${!varName}] ?)" override
    [ ! "$override" == "" ] && eval "$varName=$override"
}
export -f defineSecretVar

function getVariableFromContextAndAskIfNotExist() {
    local file=$1
    local variableName=$2
    local variableMessage=$3
    local defaultValue=$4

    local currentValue=$(readEntryIntoFile "$file" "$variableName")
    if [ "$currentValue" == "" ] || [ "$currentValue" == "null" ]
    then
        [ ! "$defaultValue" == "" ] && eval "export $variableName=$defaultValue"
        defineVar "$variableName" "$variableMessage"
        writeEntryIntoFile "$file" "$variableName" "${!variableName}"
    else
        eval "export $variableName=$currentValue"
    fi
}

function printError(){
    echo -e "\033[31;1m $* \033[0m" 1>&2
}
export -f printError
function printWarn(){
    echo -e "\033[33;1m $* \033[0m" 1>&2
}
export -f printWarn
function printInfo(){
    echo -e "\033[33;1m $* \033[0m" 1>&2
}
export -f printInfo
function printDebug(){
    echo -e "\033[94;1m $* \033[0m" 1>&2
}
export -f printDebug

function printAlert(){
    echo -e "\e[41m $* \033[0m" 1>&2
}
export -f printAlert

function writeEntryIntoFile(){
    local file=$1
    local key=$2
    local value=$3
    [ ! -f $file ] && echo "{}" > $file
    jq ".$key = \"$value\"" $file > $file.updated && mv $file.updated $file
}
export -f writeEntryIntoFile

function readEntryIntoFile() {
    local file=$1
    local key=$2
    [ ! -f $file ] && return 1
    jq -r ".$key" < $file
    return 0
}
export -f readEntryIntoFile

function callResourceManager() {
    printDebug "callResourceManager($*)"
    callKathraBackend "$1" "https://${RESOURCE_MANAGER_HOST}/api/v1/${2}" "$3" "$4"
    return $?
}
export -f callResourceManager


function waitUntilResourceIsReady() {
    printDebug "waitUntilResourceIsReady($*)"
    local type=$1
    local uuid=$2

    local status='PENDING'
    while [ "$status" == 'PENDING' ]; do
        sleep 3
        callResourceManager "GET" "$type/$uuid" > ${temp}.waitUntilResourceIsReady.$uuid
        status=$(jq -r '.status' < ${temp}.waitUntilResourceIsReady.$uuid)
    done
    if [ ! "$status" == "READY" ] 
    then
        printError "Resource ($type) $uuid has status $status"
        printResourceError $type $uuid
        return 1
    fi
    printInfo "Resource ($type) $uuid is $status"
}
export -f waitUntilResourceIsReady


function printResourceError() {
    printDebug "printResourceError($*)"
    local type=$1
    local uuid=$2
    printError "$(callResourceManager "GET" "$type/$uuid" | jq -r '.metadata')"
}

function callAppManager() {
    printDebug "callAppManager($*)"
    callKathraBackend "$1" "https://${APP_MANAGER_HOST}/api/v1/${2}" "$3" "$4"
    return $?
}
export -f callAppManager


function callKathraBackend() {
    printDebug "callKathraBackend($*)"
    local method=$1
    local URL=$2
    local json=$3
    local ouputFile=$4
    local stdOut="/dev/stdout"
    local dataJson="${TEMP_DIRECTORY}/callKathraBackend.$(date +%s%N).json"
    local stdErr="${TEMP_DIRECTORY}/callKathraBackend.$(date +%s%N).err"
    [ ! "$ouputFile" == "" ] && stdOut="$ouputFile"

    local cmd="curl -v -X $method -H \"Accept: application/json, text/plain, */*\" -H \"Authorization: Bearer $TOKEN\" -H \"Content-Type: application/json\" ${URL}"
    
    if [ ! "$json" == "" ]
    then
        [ ! -f "$json" ] && echo "$json" > $dataJson && cmd="$cmd -d @${dataJson}"
        [ -f "$json" ] && cmd="$cmd -d @${json}"
    fi

    [ ! "$ouputFile" == "" ] && cmd="$cmd > $ouputFile"
    cmd="$cmd 2> $stdErr"

    eval "$cmd"
    local rc=$?
    local httpCode=$(grep "< HTTP" < $stdErr | tail -n 1 | sed 's/.*\([0-9]\{3\}\).*/\1/')
    if [ $rc -ne 0 ] || [ ! "$httpCode" == "200" ] 
    then
        printError "Unable to call resource manager, httpCode : $httpCode" 
        printError "$cmd"
        [ -f "$ouputFile" ] && printError "$(cat $ouputFile)"
        [ -f "$stdErr" ] && printError "$(cat $stdErr)"
        return 1
    fi
    return 0
}
export -f callKathraBackend

export -f callResourceManager
function defineResourceWithReadyStatus() {
    local type=$1
    local uuid=$2
    cat > ${TEMP_DIRECTORY}/defineResourceWithReadyStatus.post << EOF
{
    "status": "READY"
}
EOF
    callResourceManager PATCH "$type/$uuid" ${TEMP_DIRECTORY}/defineResourceWithReadyStatus.post ${TEMP_DIRECTORY}/defineResourceWithReadyStatus.post.response
}
export -f defineResourceWithReadyStatus


function printAsArray() {
    cat -
}
export -f printAsArray

function findInArgs() {
    local keyToFind=$1
    shift 
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
        local key=$(echo "$1" | cut -d'=' -f1)
        local value=$(echo "$1" | cut -d'=' -f2)
        [ "${key}" == "${keyToFind}" ] && echo $value && return 0
        shift
    done
    return 1
}
