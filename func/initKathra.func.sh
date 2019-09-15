#!/bin/bash

function initKathraComponent() {
    local config=$1
    [ ! -f "$config" ] && printError "unable to find file $config" && exit 1
    local componentName=$(jq -r '.componentName' < $config | tr ' ' '_')
    local componentDescription=$(jq -r '.description' < $config)
    local implementationName=$(jq -r '.implementationName' < $config | tr ' ' '_')
    local gitHost=$(jq -r '.gitHost' < $config)
    local version=$(jq -r '.version' < $config)
    local pathApi=$(jq -r '.api' < $config)
    local pathModel=$(jq -r '.model' < $config)
    local pathClient=$(jq -r '.client' < $config)
    local pathInterface=$(jq -r '.interface' < $config)
    local pathImplementation=$(jq -r '.implementation' < $config)

    local newPathApi="${teamPath}/components/$componentName/$componentName-api"
    local newPathModel="${teamPath}/components/$componentName/JAVA/$componentName-model"
    local newPathClient="${teamPath}/components/$componentName/JAVA/$componentName-client"
    local newPathInterface="${teamPath}/components/$componentName/JAVA/$componentName-interface"
    local newPathImplementation="${teamPath}/components/$componentName/implementations/$implementationName"

    [ ! "${pathApi}" == "null" ] && migrateRepositoryKathra "${gitHost}" "${componentName}-api" "${pathApi}" "${newPathApi}" "${deployKey}"
    [ ! "${pathModel}" == "null" ] && migrateRepositoryKathra "${gitHost}" "${componentName}-model" "${pathModel}" "${newPathModel}" "${deployKey}"
    [ ! "${pathClient}" == "null" ] && migrateRepositoryKathra "${gitHost}" "${componentName}-client" "${pathClient}" "${newPathClient}" "${deployKey}"
    [ ! "${pathInterface}" == "null" ] && migrateRepositoryKathra "${gitHost}" "${componentName}-interface" "${pathInterface}" "${newPathInterface}" "${deployKey}"
    migrateRepositoryKathra "${gitHost}" "${implementationName}" "${pathImplementation}" "${newPathImplementation}" "${deployKey}"
    
    local componentConfigFile="${TEMP_DIRECTORY}/initKathraComponent.$componentName.post"

    cat > "$componentConfigFile" << EOF
{
    "name": "${componentName}",
    "description": "${componentDescription}",
    "version": "${version}",
    "status": "READY",
    "metadata": {
        "artifact-artifactName": "${componentName}",
        "artifact-groupId": "${artifactGroupId}",
        "groupId": "${deployKey}",
        "groupPath": "${teamPath}"
    },
    "implementationRepositoryUrl" : "git@${GITLAB_HOST}:${newPathImplementation}.git",
    "implementationName": "${implementationName}",
    "implementationRepositoryPath" : "${newPathImplementation}",
    "implementationPipelinePath" : "${jenkinsComponentsRootDir}/${componentName}/implementations/java/${implementationName}" 
}
EOF
    if [ ! "${pathApi}" == "null" ] 
    then
        jq ".apiRepositoryPath = \"${newPathApi}\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".apiRepositoryUrl = \"git@${GITLAB_HOST}:${newPathApi}.git\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
    fi
    if [ ! "${pathModel}" == "null" ] 
    then
        jq ".modelRepositoryUrl = \"git@${GITLAB_HOST}:${newPathModel}.git\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".modelRepositoryPath = \"${newPathModel}\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".modelPipelinePath = \"${jenkinsComponentsRootDir}/${componentName}/${componentName}-model\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
    fi
    if [ ! "${pathInterface}" == "null" ] 
    then
        jq ".interfaceRepositoryUrl = \"git@${GITLAB_HOST}:${newPathInterface}.git\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".interfaceRepositoryPath = \"${newPathInterface}\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".interfacePipelinePath = \"${jenkinsComponentsRootDir}/${componentName}/${componentName}-interface\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
    fi
    if [ ! "${pathClient}" == "null" ] 
    then
        jq ".clientRepositoryUrl = \"git@${GITLAB_HOST}:${newPathClient}.git\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".clientRepositoryPath = \"${newPathClient}\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
        jq ".clientPipelinePath = \"${jenkinsComponentsRootDir}/${componentName}/${componentName}-client\"" $componentConfigFile > $componentConfigFile.updated && mv $componentConfigFile.updated $componentConfigFile
    fi

    cat "$componentConfigFile"
    kathraImportExistingComponent "$componentConfigFile"
}
export -f initKathraComponent


function migrateRepositoryKathra() {
    printDebug "migrateRepositoryKathra($*)"
    local gitHostSrc=$1
    local name=$2
    local pathSrc=$3
    local pathDest=$4
    local deployKey=$5

    
    [ -d "${TEMP_DIRECTORY}/migrateRepositoryKathra.$name" ] && rm -Rf "${TEMP_DIRECTORY}/migrateRepositoryKathra.$name"
    git clone --mirror git@${gitHostSrc}:${pathSrc}.git ${TEMP_DIRECTORY}/migrateRepositoryKathra.$name
    [ $? -ne 0 ] && printError "Unable to pull git@${gitHostSrc}:${pathSrc}.git" && exit 1
    


    deleteRepositoryGitLab ${GITLAB_HOST} ${GITLAB_API_TOKEN} ${pathDest}

    kathraCreateSourceRepositoryGitLab "${name}" "${pathDest}" "${deployKey}" "${TEMP_DIRECTORY}/kathraCreateSourceRepositoryGitLab.$name.created"

    # remove protected branch
    local sshUrl=$(jq -r '.sshUrl' < ${TEMP_DIRECTORY}/kathraCreateSourceRepositoryGitLab.$name.created)
    local providerId=$(jq -r '.providerId' < ${TEMP_DIRECTORY}/kathraCreateSourceRepositoryGitLab.$name.created)
    curl --request DELETE --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "https://${GITLAB_HOST}/api/v4/projects/$providerId/protected_branches/master"  2> /dev/null > /dev/null

    cd ${TEMP_DIRECTORY}/migrateRepositoryKathra.$name 
    printDebug "Push ${TEMP_DIRECTORY}/migrateRepositoryKathra.$name to $sshUrl"
    git push -f --mirror ${sshUrl}
    [ $? -ne 0 ] && printError "Unable to push to ${sshUrl}" && exit 1
}
export -f migrateRepositoryKathra

function deleteRepositoryGitLab() {
    printDebug "deleteRepositoryGitLab($*)"
    local host=$1
    local token=$2
    local path=$3
    curl --request DELETE --header "PRIVATE-TOKEN: ${token}" "https://${host}/api/v4/projects/$(urlencode $(echo $path | sed 's#^/##g'))" 2> /dev/null > /dev/null
}
export -f deleteRepositoryGitLab

function urlencode() {
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C
    
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    LC_COLLATE=$old_lc_collate
}
export -f urlencode

function initKathraComponents() {
    printDebug "initKathraComponents($*)"
    local config=$(realpath $1)
    local -i countComponents=$(jq 'length' < $config)
    for i in $(seq 0 $(($countComponents - 1))); 
    do 
        jq ".[$i]" < $config > "${TEMP_DIRECTORY}/initKathraComponent.$i.json"
        initKathraComponent "${TEMP_DIRECTORY}/initKathraComponent.$i.json"
    done
}
export -f initKathraComponents

function retreiveGroup() {
    local team=$1
    local out=$2
    callResourceManager "GET" "groups" "" "${TEMP_DIRECTORY}/groups.existings" 
    local teamUUID=$(cat ${TEMP_DIRECTORY}/groups.existings | jq -r ".[] | select(.name == \"$team\") | .id ")
    [ "$teamUUID" == "null" ] && printError "Error, unable to find group $team " && exit 1
    echo $teamUUID > $out
}

function generateConfigFile() {
    local file=$1
    local components=(  'sourcemanager'
                        'appmanager'
                        'pipelinemanager'
                        'binaryrepositorymanager'
                        'usermanager'
                        'resourcemanager'
                        'catalogmanager'
                        'catalogupdater'
                        'plateformmanager'
                        'codegen'
                        'dashboard'
                        'usersync')
    local implementations=( 'sourcemanager-gitlab'
                            'appmanager-swagger'
                            'pipelinemanager-jenkins'
                            'binaryrepositorymanager-harbor'
                            'usermanager-keycloak'
                            'resourcemanager-arangodb'
                            'catalogmanager-kube'
                            'catalogupdater'
                            'plateformmanager-kube'
                            'codegen-swagger'
                            'dashboard-angular'
                            'usersync')

    [ -f $file ] && cp kathra.components.json $file
    
    # get length of an array
    local countComponents=${#components[@]}

    echo "[" > $file
    # use for loop to read all values and indexes
    for (( i=1; i<${countComponents}+1; i++ ));
    do
        local componentName=${components[$i-1]}
        local implementationName=${implementations[$i-1]}
        cat > $file.item.$componentName << EOF
{
    "componentName": "${componentName}",
    "version": "1.0.0-RC-SNAPSHOT",
    "implementationName": "${implementationName}",
    "relativePath": "KATHRA/kathra-services/kathra-${componentName}/kathra-${componentName}",
    "api" : "KATHRA/kathra-services/kathra-${componentName}/kathra-${componentName}-api",
    "model" : "KATHRA/kathra-services/kathra-${componentName}/kathra-${componentName}-model",
    "interface" : "KATHRA/kathra-services/kathra-${componentName}/kathra-${componentName}-interface",
    "client" : "KATHRA/kathra-services/kathra-${componentName}/kathra-${componentName}-client",
    "implementation" : "KATHRA/kathra-services/kathra-${componentName}/kathra-${implementationName}"
}
EOF
        cat $file.item.$componentName >> $file
        [ $i != ${countComponents} ] && echo "," >> $file
    done
    echo "]" >> $file
    cat $file
}
