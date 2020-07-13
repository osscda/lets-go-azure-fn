#!/usr/bin/env bash
set -euo pipefail

# variables
RESOURCE_GROUP='200300-hello-gopher-win'
LOCATION='eastus'
SUBSCRIPTION_ID=$(az account show | jq -r .id)
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
# RANDOM_STR='2b7222'
RANDOM_STR=$(echo -n "$SCOPE" | shasum | head -c 6)
STORAGE_NAME="storage${RANDOM_STR}"
FUNCTION_NAME="functions${RANDOM_STR}"
CREATE_IF_EXISTS="false"
# set by actions workflow
[[ -z "${GITHUB_SHA:-}" ]] && GITHUB_SHA='test'

echo "RANDOM_STR: ${RANDOM_STR}"

TMP=$(az storage account list -g $RESOURCE_GROUP | jq '[.[].name | index("'$STORAGE_NAME'")] | length')

if [[ "$TMP" == "0" || $CREATE_IF_EXISTS == "true" ]]; then
    echo "az storage account create..."
    az storage account create -g $RESOURCE_GROUP -l $LOCATION -n $STORAGE_NAME \
        --kind StorageV2 \
        --sku Standard_LRS \
        > /dev/null
else
    echo "storage exists..."
fi

TMP=$(az functionapp list -g $RESOURCE_GROUP | jq '[.[].name | index("'$FUNCTION_NAME'")] | length')

if [[ "$TMP" == "0" || $CREATE_IF_EXISTS == "true" ]]; then
    echo "az functionapp create..."
    az functionapp create -g $RESOURCE_GROUP -s $STORAGE_NAME -n $FUNCTION_NAME \
        --consumption-plan-location $LOCATION \
        --os-type Windows \
        --runtime dotnet \
        > /dev/null

    echo "az functionapp appsettings..."
    az functionapp config appsettings set -g $RESOURCE_GROUP -n $FUNCTION_NAME --settings \
        "FUNCTIONS_EXTENSION_VERSION=~3" \
        > /dev/null
else
    echo "functionapp exists..."
fi

echo "az functionapp appsettings (SERVER_NAME)..."
az functionapp config appsettings set -g $RESOURCE_GROUP -n $FUNCTION_NAME --settings \
    "SERVER_NAME=hello-gopher-${GITHUB_SHA}" \
    > /dev/null

echo "build binary..."
source build-container-windows.sh

echo "deploy function..."
cp host.windows.json host.json
source deploy-storage.sh

echo "curl https://${FUNCTION_NAME}.azurewebsites.net/api/healthz"
curl -s -w '\ntime_starttransfer: %{time_starttransfer}\n' "https://${FUNCTION_NAME}.azurewebsites.net/api/healthz"
