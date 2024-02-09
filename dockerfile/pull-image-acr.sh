#!/bin/bash

DOCK_IMG_NAME="aznhc.azurecr.io/nvidia-rt"
REPO_USERNAME="az-nhc-tok"
vaultName="aznhc-kv"
secretName="az-nhc-tok"
resourceGroupName="azure-nhc-resources"
managedIdentityID="335a45e3-ba51-4c7a-b3f7-2e109f488cee"
subscriptionId="75c5e023-db83-4675-8531-fd0150c82176"

az login --identity -u "$managedIdentityID"
az account set --subscription "$subscriptionId"

secretValue=$(az keyvault secret show --vault-name "$vaultName" --name "$secretName" --query "value" --output tsv)
echo $secretValue
sudo docker login aznhc.azurecr.io --password $secretValue --username $REPO_USERNAME 

sudo docker pull $DOCK_IMG_NAME
