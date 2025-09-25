#!/bin/bash

# Script version
SCRIPT_VERSION="1.0"

set -e

# Define global variables
SRC="$(pwd)"
export KBUILD_BUILD_USER="azure"
export KBUILD_BUILD_HOST="naifiprjkt"
ANYKERNEL3_DIR=AK
DEVICE=A226B
BRANCH=$(git rev-parse --abbrev-ref HEAD)
KERNEL_DEFCONFIG=a22x_defconfig
LOG_FILE="$SRC/build.log"
COMPILATION_LOG="$SRC/compilation.log"
FINAL_KERNEL_ZIP="$DEVICE-$BRANCH-$(date +%Y%m%d-%H%M).zip"
TOOLCHAIN_DIR="$SRC/toolchain"
OUT_IMG="$SRC/out/arch/arm64/boot/Image.gz"

# Define architecture
ARCH=arm64

# Remove old kernel zip files
rm -rf *.zip
rm -rf AK/Image*
rm -rf AK/*.zip

# Color definitions
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
nocol='\033[0m'

# function clone KernelSU
check_ksu() {
    if [ ! -d "$SRC/KernelSU-Next" ]; then
	    echo -e "$red KernelSU not found in $SRC/KernelSU-Next, Cloning...$nocol"
	    curl -LSs "https://raw.githubusercontent.com/sidex15/KernelSU-Next/refs/heads/next-susfs/kernel/setup.sh" | bash -s next-susfs
    else
	    echo -e "$green KernelSU already $nocol"
    fi
}

# Function to log messages
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to check required tools
check_tools() {
    local tools=("git" "curl" "wget" "make" "zip")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "$red Tool $tool is required but not installed. Aborting... $nocol"
            exit 1
        fi
    done
}

# Function to check for Telegram credentials
check_telegram_credentials() {
    if [[ -z "${CHAT_ID}" || -z "${BOT_TOKEN}" ]]; then
        log "$red CHAT_ID and BOT_TOKEN are not set. Aborting... $nocol"
        exit 1
    else
        log "$green Telegram credentials found. $nocol"
    fi
}

# Function to set up toolchain
set_toolchain() {
    # Check if toolchain exists, if not clone it
    if [ ! -d "$TOOLCHAIN_DIR" ]; then
        log "$red Toolchain not found in $TOOLCHAIN_DIR, cloning...$nocol"
        git clone --depth=1 https://gitlab.com/neel0210/toolchain.git "$TOOLCHAIN_DIR"
    else
        log "$green Toolchain found at $TOOLCHAIN_DIR $nocol"
    fi

    # Set GCC, Clang, and Clang Triple paths
    GCC64_PATH="$TOOLCHAIN_DIR/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
    CLANG_PATH="$TOOLCHAIN_DIR/clang/host/linux-x86/clang-r383902/bin/clang"
    CLANG_TRIPLE_PATH="$TOOLCHAIN_DIR/clang/host/linux-x86/clang-r383902/bin/aarch64-linux-gnu-"
}

# Function to perform clean build
perform_clean_build() {
    log "$blue Performing clean build... $nocol"
    make clean
    rm -rf *.log
}

# Function to send logs to Telegram and exit
send_logs_and_exit() {
    log "$red Build failed! Preparing to send logs to Telegram... $nocol"
    
    # Create compilation log if it doesn't exist
    if [ ! -f "$COMPILATION_LOG" ]; then
        echo "Build failed at $(date)" > "$COMPILATION_LOG"
        echo "Check build.log for more details" >> "$COMPILATION_LOG"
        if [ -f "$LOG_FILE" ]; then
            cat "$LOG_FILE" >> "$COMPILATION_LOG"
        fi
    fi
    
    local caption=$(printf "<b>Build Failed</b>\n<b>Branch:</b> %s\n<b>Last commit:</b> %s\n<b>Time:</b> %s" \
        "$(sanitize_for_telegram "$(git rev-parse --abbrev-ref HEAD)")" \
        "$(sanitize_for_telegram "$(git log -1 --pretty=format:'%s')")" \
        "$(date +"%d-%m-%Y %H:%M")")
    
    curl -s -F "document=@$COMPILATION_LOG" \
         --form-string "caption=${caption}" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument?chat_id=${CHAT_ID}&parse_mode=HTML"
    
    log "$red Build logs sent to Telegram. Exiting... $nocol"
    exit 1
}

# Function to sanitize text for Telegram
sanitize_for_telegram() {
    local input="$1"
    echo "$input" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Function to build the kernel
build_kernel() {
    log "$blue **** Kernel defconfig is set to $KERNEL_DEFCONFIG **** $nocol"
    log "$blue ***********************************************"
    log "          BUILDING KAKAROT KERNEL          "
    log "*********************************************** $nocol"
    
    # Set the defconfig
    if ! make O=out ARCH="$ARCH" "$KERNEL_DEFCONFIG" 2>&1 | tee -a "$COMPILATION_LOG"; then
        log "$red Defconfig failed! $nocol"
        send_logs_and_exit
    fi
    
    # Build kernel with output logging
    if ! make -j$(nproc --all) O=out \
        ARCH="$ARCH" \
        CC="$CLANG_PATH" \
        CLANG_TRIPLE="$CLANG_TRIPLE_PATH" \
        CROSS_COMPILE="$GCC64_PATH" \
        CONFIG_NO_ERROR_ON_MISMATCH=y 2>&1 | tee -a "$COMPILATION_LOG"; then
        log "$red Kernel compilation failed! $nocol"
        send_logs_and_exit
    fi
    
    # Check if kernel image was created
    if [ ! -f "$OUT_IMG" ]; then
        log "$red Kernel image not found after build! $nocol"
        send_logs_and_exit
    fi
    
    log "$green Kernel build completed successfully! $nocol"
}

# Function to zip kernel files
zip_kernel_files() {
    log "$blue **** Verifying AnyKernel3 Directory **** $nocol"

    if [ ! -d "$SRC/AK" ]; then
        git clone --depth=1 https://github.com/makruf1954/AnyKernel3.git -b a22x AK
    else
        log "$blue AnyKernel3 (AK) already present! $nocol"
    fi

    # Copy kernel image
    cp "$OUT_IMG" "$ANYKERNEL3_DIR/"
    
    log "$cyan ***********************************************"
    log "          Time to zip up!          "
    log "*********************************************** $nocol"
    
    cd "$ANYKERNEL3_DIR/" || exit
    zip -r9 "../$FINAL_KERNEL_ZIP" * -x README "$FINAL_KERNEL_ZIP"
    cd "$SRC" || exit
}

# Function to upload kernel to Telegram
upload_kernel_to_telegram() {
    log "$red ***********************************************"
    log "         Uploading to telegram         "
    log "*********************************************** $nocol"

    # Check if ZIP file exists
    if [ ! -f "$FINAL_KERNEL_ZIP" ]; then
        log "$red ZIP file $FINAL_KERNEL_ZIP not found! Cannot upload. $nocol"
        return 1
    fi

    # Tanggal Dibuat
    DATE=$(date +"%d-%m-%Y %H:%M")

    # Ambil kernel version
    if [ -f "$OUT_IMG" ]; then
        KERNEL_VER=$(zcat "$OUT_IMG" 2>/dev/null | strings | grep -m1 "Linux version" || echo "Version info not found")
    else
        KERNEL_VER="Unknown"
    fi

    # Create caption for successful build
    CAPTION="*$DATE*
\`\`\`
$KERNEL_VER
\`\`\`"

    # Upload kernel ZIP to Telegram
    log "$green Uploading kernel ZIP: $FINAL_KERNEL_ZIP $nocol"
    
    response=$(curl -s -F "document=@$FINAL_KERNEL_ZIP" \
         -F "chat_id=$CHAT_ID" \
         -F "caption=$CAPTION" \
         -F "parse_mode=Markdown" \
         "https://api.telegram.org/bot$BOT_TOKEN/sendDocument")

    # Check if upload was successful
    if echo "$response" | grep -q '"ok":true'; then
        log "$green Kernel successfully uploaded to Telegram! $nocol"
    else
        log "$red Failed to upload kernel to Telegram. Response: $response $nocol"
        return 1
    fi
}

# Function to clean up
clean_up() {
    log "$cyan ***********************************************"
    log "          All done !!!         "
    log "*********************************************** $nocol"
    rm -rf "$ANYKERNEL3_DIR" *.log *.zip
}

# Main script execution
main() {
    log "$green Starting kernel build script v$SCRIPT_VERSION $nocol"
    check_ksu
    check_tools
    check_telegram_credentials
    set_toolchain

    BUILD_START=$(date +"%s")

    perform_clean_build
    build_kernel
    zip_kernel_files

    BUILD_END=$(date +"%s")
    DIFF=$(($BUILD_END - $BUILD_START))
    log "$yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds. $nocol"

    upload_kernel_to_telegram
    clean_up

    log "$green Script execution completed successfully! $nocol"
}

# Run main function
main
