#!/bin/bash

function kathraCreateComponent() {
    local swaggerFilePath=$1
    local componentName=$2
    local group=$3
    local description=$4
    local temp=${TEMP_DIRECTORY}/kathraCreateComponent.$(date +%s)
    local groupUUID=
    [ ! -f "$swaggerFilePath" ] && printError "Unable to find swagger file $swaggerFilePath" && return 1
    swaggerFilePath=$(realpath $swaggerFilePath)

    if [[ ${group//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        groupUUID=$group
    else
        callResourceManager "GET" "groups" | jq ".[] | select(.name==\"${group}\")" > ${temp}.groupWithUUID
        groupUUID=$(jq -r '.id' < ${temp}.groupWithUUID)
    fi
    callResourceManager "GET" "groups/$groupUUID" > ${temp}.groupWithDetails
    [ $? -ne 0 ] && printError "Error to retreive group" && return 1
    local groupPath=$(jq -r '.path' < ${temp}.groupWithUUID)

    cat > ${temp}.post << EOF
    {"name":"${componentName}","description":"${description}","metadata":{"groupPath":"${groupPath}"}}
EOF
    callAppManager POST "components" "${temp}.post" "${temp}.post.response"
    [ $? -ne 0 ] && printError "Error to create component" && return 1
    local componentUUID=$(jq -r '.id' < ${temp}.post.response)
    printInfo "Component created with UUID : $componentUUID"
    waitUntilResourceIsReady "components" "$componentUUID" || return 1
    kathraCreateApiVersion $componentUUID ${swaggerFilePath} ${temp}.apiVersionCreated || return 1
    local apiVersionUUID=$(jq -r '.id' < ${temp}.apiVersionCreated)
    printInfo "ApiVersion created with UUID : $apiVersionUUID"
    
    waitUntilResourceIsReady "apiversions" "$apiVersionUUID" || return 1

    callAppManager GET "components" "$componentUUID" 
    return $?
}
export -f kathraCreateComponent

function kathraCreateImplementation() {
    local implementationName=$1
    local versionImplementation="1.1.0"
    local componentIdentifier=$2
    local versionApi=$3
    local language=$4
    local description=$5
    local temp=${TEMP_DIRECTORY}/kathraCreateImplementation.$(date +%s)
    local componentUUID
    if [[ ${componentIdentifier//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        componentUUID=$componentIdentifier
    else
        callResourceManager "GET" "components" | jq ".[] | select(.name==\"${componentIdentifier}\")" > ${temp}.componentWithUUID
        componentUUID="$(jq -r '.id' < ${temp}.componentWithUUID)"
    fi

    callResourceManager "GET" "components/$componentUUID" "" "${temp}.componentsWithDetails"
    [ $? -ne 0 ] && printError "Error to retreive component with UUID $componentUUID" && return 1
    callResourceManager "GET" "apiversions" | jq ".[] | select(.component.id ==\"${componentUUID}\") | select(.version ==\"${versionApi}\")" > ${temp}.apiversionDetails
    local apiVersionUUID=$(jq -r '.id' ${temp}.apiversionDetails)
    [ "$apiVersionUUID" == "" ] && printError "Unable to find version $versionApi for component $componentUUID"
    

    cat > ${temp}.post << EOF
    {"name":"${implementationName}","apiVersion":{"id":"${apiVersionUUID}","version":"${versionImplementation}"},"language":"${language}","desc":"${description}"}
EOF
    
    callAppManager POST "implementations" "${temp}.post" "${temp}.post.response" || return 1
    local implementationUUID=$(jq -r '.id' < ${temp}.post.response)
    printInfo "Implementation created with UUID : $implementationUUID"
    waitUntilResourceIsReady "implementations" "$implementationUUID" || return 1

    callAppManager GET "implementations" "$implementationUUID" 
    return $?
}

function kathraCreateApiVersion() {
    printDebug "kathraCreateApiVersion($*)"
    local componentUUID=$1
    local swaggerFilePath=$2
    local output=$3
    local temp=${TEMP_DIRECTORY}/kathraCreateApiVersion.$(date +%s)

    curl -v -H "Authorization: Bearer $TOKEN" -F "openApiFile=@${swaggerFilePath}" "https://${APP_MANAGER_HOST}/api/v1/components/$componentUUID/apiVersions" > ${output} 2>  ${temp}.err
    
    local httpCode=$(cat ${temp}.err  | grep "< HTTP" | tail -n 1 | sed 's/.*\([0-9]\{3\}\).*/\1/')
    printDebug "httpCode=$httpCode"
    printDebug "${temp}.err"
    if [[ ! "$httpCode" =~ 200|100 ]] 
    then
        printError "Error to create api version" 
        [ -f "$output" ] && printError "$(cat $output)"
        [ -f "${temp}.err" ] && printError "$(cat ${temp}.err)"
        return 1
    fi
    return 0
}
export -f kathraCreateApiVersion

function kathraImportExistingComponent() {
    local confFile=$1
    local name=$(jq -r '.name' < $confFile)
    local version=$(jq -r '.version' < $confFile)
    local groupId=$(jq -r '.metadata.groupId' < $confFile)
    local description=$(jq -r '.description' < $confFile)
    local lang="JAVA"
    
    [ "$description" == "" ] && description="No description for component ${name}"

    cat > ${TEMP_DIRECTORY}/kathraImportExistingComponent.$name.post << EOF
    {
        "name": "${name}",
        "status": "READY",
        "createdBy": "user",
        "metadata": {
            "artifact-artifactName": "$(jq -r '.metadata."artifact-artifactName"' < $confFile)",
            "artifact-groupId": "$(jq -r '.metadata."artifact-groupId"' < $confFile)",
            "groupId": "${groupId}",
            "groupPath": "$(jq -r '.metadata.groupPath' < $confFile)"
        },
        "description": "$description"
    }
EOF
    local groupPath=$(jq -r '.metadata.groupPath' < $confFile)
    callResourceManager POST "components?groupPath=${groupPath}" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$name.post ${TEMP_DIRECTORY}/kathraImportExistingComponent.$name.post.response

    local componentUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/kathraImportExistingComponent.$name.post.response)

    kathraImportApiVersion "$componentUUID" "$name" "$version" "$(jq -r '.metadata."artifact-artifactName"' < $confFile)" "$(jq -r '.metadata."artifact-groupId"' < $confFile)" "${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.firstVersion"

    kathraCreateSourceRepository "$name-api" "$(jq -r '.apiRepositoryPath' < $confFile)" "$(jq -r '.apiRepositoryUrl' < $confFile)" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.API
    cat > ${TEMP_DIRECTORY}/kathraImportExistingComponent.${componentUUID}.patch.apiRepository << EOF
    {
        "apiRepository": {
            "id": "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.API)"
        }
    }
EOF
    callResourceManager PATCH "components/${componentUUID}" ${TEMP_DIRECTORY}/kathraImportExistingComponent.${componentUUID}.patch.apiRepository ${TEMP_DIRECTORY}/kathraImportExistingComponent.${componentUUID}.patch.apiRepository.response


    kathraCreateSourceRepository "$name-model" "$(jq -r '.modelRepositoryPath' < $confFile)" "$(jq -r '.modelRepositoryUrl' < $confFile)" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.MODEL
    kathraCreateSourceRepository "$name-interface" "$(jq -r '.interfaceRepositoryPath' < $confFile)" "$(jq -r '.interfaceRepositoryUrl' < $confFile)" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.INTERFACE
    kathraCreateSourceRepository "$name-client" "$(jq -r '.clientRepositoryPath' < $confFile)" "$(jq -r '.clientRepositoryUrl' < $confFile)" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.CLIENT

    kathraCreatePipeline "$name-model" "$(jq -r '.modelPipelinePath' < $confFile)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.MODEL)" "$(jq -r '.modelRepositoryUrl' < $confFile)" "${groupId}" "${lang}_LIBRARY" "${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.MODEL"
    kathraCreatePipeline "$name-client" "$(jq -r '.clientPipelinePath' < $confFile)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.CLIENT)" "$(jq -r '.clientRepositoryUrl' < $confFile)" "${groupId}" "${lang}_LIBRARY" "${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.CLIENT"
    kathraCreatePipeline "$name-interface" "$(jq -r '.interfacePipelinePath' < $confFile)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.INTERFACE)" "$(jq -r '.interfaceRepositoryUrl' < $confFile)" "${groupId}" "${lang}_LIBRARY" "${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.INTERFACE"
    
    kathraCreateLibrary "$componentUUID" "$name-MODEL" "${lang}" "MODEL" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.MODEL)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.MODEL)" "${version}" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.library.MODEL
    kathraCreateLibrary "$componentUUID" "$name-CLIENT" "${lang}" "CLIENT" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.CLIENT)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.CLIENT)" "${version}" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.library.CLIENT
    kathraCreateLibrary "$componentUUID" "$name-INTERFACE" "${lang}" "INTERFACE" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.INTERFACE)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.INTERFACE)" "${version}" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.library.INTERFACE

    kathraCreateLibraryVersion "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.library.MODEL)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.firstVersion)" "$name-MODEL" "$version" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.libraryVersion.$version.MODEL
    kathraCreateLibraryVersion "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.library.CLIENT)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.firstVersion)" "$name-CLIENT" "$version" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.libraryVersion.$version.CLIENT
    kathraCreateLibraryVersion "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.library.INTERFACE)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.firstVersion)" "$name-INTERFACE" "$version" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.libraryVersion.$version.INTERFACE

    createImplementation "$componentUUID" "$configFile" "${lang}" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.implemention
    createImplementationVersion "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.implemention)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.firstVersion)" "$name" "$version" "${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.implemention.firstVersion"
    defineResourceWithReadyStatus "components" "$componentUUID"
}
export -f kathraImportExistingComponent

function createImplementation() {
    local componentUUID=$1
    local configFile=$2
    local name=$(jq -r '.implementationName' < $confFile)
    local lang=$3
    local out=$4

    kathraCreateSourceRepository "$name-model" "$(jq -r '.implementationRepositoryPath' < $confFile)" "$(jq -r '.implementationRepositoryUrl' < $confFile)" ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.implementation
    kathraCreatePipeline "$name-model" "$(jq -r '.implementationPipelinePath' < $confFile)" "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.implementation)" "$(jq -r '.implementationRepositoryUrl' < $confFile)" "${groupId}" "${lang}_SERVICE" "${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.implementation"

    cat > ${TEMP_DIRECTORY}/createImplementation.component-$componentUUID.$name.post << EOF
    {
        "name": "${name}",
        "status": "READY",
        "metadata": {
            "artifact-artifactName": "$(jq -r '.metadata."artifact-artifactName"' < $confFile)",
            "artifact-groupId": "$(jq -r '.metadata."artifact-groupId"' < $confFile)",
            "groupId": "${groupId}",
            "groupPath": "$(jq -r '.metadata.groupPath' < $confFile)",
            "path": "$(jq -r '.implementationPipelinePath' < $confFile)"
        },
        "sourceRepository": {
            "id": "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.sourceRepository.implementation)"
        },
        "pipeline": {
            "id": "$(cat ${TEMP_DIRECTORY}/kathraImportExistingComponent.$componentUUID.pipeline.implementation)"
        },
        "language": "${lang}",
        "component": {
            "id": "${componentUUID}"
        }
    }
EOF
    callResourceManager POST "implementations" ${TEMP_DIRECTORY}/createImplementation.component-$componentUUID.$name.post ${TEMP_DIRECTORY}/createImplementation.component-$componentUUID.$name.post.response
    local implementationUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/createImplementation.component-$componentUUID.$name.post.response)
    echo $implementationUUID > $out
    defineResourceWithReadyStatus "implementations" "$implementationUUID"
}
export -f createImplementation

function createImplementationVersion() {
    printDebug "createImplementationVersion($*)"
    local implementationUUID=$1
    local apiVersionUUID=$2
    local name=$3
    local version=$4
    local out=$5
cat > ${TEMP_DIRECTORY}/createImplementationVersion.implementation-$implementationUUID.$version.post << EOF
    {
    "name": "$name:$version",
    "status": "READY",
    "version": "${version}",
    "implementation": {
        "id": "${implementationUUID}"
    },
    "apiVersion": {
        "id": "${apiVersionUUID}"
    }
}
EOF
    callResourceManager POST "implementationversions" ${TEMP_DIRECTORY}/createImplementationVersion.implementation-$implementationUUID.$version.post ${TEMP_DIRECTORY}/createImplementationVersion.implementation-$implementationUUID.$version.post.response
    local implementationUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/createImplementationVersion.implementation-$implementationUUID.$version.post.response)
    echo $implementationUUID > $out
    defineResourceWithReadyStatus "implementationversions" "$implementationUUID"
}
export -f createImplementationVersion

function kathraCreateLibrary() {
    printDebug "kathraCreateLibrary($*)"
    local componentUUID=$1
    local name=$2
    local lang=$3
    local type=$4
    local repositoryUUID=$5
    local pipelineUUID=$6
    local firstVersion=$7
    local out=$8

cat > ${TEMP_DIRECTORY}/kathraCreateLibrary.component-$componentUUID.$name-${lang}-$type.post << EOF
    {
        "name": "${name}-${lang}-${type}",
        "status": "READY",
        "language": "${lang}",
        "component": {
            "id": "${componentUUID}"
        },
        "sourceRepository": {
            "id": "${repositoryUUID}"
        },
        "pipeline": {
            "id": "${pipelineUUID}"
        },
        "type": "${type}"
    }
EOF
    callResourceManager POST "libraries?groupPath=${groupPath}" ${TEMP_DIRECTORY}/kathraCreateLibrary.component-$componentUUID.$name-${lang}-$type.post ${TEMP_DIRECTORY}/kathraCreateLibrary.component-$componentUUID.$name-${lang}-$type.post.response
    local libraryUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/kathraCreateLibrary.component-$componentUUID.$name-${lang}-$type.post.response)
    echo "${libraryUUID}" > "$out"
    defineResourceWithReadyStatus "libraries" "$libraryUUID"
}
export -f kathraCreateLibrary

function kathraCreateSourceRepository() {
    printDebug "kathraCreateSourceRepository($*)"
    local name=$1
    local path=$2
    local repositorySshUrl=$3
    local out=$4

cat > ${TEMP_DIRECTORY}/kathraCreateSourceRepository.$name.post << EOF
    {
        "name": "${name}",
        "status": "READY",
        "provider": "Gitlab",
        "providerId": "",
        "path": "${path}",
        "sshUrl": "${repositorySshUrl}",
        "httpUrl": "",
        "webUrl": ""
    }
EOF
    callResourceManager POST "sourcerepositories"  ${TEMP_DIRECTORY}/kathraCreateSourceRepository.$name.post ${TEMP_DIRECTORY}/kathraCreateSourceRepository.$name.post.response
    local sourceRepositoryUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/kathraCreateSourceRepository.$name.post.response)
    echo "${sourceRepositoryUUID}" > "$out"
    defineResourceWithReadyStatus "sourcerepositories" "$sourceRepositoryUUID"
}
export -f kathraCreateSourceRepository

function kathraCreateSourceRepositoryGitLab() {
    printDebug "kathraCreateSourceRepositoryGitLab($*)"
    local name=$1
    local path=$2
    local deployKeyToEnabled=$3
    local out=$4
    cat > ${TEMP_DIRECTORY}/kathraCreateSourceRepositoryGitLab.$name.post << EOF
    {
        "name": "${name}",
        "path": "${path}"
    }
EOF
    curl -v -s --fail -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "https://${SOURCE_MANAGER_HOST}sourceRepositories?deployKeys=$deployKeyToEnabled" -d @${TEMP_DIRECTORY}/kathraCreateSourceRepositoryGitLab.$name.post > $out
    [ $? -ne 0 ] && printError "Unable to call source manager" && exit 1
}
export -f kathraCreateSourceRepositoryGitLab

function kathraCreatePipeline() {
    printDebug "kathraCreatePipeline($*)"
    local name=$1
    local path=$2
    local repositoryUUID=$3
    local repositoryURL=$4
    local credentialId=$5
    local template=$6
    local out=$7

    createPipelineIntoPipelineManager "$path" "$template" "$repositoryURL" "$credentialId" "${TEMP_DIRECTORY}/createPipelineIntoPipelineManager.$name.post"

    local providerId=$(jq -r '.providerId' < "${TEMP_DIRECTORY}/createPipelineIntoPipelineManager.$name.post")
    
cat > ${TEMP_DIRECTORY}/kathraCreatePipeline.pipeline.$name.post << EOF
    {
        "name": "${name}",
        "status": "READY",
        "provider": "jenkins",
        "providerId": "${providerId}",
        "credentialId": "${credentialId}",
        "path": "${path}",
        "sourceRepository": {
            "id": "${repositoryUUID}"
        },
        "template": "${template}"
    }
EOF
    callResourceManager POST "pipelines" ${TEMP_DIRECTORY}/kathraCreatePipeline.pipeline.$name.post ${TEMP_DIRECTORY}/kathraCreatePipeline.pipeline.$name.post.response
    local pipelineUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/kathraCreatePipeline.pipeline.$name.post.response)
    echo "${pipelineUUID}" > "$out"
    defineResourceWithReadyStatus "pipelines" "$pipelineUUID"
}
export -f kathraCreatePipeline

function createPipelineIntoPipelineManager() {
    printDebug "createPipelineIntoPipelineManager($*)"
    
    local path=$1
    local template=$2
    local gitRepository=$3
    local credentialId=$4
    local out=$5
    local json="{
	\"path\":\"${path}\",
	\"sourceRepository\": {\"sshUrl\":\"${gitRepository}\"},
	\"template\":\"${template}\",
	\"credentialId\":\"${credentialId}\"
}"
    curl -s -X POST https://${PIPELINE_MANAGER_HOST}/api/v1/pipelines \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Cache-Control: no-cache' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: application/json' \
  -H 'accept-encoding: gzip, deflate' \
  -H 'cache-control: no-cache' \
  -d "${json}" > $out
  [ $? -ne 0 ] && printError "Unable to call resource manager"
}
export -f createPipelineIntoPipelineManager

function kathraCreateLibraryVersion() {
    printDebug "kathraCreateLibraryVersion($*)"
    local libraryUUID=$1
    local apiVersionUUID=$2
    local name=$3
    local version=$4
    local out=$5

cat > ${TEMP_DIRECTORY}/kathraCreateLibraryVersion.library-$libraryUUID.$apiVersionUUID-$name-$version.post << EOF
    {
        "name": "${name}-${version}",
        "status": "READY",
        "library": {
            "id": "${libraryUUID}"
        },
        "apiVersion": {
            "id": "${apiVersionUUID}"
        },
        "apiRepositoryStatus": "READY",
        "pipelineStatus": "READY"
    }
EOF
    callResourceManager POST "libraryapiversions" ${TEMP_DIRECTORY}/kathraCreateLibraryVersion.library-$libraryUUID.$apiVersionUUID-$name-$version.post ${TEMP_DIRECTORY}/kathraCreateLibraryVersion.library-$libraryUUID.$apiVersionUUID-$name-$version.post.response
    local libraryVersionUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/kathraCreateLibraryVersion.library-$libraryUUID.$apiVersionUUID-$name-$version.post.response)
    echo "${libraryVersionUUID}" > "$out"
    defineResourceWithReadyStatus "libraryapiversions" "$libraryVersionUUID"
}
export -f kathraCreateLibraryVersion


function kathraImportApiVersion() {
    printDebug "kathraImportApiVersion($*)"
    local componentUUID=$1
    local name=$2
    local version=$3
    local artifactName=$4
    local artifactGroupId=$5
    local out=$6

cat > ${TEMP_DIRECTORY}/kathraImportApiVersion.component-$componentUUID.$version.post << EOF
    {
        "name": "${name} ${version}",
        "status": "READY",
        "metadata": {
            "artifact-artifactName": "${artifactName}",
            "artifact-groupId": "${artifactGroupId}"
        },
        "component": {
            "id": "${componentUUID}"
        },
        "released": false,
        "version": "${version}",
        "apiRepositoryStatus": "READY"
    }
EOF
    callResourceManager POST "apiversions" ${TEMP_DIRECTORY}/kathraImportApiVersion.component-$componentUUID.$version.post ${TEMP_DIRECTORY}/kathraImportApiVersion.component-$componentUUID.$version.post.response
    local apiVersionUUID=$(jq -r '.id' < ${TEMP_DIRECTORY}/kathraImportApiVersion.component-$componentUUID.$version.post.response)
    echo "${apiVersionUUID}" > "$out"
    defineResourceWithReadyStatus "apiversions" "$apiVersionUUID"
}
export -f kathraImportApiVersion

