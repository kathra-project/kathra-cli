#!/bin/bash

function kathraLogin() {
    declare USER_LOGIN="$(findInArgs '--username' $*)"
    declare USER_PASSWORD="$(findInArgs '--password' $*)"

    declare KEYCLOAK_HOST_ARG="$(findInArgs '--host' $*)"
    [ "${KEYCLOAK_HOST_ARG}" == "" ] && KEYCLOAK_HOST_ARG=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST")

    declare KEYCLOAK_CLIENT_REALM_ARG="$(findInArgs '--realm' $*)"
    [ "${KEYCLOAK_CLIENT_REALM_ARG}" == "" ] && KEYCLOAK_CLIENT_REALM_ARG=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_CLIENT_REALM")
    declare KEYCLOAK_CLIENT_ID_ARG="$(findInArgs '--client-id' $*)"
    [ "${KEYCLOAK_CLIENT_ID_ARG}" == "" ] && KEYCLOAK_CLIENT_ID_ARG=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_CLIENT_ID")
    declare KEYCLOAK_CLIENT_SECRET_ARG="$(findInArgs '--client-secret' $*)"
    [ "${KEYCLOAK_CLIENT_SECRET_ARG}" == "" ] && KEYCLOAK_CLIENT_SECRET_ARG=$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_CLIENT_SECRET")
    
    getKeycloakToken $KEYCLOAK_HOST_ARG "$KEYCLOAK_CLIENT_REALM_ARG" "$USER_LOGIN" "$USER_PASSWORD" "$KEYCLOAK_CLIENT_ID_ARG" "$KEYCLOAK_CLIENT_SECRET_ARG" $TEMP_DIRECTORY/token || exit 1
   
    declare TOKEN=$(cat $TEMP_DIRECTORY/token)
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "TOKEN" "$TOKEN"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST" "$KEYCLOAK_HOST_ARG"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_CLIENT_REALM" "$KEYCLOAK_CLIENT_REALM_ARG"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_ID_ARG"
    writeEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_CLIENT_SECRET" "$KEYCLOAK_CLIENT_SECRET_ARG"
}
export -f kathraLogin