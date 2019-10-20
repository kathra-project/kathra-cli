#!/bin/bash
##################################################################
## KATHRA CLI
## @author Julien Boubechtoula
## 
##################################################################
export SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export TEMP_DIRECTORY=/tmp/kathra-cli/
export KATHRA_CONTEXT_FILE=$HOME/.kathra-context
[ ! -d $TEMP_DIRECTORY ] && mkdir $TEMP_DIRECTORY

. $SCRIPT_DIRECTORY/func/imports.sh

printDebug "Context file: $KATHRA_CONTEXT_FILE"

function show_help() {
    printInfo "login --username=<login> --password=<password> --host=<default:$(readEntryIntoFile "$KATHRA_CONTEXT_FILE" "KEYCLOAK_HOST")>"
    printInfo "get components : list components"
    printInfo "get components <uuid> : list resource with details"
    printInfo "create components <swagger-filePath> <component's name> <team's name> <component's description> : add a new component with apiversion from swagger file"
    printInfo "delete components <uuid> : delete component by uuid [--purge : delete pipelines and sourcerepositories into Jenkins and GitLab]"
    printInfo "import components <filePath> : import component from file"
    printInfo "patch components <uuid> <json> : patch resource"
    printInfo "create implementations <implementation's name> <implementation's version> <component's name or UUID> <component's version> <implementation's language> <implementation's description> : create new implementation"
    objects=( apiversions implementations librairies pipelines sourcerepositories users groups keypairs implementationversions )
    for object in "${objects[@]}"
    do
        printInfo "get $object : list $object"
        printInfo "get $object <uuid> : list all with details"
        printInfo "patch $object <uuid> <json> : patch resource"
        
    done
    return 0
}

findInArgs '--help' $* > /dev/null && show_help && exit 0
findInArgs '-h' $* > /dev/null && show_help && exit 0

. $SCRIPT_DIRECTORY/conf.sh

declare verb=$1
declare resourceType=$2
declare uuid=$3
declare extra=$4


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
        [ "${uuid}" == "" ] && callResourceManager "GET" "${resourceType}" | jq -r ".[] | {${propertiesToDisplayFilter}}" && exit 0
        [ ! "${uuid}" == "" ] && callResourceManager "GET" "${resourceType}/${uuid}" | jq '.' && exit 0
    ;;
    delete)   
        case "${resourceType}" in
            components)   
                declare purge=0
                findInArgs "--purge" $* 2> /dev/null > /dev/null && purge=1 || purge=0
                kathraDeleteComponent "${uuid}" $purge
            ;;
            implementations)   
                declare purge=0
                findInArgs "--purge" $* 2> /dev/null > /dev/null && purge=1 || purge=0
                kathraDeleteImplementation "${uuid}" $purge
            ;;
        esac  
    ;;
    patch)   
        callResourceManager "PATCH" "${resourceType}/${uuid}" "${extra}" | jq
    ;;
    import) 
        case "${resourceType}" in
            components)   
                kathraImportExistingComponent "${uuid}"
            ;;
        esac   
    ;;
    *)
        show_help   
    ;;
esac   

exit $?