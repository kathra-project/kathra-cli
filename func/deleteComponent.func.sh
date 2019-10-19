#!/bin/bash

function kathraDeleteComponent() {
    printDebug "kathraDeleteComponent($*)"
    local uuid=$1
    local purge=$2
    [ "$purge" == "1" ] && printAlert "All pipelines and sources repositories will be deleted in 5s" && sleep 5
    
    callResourceManager "GET" "components/$uuid" "" "${TEMP_DIRECTORY}/component.$uuid" 
    
    local sourceRepositoryUUID=$(jq -r '.apiRepository.id' < ${TEMP_DIRECTORY}/component.$uuid)
    [ ! "$sourceRepositoryUUID" == "null" ] &&  kathraDeleteSourceRepository ${sourceRepositoryUUID} $purge

    jq -r '.libraries[] | .id ' < ${TEMP_DIRECTORY}/component.$uuid | xargs -I{} -n 1 -P 5  bash -c "kathraDeleteLibrary {} $purge"
    jq -r '.versions[] | .id ' < ${TEMP_DIRECTORY}/component.$uuid | xargs -I{} -n 1 -P 5  bash -c 'kathraDeleteApiVersion {}'
    jq -r '.implementations[] | .id ' < ${TEMP_DIRECTORY}/component.$uuid | xargs -I{} -n 1 -P 5  bash -c "kathraDeleteImplementation {} $purge"

    callResourceManager "DELETE" "components/$uuid" > /dev/null
    return $?
}

function kathraDeleteLibrary() {
    printDebug "kathraDeleteLibrary($*)"
    local uuid=$1
    local purge=$2
    callResourceManager "GET" "libraries/$uuid" "" "${TEMP_DIRECTORY}/library.$uuid" 
    jq -r '.versions[] | .id ' < ${TEMP_DIRECTORY}/library.$uuid | xargs -I{} -n 1 -P 5  bash -c 'kathraDeleteLibraryApiVersion {}'
    local sourceRepositoryUUID=$(jq -r '.sourceRepository | .id ' < ${TEMP_DIRECTORY}/library.$uuid)
    local pipelineUUID=$(jq -r '.pipeline | .id ' < ${TEMP_DIRECTORY}/library.$uuid)
    [ ! "$sourceRepositoryUUID" == "null" ] && kathraDeleteSourceRepository ${sourceRepositoryUUID} $purge
    [ ! "$pipelineUUID" == "null" ] && kathraDeletePipeline ${pipelineUUID} $purge
}
export -f kathraDeleteLibrary

function kathraDeleteLibraryApiVersion() {
    printDebug "kathraDeleteLibraryApiVersion($*)"
    callResourceManager "DELETE" "libraryapiversions/$1" > /dev/null
}
export -f kathraDeleteLibraryApiVersion

function kathraDeleteApiVersion() {
    printDebug "kathraDeleteApiVersion($*)"
    local uuid=$1
    callResourceManager "GET" "apiversions/$uuid" "" "${TEMP_DIRECTORY}/apiversion.$uuid" 
}
export -f kathraDeleteApiVersion

function kathraDeleteImplementation() {
    printDebug "kathraDeleteImplementation($*)"
    local uuid=$1
    local purge=$2
    callResourceManager "GET" "implementations/$uuid" "" "${TEMP_DIRECTORY}/implementation.$uuid" 
    jq -r '.versions[] | .id ' < ${TEMP_DIRECTORY}/implementation.$uuid | xargs -I{} -n 1 -P 5  bash -c 'kathraDeleteImplementationVersion {}'
    local sourceRepositoryUUID=$(jq -r '.sourceRepository | .id ' < ${TEMP_DIRECTORY}/implementation.$uuid)
    local pipelineUUID=$(jq -r '.pipeline | .id ' < ${TEMP_DIRECTORY}/implementation.$uuid)
    [ ! "$sourceRepositoryUUID" == "null" ] && kathraDeleteSourceRepository ${sourceRepositoryUUID} $purge
    [ ! "$pipelineUUID" == "null" ] && kathraDeletePipeline ${pipelineUUID} $purge
    callResourceManager "DELETE" "implementations/$uuid" > /dev/null
}
export -f kathraDeleteImplementation

function kathraDeleteImplementationVersion() {
    printDebug "kathraDeleteImplementationVersion($*)"
    local uuid=$1
    callResourceManager "DELETE" "implementationversions/$uuid" > /dev/null
}
export -f kathraDeleteImplementationVersion


function kathraDeleteSourceRepository() {
    printDebug "kathraDeleteSourceRepository($*)"
    local purge=$2
    if [ "$purge" == "1" ]
    then
        local providerId=$(callResourceManager "GET" "sourcerepositories/$1" | jq -r '.providerId')
        [ "$providerId" == "null" ] && printWarn "Unable to find providerId for sourceRepository $1" || deleteRepositoryGitLab "$GITLAB_HOST" "$GITLAB_API_TOKEN" "$providerId"
    fi
    callResourceManager "DELETE" "sourcerepositories/$1" > /dev/null
}
export -f kathraDeleteSourceRepository

function kathraDeletePipeline() {
    printDebug "kathraDeletePipeline($*)"
    local purge=$2
    if [ "$purge" == "1" ]
    then
        callResourceManager "GET" "pipelines/$1"
        local providerId=$(callResourceManager "GET" "pipelines/$1" | jq -r '.providerId')
        [ "$providerId" == "null" ] && printWarn "Unable to find providerId for pipeline $1" || jenkinsDeletePipeline "$JENKINS_HOST" "$JENKINS_API_TOKEN" "$providerId"
    fi
    callResourceManager "DELETE" "pipelines/$1" > /dev/null
}
export -f kathraDeletePipeline

function jenkinsDeletePipeline() {
    printDebug "jenkinsDeletePipeline($*)"
    local host=$1
    local token=$2
    local path=$3
    curl --fail -XPOST --user kathra-pipelinemanager:${token} https://${host}$(echo "${path}" | sed 's#/#/job/#g')/toDelete 2> /dev/null > /dev/null
    local rc=$?
    [ $rc -ne 0 ] && printError "Unable to delete pipeline : $path"
    return $rc
}
export -f jenkinsDeletePipeline
