
#!/bin/bash

function getKeycloakToken() {
    local host=$1
    local realm=$2
    local username=$3
    local password=$4
    local clientId=$5
    local clientSecret=$6
    local out=$7
    local url="https://$host/auth/realms/$realm/protocol/openid-connect/token"
    printDebug "getKeycloakToken -> get access token from $url with user '$username' and client '$clientId'"
    curl -v -d "client_id=$clientId" -d "username=$username" -d "password=$password" -d "grant_type=password" -d "client_secret=$clientSecret" "$url" > $TEMP_DIRECTORY/getKeycloakToken.token 2> $TEMP_DIRECTORY/getKeycloakToken.token.err
    [ $? -ne 0 ] && printError "Unable to get token" && exit 1
    local access_token=$(grep "access_token" < $TEMP_DIRECTORY/getKeycloakToken.token | sed 's/.*\"access_token\":\"\([^\"]*\)\".*/\1/g')
    printDebug "ACCESS TOKEN IS \"$access_token\"";
    echo $access_token > $out
    [ "$access_token" == "" ] && printError "Unable to get token" && return 1
    return 0
}

export -f getKeycloakToken

function checkKeycloakTokenIsValid() {
    local KC_SERVER=$1
    local KC_REALM=$2
    local KC_CLIENT=$3
    local KC_CLIENT_SECRET=$4
    local KC_ACCESS_TOKEN=$5
    local KC_CONTEXT=auth

    printDebug "checkKeycloakTokenIsValid($*)"

    curl -k --fail -X POST -u "$KC_CLIENT:$KC_CLIENT_SECRET" -d "token=$KC_ACCESS_TOKEN" "https://$KC_SERVER/$KC_CONTEXT/realms/$KC_REALM/protocol/openid-connect/token/introspect" 2> /dev/null > $TEMP_DIRECTORY/checkKeycloakTokenIsValid || return 1
    [ "$(jq -r '.active' $TEMP_DIRECTORY/checkKeycloakTokenIsValid)" == "false" ] && return 1
    return 0
}
export -f checkKeycloakTokenIsValid