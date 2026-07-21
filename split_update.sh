#!/bin/bash
export LC_ALL=C
set -e

if [ $# -ne 3 ]; then
    echo "Need exactly three parameters: split_update.sh mainsailos_image linux_boot_image linux_root_image"
    exit 1
fi

source_image=${1}
linux_boot_image=${2}
linux_root_image=${3}

if [ ! -f "${source_image}" ];  then
    echo "MainsailOS image must exist"
    exit 1
fi

if [ -e "${linux_boot_image}" ]; then
    echo "linux_boot image must not exist"
    exit 1
fi

if [ -e "${linux_root_image}" ]; then
    echo "linux_root image must not exist"
    exit 1
fi

function get_start_sector_by_number()
{
    local device=$1
    local number=$2
    sfdisk -l -o Start -q  "${device}" | sed -n "$((number+1))p" |tr -d ' '
}

function get_size_by_number()
{
    local device=$1
    local number=$2
    sfdisk -l -o Sectors -q  "${device}" | sed -n "$((number+1))p" |tr -d ' '
}

function extract_partition()
{
    local source_device=$1
    local target_image=$2
    local source_number=$3
    local sector_size=$4

    local source_start=$(get_start_sector_by_number "${source_device}" "${source_number}")
    local source_size=$(get_size_by_number "${source_device}" "${source_number}")

    dd if="${source_device}" of="${target_image}" skip=${source_start} bs=${sector_size} count=${source_size} conv=sparse status=progress
}

extract_partition "${source_image}" "${linux_boot_image}" 1 512
extract_partition "${source_image}" "${linux_root_image}" 2 512

echo
echo
echo "Images ${linux_boot_image} and ${linux_root_image} extracted. Check output for errors"
exit 0
