#!/bin/bash
##################################################################
## KATHRA CLI
## @author Julien Boubechtoula
## 
##################################################################
export SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export TEMP_DIRECTORY=/tmp/kathra-cli/
export KATHRA_CONTEXT_FILE=$HOME/.kathra-context
export VERSION="1.0.0-RC-SNAPSHOT"
[ ! -d $TEMP_DIRECTORY ] && mkdir $TEMP_DIRECTORY

. $SCRIPT_DIRECTORY/func/imports.sh

printDebug "Context file: $KATHRA_CONTEXT_FILE"

export resourceTypesExistings=( components apiversions implementations librairies pipelines sourcerepositories groups keypairs implementationversions )

function show_help() {
    printInfo "KATHRA CLI"
    printInfo "version: $VERSION"
    printInfo ""
    printInfo "Usage: "
    printInfo "--version"
    printInfo ""
    printInfo "login --username=<login> --password=<password> --host=<default:$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST")>  : Get a token"
    
    printInfo ""
    printInfo "create components <swagger-file> <name> <team's name> <description>                               : add a new component with apiversion from swagger file"
    printInfo "import components <filePath>                                                                      : import component from file"
    printInfo ""
    printInfo "create implementations <name> <version> <component> <api-version> <language> <description>        : create new implementation"
    
    printInfo ""
    printInfo "get <resource-type>                                  : list resources"
    printInfo "get <resource-type> <uuid>                           : list all with details"
    printInfo "patch <resource-type> <uuid> <json>                  : patch resource"
    printInfo "delete <resource-type> <uuid>                        : delete resource"

    printInfo ""
    printInfo "Resource types :"
    for object in "${resourceTypesExistings[@]}"
    do
        printInfo "- $object"
    done

    return 0
}

findInArgs '--help' $* > /dev/null && show_help && exit 0
findInArgs '-h' $* > /dev/null && show_help && exit 0

. $SCRIPT_DIRECTORY/conf.sh

declare verb=$1
declare resourceType=$2
declare identifier=$3
declare extra=$4

function resolvIfIdentifierIsNameOrUUID() {
    local resourceType=$1
    local identifier=$2
    if [[ ${identifier//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        echo $identifier
    else
        callResourceManager "GET" "${resourceType}" | jq ".[] | select(.name==\"${identifier}\")" > ${TEMP_DIRECTORY}.resolvIfIdentifierIsNameOrUUID
        [ "$(jq -r '.id' < ${TEMP_DIRECTORY}.resolvIfIdentifierIsNameOrUUID)" == "" ] && printError "Unable to find resource ${resourceType} with name '$identifier'" && return 1
        echo "$(jq -r '.id' < ${TEMP_DIRECTORY}.resolvIfIdentifierIsNameOrUUID)"
    fi
    return 0
}

function getTypeResourceFromAlias() {
    local type=$1
    local -A aliasTR;
    aliasTR[c]="components";
    aliasTR[com]="components";
    aliasTR[component]="components";
    aliasTR[a]="apiversions";
    aliasTR[api]="apiversions";
    aliasTR[apiversion]="apiversions";
    aliasTR[i]="implementations";
    aliasTR[imp]="implementations";
    aliasTR[implementations]="implementations";
    declare search=$(echo ${aliasTR[${type}]:-MISSING})
    [ "$search" == "MISSING" ] && return 1
    echo $search && return 0
}

[[ ! " ${resourceTypesExistings[@]} " =~ " ${resourceType} " ]] && resourceType=$(getTypeResourceFromAlias ${resourceType})
[ "$resourceType" == "" ] && printError "Unable to find type of resource, use help" && exit

case "${verb}" in
    create)   
        case "${resourceType}" in
            implementations)   
                kathraCreateImplementation "$3" "$4" "$5" "$6" "$7" "$8"
            ;;
            components)   
                kathraCreateComponent "$3" "$4" "$5" "$6"
            ;;
        esac  
    ;;
    get)   
    
        declare propertiesToDisplay=(name id status)
        declare propertiesToDisplayFilter=$(echo ${propertiesToDisplay[*]} | tr ' ' '\n' | sed 's#\(.*\)#\1: .\1#g' | tr '\n' ',')

        [ "${identifier}" == "" ] && callResourceManager "GET" "${resourceType}" | jq -r ".[] | {${propertiesToDisplayFilter}}" && exit 0
        declare uuid=$(resolvIfIdentifierIsNameOrUUID "${resourceType}" "$identifier")
        [ "$uuid" == "" ] && exit 1
        callResourceManager "GET" "${resourceType}/${uuid}" | jq '.' && exit 0
    ;;
    delete)   
        declare uuid=$(resolvIfIdentifierIsNameOrUUID "${resourceType}" "$identifier")
        [ "$uuid" == "" ] && exit 1
        case "${resourceType}" in
            components)   
                callResourceManager "DELETE" "${resourceType}/${uuid}" | jq '.' && exit 0
            ;;
            implementations)   
                callResourceManager "DELETE" "${resourceType}/${uuid}" | jq '.' && exit 0
            ;;
        esac  
    ;;
    patch)   
        declare uuid=$(resolvIfIdentifierIsNameOrUUID "${resourceType}" "$identifier")
        [ "$uuid" == "" ] && exit 1
        callResourceManager "PATCH" "${resourceType}/${uuid}" "${extra}" | jq
    ;;
    import) 
        case "${resourceType}" in
            components)   
                kathraImportExistingComponent "${identifier}"
            ;;
        esac   
    ;;
    *)
        show_help   
    ;;
esac   

exit $?