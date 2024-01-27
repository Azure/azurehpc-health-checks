#!/bin/bash

####
# @Brief        : GET ADO build info
# @Param        : ADO Auth token, build url
# @RetVal       : build json
####
get_builds_res () {
    builds_json=$(curl -s -H "Authorization: Bearer $SYSTEM_ACCESSTOKEN" $build_url)
    echo $builds_json
}

# Print GITHUB_PR_NUMBER env variable
echo "GITHUB_PR_NUMBER: $(GITHUB_PR_NUMBER)"

# Queue PR Pipeline
res_code=$(curl -s -w "%{response_code}\n" -o post.json -X POST "https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_apis/build/builds?api-version=7.2-preview.7" \
-H "Authorization: Bearer $SYSTEM_ACCESSTOKEN" -H "Content-Type: application/json" \
--data-raw "{\"definition\": {\"id\": 29}, \"sourceBranch\": \"master\", \"parameters\": \"{\\\"GITHUB_PR_NUMBER\\\": \\\"$(GITHUB_PR_NUMBER)\\\"}\"}")

if [ $res_code -ne 200 ]
then
    echo "Error! Could not queue build. Response code: $res_code"
    exit 1
fi

echo "Queued build!"

# Get URL for queued ADO build
post_build_res=$(cat ./post.json)
build_url=$(echo $post_build_res | jq -r "._links.self.href")
echo "Build url: $(echo $post_build_res | jq -r "._links.web.href")"

# Wait until build finishes
build_status=$(get_builds_res | jq -r ".status")

while [ "${build_status}" != "completed" ]
do
    build_status=$(get_builds_res | jq -r ".status")
  
    echo "Build status: ${build_status}"
    sleep 300
done

build_res=$(get_builds_res | jq -r ".result")
echo "Build result: ${build_res}"

# Throw an error if build fails
if [ "${build_res}" != "succeeded" ]
then
    echo "Error! Build failed..."
    exit 1
fi
