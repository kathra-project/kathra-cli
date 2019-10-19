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
    local groupName=$(jq -r '.groupName' < $config)
    local implementationLang=$(jq -r '.implementationLang' < $config)
    local apiFile=$(jq -r '.apiFile' < $config)
    [ "$apiFile" == "null" ] && apiFile="swagger.yml"
    local apiDir=${TEMP_DIRECTORY}/migrateRepositoryKathra.$componentName.api
    local temp=${TEMP_DIRECTORY}/initKathraComponent.$(date +%s)
    
    [ -d $apiDir ] && rm -Rf $apiDir
    git clone git@${gitHost}:${pathApi}.git $apiDir
    cd $apiDir
    [ ! -f $apiFile ] && printError "Unable find $apiFile into $apiDir" && return 1
    
    sed 's#version:\(.*\)-RC-SNAPSHOT#version:\1#g' < $apiFile | sed 's#version:\(.*\)-SNAPSHOT#version:\1#g' > $apiFile.fixedVersion
    mv $apiFile.fixedVersion $apiFile
    
    # create component
    local componentUUID="$(callResourceManager "GET" "components" | jq ".[] | select(.name==\"${componentName}\")" | jq -r '.id')"
    [ "${componentUUID}" == "null" ] && componentUUID=""
    [ "${componentUUID}" == "" ] && kathraCreateComponent ${apiFile} "$componentName" "$groupName" "$componentDescription"
    componentUUID="$(callResourceManager "GET" "components" | jq ".[] | select(.name==\"${componentName}\")" | jq -r '.id')"
    
    importLibrariesForComponent "$componentUUID" "$config"
    [ "${implementationName}" == "null" ] && implementationName=""
    [ "${implementationName}" == "" ] && return 0
    # create implementation
    local implementationUUID="$(callResourceManager "GET" "implementations" | jq ".[] | select(.name==\"${implementationName}\")" | jq -r '.id')"
    [ "${implementationUUID}" == "null" ] && implementationUUID=""
    [ "${implementationUUID}" == "" ] && kathraCreateImplementation "$implementationName" "$componentUUID" "$version" "$implementationLang" "No description"
    
    local implementationRepositoryUUID=$(callAppManager GET "implementations" | jq -r ".[] | select(.name==\"${implementationName}\") | .sourceRepository.id")
    callResourceManager GET "sourcerepositories/$implementationRepositoryUUID" > ${TEMP_DIRECTORY}/migrateRepositoryKathra.$implementationName.sourceRepository
    
    ## remove protected branch
    local implementationRepositoryProviderId=$(jq -r '.providerId' < ${TEMP_DIRECTORY}/migrateRepositoryKathra.$implementationName.sourceRepository)
    curl --request DELETE --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "https://${GITLAB_HOST}/api/v4/projects/$implementationRepositoryProviderId/protected_branches/master"  2> /dev/null > /dev/null
    ## Import implementation source code
    local implementationRepositoryUrl=$(jq -r '.sshUrl' < ${TEMP_DIRECTORY}/migrateRepositoryKathra.$implementationName.sourceRepository)
    local pathImplementation=$(jq -r '.implementation' < $config)
    local tmpDir=${TEMP_DIRECTORY}/mirrorRepositoryAndPush.$implementationName
    [ -d ${TEMP_DIRECTORY}/mirrorRepositoryAndPush.$implementationName ] && rm -rf ${TEMP_DIRECTORY}/mirrorRepositoryAndPush.$implementationName
    mirrorRepositoryAndPush "git@${gitHost}:${pathImplementation}.git" "${implementationRepositoryUrl}" "$tmpDir"
    
    return $?
}

function importLibrariesForComponent() {
    local componentUUID=$1
    local config=$2
    printDebug "importLibrariesForComponent(componentUUID: $componentUUID, config: $config)"

    [ ! "$(jq -r '.javaModel' < $config)" == "null" ] && [ ! "$(jq -r '.javaModel' < $config)" == "" ]  && importLibrary "$componentUUID" "JAVA" "MODEL" "git@${gitHost}:$(jq -r '.javaModel' < $config)"
    [ ! "$(jq -r '.javaInterface' < $config)" == "null" ] && [ ! "$(jq -r '.javaInterface' < $config)" == "" ]  && importLibrary "$componentUUID" "JAVA" "INTERFACE" "git@${gitHost}:$(jq -r '.javaInterface' < $config)"
    [ ! "$(jq -r '.javaClient' < $config)" == "null" ] && [ ! "$(jq -r '.javaClient' < $config)" == "" ] && importLibrary "$componentUUID" "JAVA" "CLIENT" "git@${gitHost}:$(jq -r '.javaClient' < $config)"
    
    [ ! "$(jq -r '.pythonModel' < $config)" == "null" ] && [ ! "$(jq -r '.pythonModel' < $config)" == "" ]  && importLibrary "$componentUUID" "PYTHON" "MODEL" "git@${gitHost}:$(jq -r '.pythonModel' < $config)"
    [ ! "$(jq -r '.pythonInterface' < $config)" == "null" ] && [ ! "$(jq -r '.pythonInterface' < $config)" == "" ]  && importLibrary "$componentUUID" "PYTHON" "INTERFACE" "git@${gitHost}:$(jq -r '.pythonInterface' < $config)"
    [ ! "$(jq -r '.pythonClient' < $config)" == "null" ] && [ ! "$(jq -r '.pythonClient' < $config)" == "" ] && importLibrary "$componentUUID" "PYTHON" "CLIENT" "git@${gitHost}:$(jq -r '.javaClient' < $config)"
}
export -f importLibrariesForComponent

function importLibrary() {
    local componentUUID=$1
    local lang=$2
    local type=$3
    local gitSrc=$4
    local temp=${TEMP_DIRECTORY}/importLibrary.$(date +%s)
    printDebug "importLibrary(componentUUID: $componentUUID, lang: $lang, type: $type, gitSrc: $gitSrc)"
    
    callResourceManager "GET" "libraries" | jq ".[] | select((.component.id==\"${componentUUID}\") and (.type==\"${type}\") and (.language==\"${lang}\"))" > $temp.libFound
    local libUUID=$(jq -r '.id' < $temp.libFound)
    [ "$libUUID" == "null" ] && printError "Unable to find library $lang / $type for component $componentUUID"
    local libUuidSourceRepo=$(jq -r '.sourceRepository.id' < $temp.libFound)
    [ "$libUuidSourceRepo" == "null" ] && printError "Unable to find sourceRepository for library $libUUID"
    callResourceManager GET "sourcerepositories/$libUuidSourceRepo" > ${temp}.sourceRepository
    local sshUrl=$(jq -r '.sshUrl' < ${temp}.sourceRepository)
    local providerId=$(jq -r '.providerId' < ${temp}.sourceRepository)
    echo "providerId:$providerId"
    curl --request DELETE --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "https://${GITLAB_HOST}/api/v4/projects/$providerId/protected_branches/master"  2> /dev/null > /dev/null
    mirrorRepositoryAndPush "$gitSrc" "$sshUrl" "$temp.migrateRepo"
}
export -f importLibrary

function mirrorRepositoryAndPush() {
    printDebug "mirrorRepositoryAndPush($*)"
    local remoteSrc=$1
    local remoteDest=$2
    local tmp=$3
    
    git clone --mirror ${remoteSrc} $tmp
    [ $? -ne 0 ] && printError "Unable to clone mirror from ${remoteSrc}" && exit 1
    cd $tmp
    git push -f --mirror ${remoteDest}
    [ $? -ne 0 ] && printError "Unable to push mirror to ${remoteDest}" && exit 1
}
export -f mirrorRepositoryAndPush

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