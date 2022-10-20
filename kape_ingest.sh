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
webHookUri="https://your.teams.webhook.url/"

RED="ff0000"
GREEN="00ff00"
BLUE="0000ff"
ORANGE="ff8c00"

# check for new uploads in /sftp/upload
uploadDir=/sftp/upload
filesList=()

shopt -s nullglob

for fileFound in $(basename -a $uploadDir/*); do

    echo " [*] Found file: \"$fileFound\""

    # create working folders and move artifacts
    HOSTNAME=$(echo -n "$fileFound" | awk -F '_' '{print $(NF-1)}')
    CollectionDate=$(echo -n "$fileFound" | awk -F '_' '{print $NF}')
    fourteenDays=$(python3 -c "import datetime;\
                   collection_date=datetime.datetime.strptime('$CollectionDate','%Y%m%d%H%M%S');\
                   analysis_date=collection_date + datetime.timedelta(days=-14);\
                   print(analysis_date.isoformat());")
    HOSTROOT="/cases/$HOSTNAME"
    [[ -e "/cases/$HOSTNAME" ]] || mkdir -p "$HOSTROOT"
    mkdir -p "$HOSTROOT/"{artifacts/base,plaso/logs,chainsaw}
    rm -rf $HOSTROOT/artifacts/base/*
    mv "$uploadDir/$fileFound" "$HOSTROOT/"
    cd "$HOSTROOT"

    # extract KAPE artifacts - root folder should be
    # the OS drive letter
    kape_src_archive=$(ls -1 "$fileFound"/*.zip)
    7z x '-x!*.csv' "-pinfected" "-oartifacts/base" "$kape_src_archive"

    # check if the kape collection encountered any "Long File Names"
    # during collection. if so, restore them to the original path
    # while preserving timestamps
    for LongFile in ./artifacts/base/LongFileNames/*OriginalPathInfo.txt; do
        ORIGINAL_PATH=artifacts/base/$(cat $LongFile | tr '\' '/' 2>/dev/null)
        rm $LongFile
        FILE_ID=$(basename $LongFile | awk -F '_' '{print $1}')
        rsync -a --remove-source-files --mkpath artifacts/base/LongFileNames/${FILE_ID}* "${ORIGINAL_PATH}"
    done

    rm -rf artifacts/base/LongFileNames

    # set the drive letter (should be "C", but may not be)
    drive_letter=$(ls -1 artifacts/base)

    # run chainsaw; output to csv
    if [[ -e artifacts/base/$drive_letter/Windows/System32/winevt/logs ]]; then
        chainsaw hunt \
        artifacts/base/$drive_letter/Windows/System32/winevt/logs/ \
        --full --csv -o chainsaw \
        -s /opt/chainsaw/sigma/rules/ \
        --mapping /opt/chainsaw/mappings/sigma-event-logs-all.yml
    fi

    # move large files to a new sub-folder to process separately
    pushd artifacts/base >/dev/null
    find $drive_letter/ -type f ! -name '$MFT' -size +1G | grep . >/dev/null && LARGE_FILES=1
    if [[ $LARGE_FILES ]]; then
        mkdir ../large_files
        rsync -av --remove-source-files --prune-empty-dirs --files-from <(find . -type f ! -name '$MFT' -size +1G) . ../large_files
    fi
    popd >/dev/null

    # start a new tmux session for this HOSTNAME
    SESSION=${HOSTNAME,,}
    tmux new -s $SESSION -d

    command=""

    for artifact_path in artifacts/*; do

        art_type=$(basename $artifact_path)

        # run plaso log2timeline
        command+=$(cat << EOF
docker run -ti --rm -v $PWD/$artifact_path:/artifacts \
-v $PWD/plaso:/plaso log2timeline/plaso:20220428 log2timeline.py \
-z UTC --hashers md5 \
--logfile /plaso/logs/${HOSTNAME}_${art_type}_log2timeline.gz \
--storage_file /plaso/${HOSTNAME}_${art_type}.plaso \
/artifacts/$drive_letter; \
docker run -ti --rm --network host \
-v $PWD/plaso:/plaso log2timeline/plaso:20220428 psort.py \
--analysis tagging \
--tagging_file tag_windows.txt \
-o elastic \
--elastic-mappings /usr/share/plaso/elasticsearch.mappings \
--index_name kape-${HOSTNAME,,} \
--server 127.0.0.1 --port 9200 \
--logfile /plaso/logs/${HOSTNAME}_${art_type}_psort.gz \
/plaso/${HOSTNAME}_${art_type}.plaso \
'datetime > DATETIME("$fourteenDays")'; \
docker run -ti --rm -v $PWD/plaso:/plaso \
log2timeline/plaso:20220428 pinfo.py /plaso/${HOSTNAME}_${art_type}.plaso \
>> plaso/${HOSTNAME}_PLASO_INFO.txt;
EOF
        )
    done
    command+=$(printf " exit")
    printf "\nStarting plaso processing in tmux session: $SESSION\n\n"
    tmux send-keys -t $SESSION "$command" Enter

    teams_chat_post $webHookUri "KAPE Ingest Started" "$BLUE" \
    "KAPE ingest started for host:<br><br>${HOSTNAME}"
done