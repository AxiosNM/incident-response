#!/bin/bash

function teams_chat_post () {
    # =============================================================================
    #  Author: Chu-Siang Lai / chusiang (at) drx.tw
    #  Filename: teams-chat-post.sh
    #  Modified: 2018-03-28 15:04
    #  Description: Post a message to Microsoft Teams.
    #  Reference:
    #
    #   - https://gist.github.com/chusiang/895f6406fbf9285c58ad0a3ace13d025
    #
    # =============================================================================

    # Help.
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo 'Usage: teams-chat-post.sh "<webhook_url>" "<title>" "<color>" "<message>"'
        exit 0
    fi

    # Webhook or Token.
    WEBHOOK_URL=$1
    if [[ "${WEBHOOK_URL}" == "" ]]
    then
        echo "No webhook_url specified."
        exit 1
    fi
    shift

    # Title .
    TITLE=$1
    if [[ "${TITLE}" == "" ]]
    then
        echo "No title specified."
        exit 1
    fi
    shift

    # Color.
    COLOR=$1
    if [[ "${COLOR}" == "" ]]
    then
        echo "No status specified."
        exit 1
    fi
    shift

    # Text.
    TEXT=$*
    if [[ "${TEXT}" == "" ]]
    then
        echo "No text specified."
        exit 1
    fi

    # Convert formating.
    MESSAGE=$( echo ${TEXT} | sed 's/"/\"/g' | sed "s/'/\'/g" )
    JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"${MESSAGE}\" }"

    # Post to Microsoft Teams.
    curl -H "Content-Type: application/json" -d "${JSON}" "${WEBHOOK_URL}"
}

# constants:
webHookUri="https://your.teams.webhook.url"
TITLE="File(s) uploaded to Skadi SFTP"
COLOR="00ff00"  #green

tempUploadDir=/sftp/sftpuser/upload/*
uploadDir=/sftp/upload

# loop:
#    go through each file found in the directory /sftp/sftpuser/upload
#    add it to the files list array and move it to the directory /sftp/upload
#    post a message with the files list to teams

filesList=()

shopt -s nullglob

for fileFound in $tempUploadDir; do

    echo " [*] Found file: \"$fileFound\""

    # check to make sure the file isn't open; wait until it's closed
    while :
    do
        if ! [[ `lsof -c sshd | grep "$fileFound"` ]]
        then
            break
        fi
        sleep 1
    done

    echo " --> moving file \"$fileFound\" to \"$uploadDir\" and adding to files list"
    mv "$fileFound" $uploadDir/ && filesList+=( "$fileFound" )

done

if [[ ! -z "$filesList" ]]; then
    printf "\n [!] Posting message to Teams\n"
    filesString=$(for ((i = 0; i < ${#filesList[@]}; i++)); do echo "-->  ${filesList[$i]}<br>"  ; done)
    MESSAGE=$'The following files were uploaded to the SFTP server and moved out of chroot:<br><br>'
    MESSAGE+="$filesString"
    teams_chat_post "$webHookUri" "$TITLE" "$COLOR" "$MESSAGE"
fi
