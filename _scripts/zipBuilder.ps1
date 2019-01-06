#####################################################
## This script automatically zips up files for Lambda
#####################################################

## Check for Docker Installation
$docker_version = (docker -v)
if (!$docker_version) {
    Write-Host "Docker is not Installed. Quiting";
    exit
} 
Write-Output $docker_version

## Create Temp Directory for Docker Copy
New-Item -Name temp.lambda -ItemType directory | Out-Null

## Get Docker Image if it's not downloaded
$docker_image = (docker images -q node:8.11)
if(!$docker_image) {
    Write-Output ("This Script requires the Node:8.10 image, but it is not installed.")
    Write-Output "Attempting to Download..."
    docker pull node:8.10
}
## Copy Node Files to Temp Directory
Copy-Item .\index.js -Destination temp.lambda
Copy-Item .\package.json -Destination temp.lambda

## Run Docker Container to Install Dependencies
Write-Output "Installing Dependencies"
(docker run -t --name lambda_build --rm -v $PWD/temp.lambda:/venv -w /venv node:8.10 npm install --silent | Out-Null)

## Zip Directory
Write-Output 'Zipping up Contents'
$directory = (Get-Item $PWD).Name
Compress-Archive .\temp.lambda\* -DestinationPath $directory

## Cleanup Temp
Write-Output "Cleaning up Temp Directory"
Remove-Item temp.lambda -Force -Recurse