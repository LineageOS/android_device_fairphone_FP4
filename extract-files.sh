#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=FP4
VENDOR=fairphone

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_FIRMWARE=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        system_ext/lib/libwfdservice.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed "android.media.audio.common.types-V2-cpp.so" "android.media.audio.common.types-V3-cpp.so" "${2}"
            ;;
        system_ext/lib64/libwfdnative.so)
            [ "$2" = "" ] && return 0
            sed -i "s/android.hidl.base@1.0.so/libhidlbase.so\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00/" "${2}"
            ;;
        vendor/etc/libnfc-hal-st.conf)
            [ "$2" = "" ] && return 0
            sed -i 's|STNFC_HAL_LOGLEVEL=.*|STNFC_HAL_LOGLEVEL=0x12|g' "${2}"
            ;;
        vendor/lib64/libmorpho_movie_stabilizer6.so)
            [ "$2" = "" ] && return 0
            grep -q libutils.so "${2}" || "${PATCHELF}" --add-needed "libutils.so" "${2}"
            ;;
        vendor/lib64/vendor.fpsensor.hardware.fpsensorhidlsvc@2.0.so)
            [ "$2" = "" ] && return 0
            grep -q libhidlbase_shim.so "{$2}" || "${PATCHELF}" --add-needed "libhidlbase_shim.so" "${2}"
            ;;
        vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.bitra.so)
            [ "$2" = "" ] && return 0
            "${SIGSCAN}" -p "13 0a 00 94" -P "1F 20 03 D5" -f "${2}"
            ;;
        vendor/lib64/hw/fingerprint.lito.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF_0_17_2}" --set-soname fingerprint.lito.so "${2}"
            sed -i 's|fpsensor_fingerprint\x00|fingerprint\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00|g' "${2}"
            sed -i 's|persist.dev.fp_log_level|persist.odm.fp_log_level|g' "${2}"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

if [ -z "${ONLY_FIRMWARE}" ]; then
    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${SECTION}" ]; then
    extract_firmware "${MY_DIR}/proprietary-firmware.txt" "${SRC}"
fi

"${MY_DIR}/setup-makefiles.sh"
