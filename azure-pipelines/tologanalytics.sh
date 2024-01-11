#!/bin/bash

workspace_id="${LOG_CONTAINER_ID}"
logName=$1
echo "##[debug]Log Analytics Container name: $logName"
key="${LOG_CONTAINER_KEY}"

jsonFile=$2

if [ ! -s $jsonFile ]
then
	echo "JSON file $jsonFile not found"
	exit 1
fi

echo "##[section]uploading $jsonFile to Azure Log Analytics workspace $workspace_id"

content=$(cat $jsonFile | iconv -t utf8)
echo "##[debug]$content"
content_len=${#content}
rfc1123date="$(date -u +%a,\ %d\ %b\ %Y\ %H:%M:%S\ GMT)"
string_to_hash="POST\n${content_len}\napplication/json\nx-ms-date:${rfc1123date}\n/api/logs"
utf8_to_hash=$(echo -n "$string_to_hash" | iconv -t utf8)
decoded_hex_key="$(echo "$key" | base64 --decode --wrap=0 | xxd -p -c256)"
signature="$(echo -ne "$utf8_to_hash" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$decoded_hex_key" -binary | base64 --wrap=0)"
auth_token="SharedKey $workspace_id:$signature"

curl -s -S \
	-H "Content-Type: application/json" \
	-H "Log-Type: ${logName//-/_}" \
	-H "Authorization: $auth_token" \
	-H "x-ms-date: $rfc1123date" \
	-X POST \
	--data "$content" \
	https://$workspace_id.ods.opinsights.azure.com/api/logs?api-version=2016-04-01
