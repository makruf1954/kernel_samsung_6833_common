#!/bin/sh

# Kernel Build Script by Mahiroo & improve zero

trap 'echo -e "\n\033[91m[!] Build dibatalkan.\033[0m"; [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ] && tg_channelcast " <b>Build dibatalkan!</b>"; cleanup_files; exit 1' INT
exec > >(tee -a build.log) 2>&1

# ============================
# Setup
# ============================
PHONE="a22x"
DEFCONFIG="a22x_defconfig"
ZIPNAME="A22-$(date '+%Y%m%d-%H%M').zip"
KSU="$(pwd)/KernelSU-Next"
COMPILERDIR="$(pwd)/zyc-clang"
export KBUILD_BUILD_USER="zero"
export KBUILD_BUILD_HOST="naifiprjkt"

# ============================
# Variabel
# ============================
DATE="$(date '+%Y-%m-%d %H:%M:%S')"
kernel="out/arch/arm64/boot/Image.gz"
dtb="out/arch/arm64/boot/dtb.img"
dtbo="out/arch/arm64/boot/dtbo.img"

# ============================
# Warna output
# ============================
cyan="\033[96m"
green="\033[92m"
red="\033[91m"
reset="\033[0m"

function add_ksu() {
     if [ -d $KSU ]; then
         echo -e "$green[!] KernelSU is ready...${reset}"
     else 
         echo -e "$red[!] KernelSU Dir Not Found!!!${reset}"
         echo -e "$green[+] Wait.. Cloning KernelSU...${reset}"
         curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -
     fi
}

function check_tools() {
    local tools=("git" "curl" "wget" "make" "zip")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "$red Tool $tool is required but not installed. Aborting... $reset"
            exit 1
        fi
    done
}

function install_dependencies() {
    echo -e "${cyan}==> Instalasi dependensi...${reset}"
    sudo apt update
    sudo apt install -y bc cpio flex bison aptitude git python-is-python3 tar aria2 perl wget curl lz4 libssl-dev device-tree-compiler zstd
}

function setup_clang() {
    if [ -d $COMPILERDIR ]; then
        echo -e "$green[!] Lets's Build UwU...${reset}"
    else
        echo -e "$red[!] clang Dir Not Found!!!${reset}"
        echo -e "$green[+] Wait.. Cloning clang...${reset}"
        wget "$(curl -s https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-link.txt)" -O "zyc-clang.tar.gz"
        rm -rf $COMPILERDIR 
        mkdir $COMPILERDIR 
        tar -xvf zyc-clang.tar.gz -C $COMPILERDIR
        rm -rf zyc-clang.tar.gz
        echo -e "$green[!] Lets's Build UwU...${reset}"
    fi
}

function tg_channelcast() {
    local msg=""
    for POST in "$@"; do
        msg+="${POST}"$'\n'
    done
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d disable_web_page_preview=true \
        -d parse_mode=HTML \
        -d text="${msg}"
}

function send_error_log() {
    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
    
    tg_channelcast \
        " <b>Build Error untuk $PHONE!</b>" \
        " <b>Durasi:</b> <code>$((DIFF / 60)) menit $((DIFF % 60)) detik</code>" \
        " <b>Log file dikirim untuk debugging</b>"
    
    curl -s -F "chat_id=${CHAT_ID}" \
         -F "document=@log.txt" \
         -F "caption=Error Build untuk $PHONE - $(date '+%Y-%m-%d %H:%M:%S')" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" > /dev/null
}

function upload_success_zip() {
    # Ambil kernel version
    if [ -f "$kernel" ]; then
        KERNEL_VER=$(gzip -dc "$kernel" | strings | grep -m1 "Linux version")
    else
        KERNEL_VER="Unknown"
    fi

    # Caption untuk sukses upload
    CAPTION="*A22-$DATE*
\`\`\`
LocalVersion :
$KERNEL_VER
\`\`\`
*Flash via Recovery*"

    # Upload ZIP
    curl -s -F "document=@$ZIPNAME" \
         -F "chat_id=$CHAT_ID" \
         -F "caption=$CAPTION" \
         -F "parse_mode=Markdown" \
         "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" > /dev/null
    
    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
    
    tg_channelcast \
        " <b>Build Sukses!</b>" \
        " <b>Device:</b> <code>$PHONE</code>" \
        " <b>ZIP:</b> <code>$ZIPNAME</code>" \
        " <b>Durasi:</b> <code>$((DIFF / 60)) menit $((DIFF % 60)) detik</code>"
}

function clean() {
    echo -e "${red}[!] Clean...${reset}"
    rm -rf log.txt full-build.log out/full_defconfig "$ZIPNAME"
}

function cleanup_files() {
    echo -e "${red}[!] Cleanup akhir...${reset}"
    [ -f "$ZIPNAME" ] && rm -f "$ZIPNAME"
    [ -f log.txt ] && rm -f log.txt
    [ -f full-build.log ] && rm -f full-build.log
    [ -f out/full_defconfig ] && rm -f out/full_defconfig
}

function build_kernel() {
    export PATH="$COMPILERDIR/bin:$PATH"
    
    echo -e "${green}==================================\033[0m"
    echo -e "${green}= [!] START BUILD ${DEFCONFIG}\033[0m"
    echo -e "${green}==================================\033[0m"
    
    # Make defconfig
    make -j$(nproc --all) O=out ARCH=arm64 ${DEFCONFIG}
    if [ $? -ne 0 ]; then
        echo -e "$red [!] DEFCONFIG FAILED ${reset}"
        return 1
    fi

    # Build kernel 
    make -j$(nproc --all) \
        O=out \
        ARCH=arm64 \
        LLVM=1 \
        LLVM_IAS=1 \
        AR=llvm-ar \
        NM=llvm-nm \
        LD=ld.lld \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CC=clang \
        DTC_EXT=dtc \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        >full-build.log 2>&1

    # Check for errors  
    grep -Ei "(error|warning)" full-build.log > log.txt   
    
    if grep -q "error:" full-build.log || [ ! -f "$kernel" ]; then
        echo -e "${red}[!] Build gagal${reset}"
        send_error_log
        cleanup_files
        return 1
    fi

    echo -e "${green}[+] Build sukses! Packing ZIP...${reset}"

    # Pack ZIP
    [ ! -d AnyKernel3 ] && git clone -q https://github.com/makruf1954/AnyKernel3.git -b a22x
    cp -f "$kernel" "$dtb" AnyKernel3/
    [ -f "$dtbo" ] && cp -f "$dtbo" AnyKernel3/
    cd AnyKernel3 || return 1
    zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
    cd .. && rm -rf AnyKernel3

    # Save defconfig
    make O=out ARCH=arm64 savedefconfig
    mv out/defconfig out/full_defconfig

    # Upload and notify
    upload_success_zip
    cleanup_files
}

# ============================
# Main Execution
# ============================
BUILD_START=$(date +"%s")
add_ksu
check_tools
install_dependencies
clean
setup_clang
build_kernel
BUILD_FINISH=$(date +"%s")
