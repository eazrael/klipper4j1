#!/bin/bash
set -ex
SRC_DIR=$(dirname "$(readlink -f ""${BASH_SOURCE}"")")
BUILD_DIR=$(readlink -f "$(pwd)")

LK2ND_REPO="https://github.com/eazrael/lk2nd.git"
LK2ND_TAG="f4cb316c8e0c0c0b245399132a44866a63566062"
LK2ND_PATCH="${SRC_DIR}/patches/lk2nd.patch"

ARMBIAN_REPO="https://github.com/eazrael/armbian-build.git"
ARMBIAN_TAG="snapmakerj1"
ARMBIAN_PATCH="${SRC_DIR}/patches/armbian.patch"

MAINSAILOS_REPO="https://github.com/mainsail-crew/MainsailOS.git"
MAINSAILOS_TAG="6e5bb4c3e9c5a8b022a3ecade586dab3070fdd6a"
MAINSAILOS_PATCH="${SRC_DIR}/patches/mainsailos.patch"
#workaround for pull requests
MAINSAILOS_PR=351

function build_lk2nd()
{
    git clone "${LK2ND_REPO}" lk2nd
    cd lk2nd
    git checkout "${LK2ND_TAG}"

    if [ -f "${LK2ND_PATCH}" ] ; then 
        git apply --whitespace=fix "${LK2ND_PATCH}"
    fi 

    MAKEFLAGS=-j$(nproc) make BOOTLOADER_OUT=snapmakerj1 TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8909
    MAKEFLAGS=-j$(nproc) make BOOTLOADER_OUT=snapmakerj1-fastboot TOOLCHAIN_PREFIX=arm-none-eabi- LK2ND_FORCE_FASTBOOT=1 LK2ND_FASTBOOT_DEBUG=2 DELAY=300000  lk2nd-msm8909 
    ln snapmakerj1/*/lk2nd.img "${BUILD_DIR}/lk2nd.img" || cp --reflink=auto snapmakerj1/*/lk2nd.img "${BUILD_DIR}/lk2nd.img"
    ln snapmakerj1-fastboot/*/lk2nd.img "${BUILD_DIR}/lk2nd-fastboot.img" || cp --reflink=auto snapmakerj1-fastboot/*/lk2nd.img "${BUILD_DIR}/lk2nd-fastboot.img"
    
    # no idea where this comes from
    rm -f "${BUILD_DIR}/emmc_appsboot.mbn" || true
}

function build_armbian()
{
    git clone "${ARMBIAN_REPO}" armbian
    cd armbian 
    git checkout "${ARMBIAN_TAG}" 
    
    if [ -f "${ARMBIAN_PATCH}" ] ; then 
        git apply --whitespace=fix "${ARMBIAN_PATCH}"
    fi 
    
    time MAKEFLAGS=-j$(nproc) ./compile.sh BOARD=snapmaker-j1  KERNEL_CONFIGURE=no
    ln output/images/*.img "${BUILD_DIR}/armbian.img" ||  cp --reflink=auto output/images/*.img "${BUILD_DIR}/armbian.img"
}

function build_mainsailos() 
{
    git clone "${MAINSAILOS_REPO}" mainsailos
    cd mainsailos 
    
    if [ -n "${MAINSAILOS_PR}" ]; then 
         git fetch origin "pull/"${MAINSAILOS_PR}"/head:pr${MAINSAILOS_PR}"
    fi
    git checkout "${MAINSAILOS_TAG}" 
    
    if [ -f "${MAINSAILOS_PATCH}" ]; then
        git apply --whitespace=fix "${MAINSAILOS_PATCH}"
    fi 

    ln "${BUILD_DIR}/armbian.img" ||  cp --reflink=auto "${BUILD_DIR}/armbian.img" .

    time bash build.sh 
    ln build_*/output.img "${BUILD_DIR}/mainsailos.img" ||  cp --reflink=autobuild_*/output.img "${BUILD_DIR}/armbian.img"
}

if [ -n "$(ls -A .)" ] ; then
    echo Current directory must be empty 1>&2
    exit 1
fi


(build_lk2nd)
(build_armbian)
(build_mainsailos)

