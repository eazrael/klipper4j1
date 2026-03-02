#!/bin/bash 
export LC_ALL=C
set -e 

KEEP_PARTITIONS="sbl1 sbl1bak aboot abootbak boot rpm rpmbak tzbak modemst1 modemst2 fsc ssd splash DDR fsg sec devinfo keystore oem config"


if [ $# -ne 4 ]; then 
    echo "Need exactly four parameters: create_image.sh backup_image klipper_image lk2nd_image target_image_name"
    exit 1
fi

source_image=${1}
klipper_image=${2}
lk2nd_image=${3}
target_image=${4}

if [ ! -f "${source_image}" ]; then 
    echo "Source image must exist" 
    exit 1
fi 

if [ ! -f "${klipper_image}" ];  then 
    echo "MainsailOS image must exist" 
    exit 1
fi 

if [ ! -f "${lk2nd_image}" ];  then 
    echo "LK2nd image must exist" 
    exit 1
fi 

if [ -e "${target_image}" ]; then 
    echo "Target image must not exist" 
    exit 1
fi

source_size=$(stat -c %s "${source_image}")
echo "Source image size is ${source_size} ($((source_size/1024/1024))MB)"
source_gpt=$(sfdisk -d "${source_image}")

source_partition_table=$(sed '1,/^$/d'  <<<"${source_gpt}" |tr -d ' ' |cut -d ':' -f2-)
echo "$source_partition_table" 

source_partition_header=$(sed '/^[[:space:]]*$/q' <<<${source_gpt})
sector_size=$(grep sector-size <<<$source_gpt | cut -d ':' -f 2- |tr -d ' ' )
echo Sector Size: "$sector_size"
echo Header:
echo "${source_partition_header}"


echo Reserving space for new image
fallocate -l ${source_size} "${target_image}"

function rewrite_partition()
{
    local partition_name=$1
    local partition_table=$2    
    while read name value 
    do 
        local $name=$value
    done  < <(grep "name=\"${partition_name}\"" <<<${partition_table} |tr ',' '\n' |tr '=' ' ')
    if [ -n "${attrs}" ] ; then 
        echo size=${size}, type=${type}, uuid=${uuid}, name=${partition_name}, attrs="${attrs}"
    else
        echo size=${size}, type=${type}, uuid=${uuid}, name=${partition_name}
    fi
}

function get_partition_number_by_name()
{
    local device=$1
    local name=$2

    sfdisk -l -o Name,Start,Sectors,Type-UUID,UUID,Attrs -q "${device}" |tr -s ' ' |tail -n +2 |grep -n "^${name} "  | cut -d: -f1
}

function get_start_sector_by_name()
{
    local device=$1
    local name=$2    
    #sfdisk -l -o Name,Start,Sectors,Type-UUID,UUID,Attrs -q "${device}" |tr -s ' ' |tail -n +2 |grep -n "^${name} "  
    read name start < <(sfdisk -l -o Name,Start -q  "${device}" |tr -s ' ' |tail -n +2 |grep "^${name} ")
    echo ${start}
}

function get_start_sector_by_number()
{
    local device=$1
    local number=$2    
    #sfdisk -l -o Name,Start,Sectors,Type-UUID,UUID,Attrs -q "${device}" |tr -s ' ' |tail -n +2 |grep -n "^${name} "  
    sfdisk -l -o Start -q  "${device}" | sed -n "$((number+1))p" |tr -d ' '
}

function get_size_by_name()
{
    local device=$1
    local name=$2    
    #sfdisk -l -o Name,Start,Sectors,Type-UUID,UUID,Attrs -q "${device}" |tr -s ' ' |tail -n +2 |grep -n "^${name} " 
    read name sectors < <(sfdisk -l -o Name,Sectors -q  "${device}" |tr -s ' ' |tail -n +2 |grep "^${name} ")
    echo ${sectors}
}

function get_size_by_number()
{
    local device=$1
    local number=$2    
    #sfdisk -l -o Name,Start,Sectors,Type-UUID,UUID,Attrs -q "${device}" |tr -s ' ' |tail -n +2 |grep -n "^${name} "  
    sfdisk -l -o Sectors -q  "${device}" | sed -n "$((number+1))p" |tr -d ' '
}
function get_size_by_number()
{
    local device=$1
    local number=$2    
    #sfdisk -l -o Name,Start,Sectors,Type-UUID,UUID,Attrs -q "${device}" |tr -s ' ' |tail -n +2 |grep -n "^${name} "  
    sfdisk -l -o Sectors -q  "${device}" | sed -n "$((number+1))p" |tr -d ' '
}

function clone_partition()
{
    local source_device=$1
    local target_device=$2
    local name=$3
    local sector_size=$4

    local source_start=$(get_start_sector_by_name "${source_device}" "${name}")
    local target_start=$(get_start_sector_by_name "${target_device}" "${name}")
    local source_size=$(get_size_by_name "${source_device}" "${name}")

    dd if="${source_device}" of="${target_device}"  skip=${source_start} seek=${target_start} bs=${sector_size} count=${source_size} conv=sparse,notrunc
}

clone_from_armbian_image()
{
    local source_device=$1
    local target_device=$2
    local source_number=$3
    local target_name=$4
    local sector_size=$5

    local source_start=$(get_start_sector_by_number "${source_device}" "${source_number}")
    local target_start=$(get_start_sector_by_name "${target_device}" "${target_name}")
    local source_size=$(get_size_by_number "${source_device}" "${source_number}")

    dd if="${source_device}" of="${target_device}"  skip=${source_start} seek=${target_start} bs=${sector_size} count=${source_size} conv=sparse,notrunc status=progress
}

function extract_firmware() 
{
    local source_image=${1}
    local fw_tempdir=$(mktemp -d)
    mkdir -p "${fw_tempdir}/usr/lib/firmware/wlan/prima"

    local mount_tempdir=$(mktemp -d)
    local loop_device=$(losetup -f)
    losetup -P -r "${loop_device}" "${source_image}"

    local modem_partition=$(get_partition_number_by_name "${source_image}" "modem") 
    mount -o ro "${loop_device}p${modem_partition}" "${mount_tempdir}"
    cp "${mount_tempdir}"/image/wcnss.* "${fw_tempdir}/usr/lib/firmware/"
    umount "${mount_tempdir}"

    local persist_partition=$(get_partition_number_by_name "${source_image}" "persist")
    mount -o ro,noload "${loop_device}p${persist_partition}" "${mount_tempdir}"
    cp "${mount_tempdir}"/WCNSS* "${fw_tempdir}/usr/lib/firmware/wlan/prima/"
    umount "${mount_tempdir}"

    losetup -d "${loop_device}"

    # show what we found 
    local tarfile=$(readlink -f firmware.tar)
    ( cd "${fw_tempdir}" &&   tar -cvf "${tarfile}" * )
}

function inject_firmware()
{
    local target_image=${1}

    local mount_tempdir=$(mktemp -d)
    local loop_device=$(losetup -f)
    local tarfile=$(readlink -f firmware.tar)


    losetup -P  "${loop_device}" "${target_image}"

    local root_partition=$(get_partition_number_by_name "${target_image}" "linux_root") 
    mount -o rw "${loop_device}p${root_partition}" "${mount_tempdir}"
    (cd "${mount_tempdir}" && tar -xf "${tarfile}" ) 
    
    # trimming fails randomly, no idea why
    # and it is not always supported on loopback
    fstrim -v "${mount_tempdir}" 2>/dev/null || true
    umount "${mount_tempdir}"

    losetup -d "${loop_device}"
}

extract_firmware "${source_image}"


#echo "$source_partition_header"
new_partitions=""
for partition in ${KEEP_PARTITIONS}
do
    new_partitions="${new_partitions}\n"$(rewrite_partition "${partition}" "${source_partition_table}")
done 
#add a boot & root partition
new_partitions=${new_partitions}"\ntype=linux, name=linux_boot, size=128MiB"
new_partitions=${new_partitions}"\ntype=linux, name=linux_root"
#execute
sfdisk "${target_image}" < <(echo -e "${source_partition_header}\n${new_partitions}")

# copy essential partitions to the target image
for partition in ${KEEP_PARTITIONS}
do
    clone_partition "${source_image}" "${target_image}" "${partition}" ${sector_size}
done 

boot_start=$(get_start_sector_by_name "${target_image}" boot)
linux_boot_start=$(get_start_sector_by_name "${target_image}" linux_boot)
linux_root_start=$(get_start_sector_by_name "${target_image}" linux_root)

# TODO safety check target partition sizes and image availabilty
echo Boot Start $boot_start 
echo Linux_Boot Start $linux_boot_start 
echo Linux_Root Start $linux_root_start 

dd if="${lk2nd_image}" of="${target_image}" seek=$boot_start conv=notrunc status=progress
clone_from_armbian_image "${klipper_image}" "${target_image}" 1 linux_boot 512
clone_from_armbian_image "${klipper_image}" "${target_image}" 2 linux_root 512

inject_firmware "${target_image}"

echo 
echo 
echo "New image ${target_image} created. Check output for errors"
exit 0
