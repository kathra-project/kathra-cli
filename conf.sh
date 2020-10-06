#!/bin/bash

initInstallJQ || exit 1
initInstallJson2yaml || exit 1

export DOMAIN_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "DOMAIN_HOST")
if [ "$DOMAIN_HOST" == "" ] || [ "$DOMAIN_HOST" == "null" ]
then
    export DOMAIN_HOST="kathra-opensourcing.irtsystemx.org"
    defineVar "DOMAIN_HOST" "Kathra domain's name (dashboard.[domain-name])"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "DOMAIN_HOST" "$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST" "keycloak.$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "APP_MANAGER_HOST" "appmanager.$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "RESOURCE_MANAGER_HOST" "resourcemanager.$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "PIPELINE_MANAGER_HOST" "pipelinemanager.$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "SOURCE_MANAGER_HOST" "sourcemanager.$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "JENKINS_HOST" "jenkins.$DOMAIN_HOST"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "GITLAB_HOST" "gitlab.$DOMAIN_HOST"
fi
printDebug "Kathra's domain: $DOMAIN_HOST"

export RESOURCE_MANAGER_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "RESOURCE_MANAGER_HOST")
printDebug "RESOURCE_MANAGER_HOST: $RESOURCE_MANAGER_HOST"
export APP_MANAGER_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "APP_MANAGER_HOST")
printDebug "RESOURCE_MANAGER_HOST: $APP_MANAGER_HOST"
export PIPELINE_MANAGER_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "PIPELINE_MANAGER_HOST")
printDebug "PIPELINE_MANAGER_HOST: $PIPELINE_MANAGER_HOST"
export SOURCE_MANAGER_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "SOURCE_MANAGER_HOST")
printDebug "SOURCE_MANAGER_HOST: $SOURCE_MANAGER_HOST"
checkApiIsReady "https://$RESOURCE_MANAGER_HOST/api/v1/swagger.json" || exit 1

export JENKINS_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "JENKINS_HOST")
printDebug "JENKINS_HOST: $JENKINS_HOST"
export GITLAB_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "GITLAB_HOST")
printDebug "GITLAB_HOST: $GITLAB_HOST"


export KEYCLOAK_HOST=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST")
printDebug "KEYCLOAK_HOST: $KEYCLOAK_HOST"

getVariableFromContextAndAskIfNotExist $KATHRA_CONTEXT_FILE "KEYCLOAK_CLIENT_ID" "Keycloak client id" "kathra-resource-manager"
getVariableFromContextAndAskIfNotExist $KATHRA_CONTEXT_FILE "KEYCLOAK_CLIENT_SECRET" "Keycloak client secret" "184863e6-0b78-4df6-ae99-38b4003f6db5"
getVariableFromContextAndAskIfNotExist $KATHRA_CONTEXT_FILE "KEYCLOAK_CLIENT_REALM" "Keycloak realm" "kathra"

### CHECK JENKINS SETTINGS
getVariableFromContextAndAskIfNotExist $KATHRA_CONTEXT_FILE "JENKINS_API_USER" "Jenkins's username ($JENKINS_HOST)" "kathra-pipelinemanager"
getVariableFromContextAndAskIfNotExist $KATHRA_CONTEXT_FILE "JENKINS_API_TOKEN" "Jenkins's api token ($JENKINS_HOST)" ""
declare jenkinsTokenUsername=$(curl --fail -XPOST --user ${JENKINS_API_USER}:${JENKINS_API_TOKEN} https://${JENKINS_HOST}/me/api/json 2> /dev/null | jq -r '.id')
if [ "${jenkinsTokenUsername}" == "" ]
then
    while [ "${jenkinsTokenUsername}" == "" ]; do
        printError "Jenkins Token '${JENKINS_API_TOKEN}' for user '${JENKINS_API_USER}' doesn't work with https://${JENKINS_HOST}, unable to find user info, edit $KATHRA_CONTEXT_FILE"
        defineVar "JENKINS_API_TOKEN" "Jenkins's api token ($JENKINS_API_TOKEN)"
        jenkinsTokenUsername=$(curl --fail -XPOST --user ${JENKINS_API_USER}:${JENKINS_API_TOKEN} https://${JENKINS_HOST}/me/api/json 2> /dev/null | jq -r '.id')
    done
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "JENKINS_API_TOKEN" "$JENKINS_API_TOKEN"
fi
printDebug "Jenkins token is associated to user '$jenkinsTokenUsername'"


### CHECK GITLAB SETTINGS
getVariableFromContextAndAskIfNotExist $KATHRA_CONTEXT_FILE "GITLAB_API_TOKEN" "GitLab's api token ($GITLAB_HOST)" ""
declare gitLabTokenUsername=$(curl --fail -s --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "https://${GITLAB_HOST}/api/v4/user"  2> /dev/null | jq -r '.username')
if [ "${gitLabTokenUsername}" == "" ]
then
    while [ "${gitLabTokenUsername}" == "" ]; do
        printError "GitLab Token '${GITLAB_API_TOKEN}' doesn't work with https://${GITLAB_HOST}, unable to find user info, edit $KATHRA_CONTEXT_FILE"
        defineVar "GITLAB_API_TOKEN" "GitLab's api token ($GITLAB_API_TOKEN)"
        gitLabTokenUsername=$(curl --fail -s --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "https://${GITLAB_HOST}/api/v4/user"  2> /dev/null | jq -r '.username')
    done
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "GITLAB_API_TOKEN" "$GITLAB_API_TOKEN"
fi
printDebug "GitLab token is associated to user '$gitLabTokenUsername'"

if [ "$1" == "login" ]
then
    kathraLogin $* || printError "Unable to login"
    printInfo "You are logged in"
    exit 0
fi

### CHECK KEYCLOAK SETTINGS
export TOKEN=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "TOKEN")
if [ ! "$TOKEN" == "" ] && [ ! "$TOKEN" == "null" ]
then
    checkKeycloakTokenIsValid "$KEYCLOAK_HOST" "$KEYCLOAK_CLIENT_REALM" "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET" "$TOKEN" 
    [ $? -ne 0 ] && printError "Token is not valid" &&  export TOKEN=""
fi

if [ "$TOKEN" == "" ] || [ "$TOKEN" == "null" ]
then
    declare USER_LOGIN="user"
    declare USER_PASSWORD="123"
    defineVar "USER_LOGIN" "Kathra user login"
    defineSecretVar "USER_PASSWORD" "Kathra user password"
    
    getKeycloakToken $KEYCLOAK_HOST "$KEYCLOAK_CLIENT_REALM" "$USER_LOGIN" "$USER_PASSWORD" "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET" $TEMP_DIRECTORY/token
    export TOKEN=$(cat $TEMP_DIRECTORY/token)
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "TOKEN" "$TOKEN"
fi
