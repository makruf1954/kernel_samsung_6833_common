#!/bin/sh

# Kernel Build Script by Mahiroo aka Yudaa

trap 'echo -e "\n\033[91m[!] Build dibatalkan oleh user.\033[0m"; tg_channelcast " <b>Build kernel dibatalkan oleh user!</b>"; cleanup_files; exit 1' INT
exec > >(tee -a build.log) 2>&1

# ============================
# Setup
# ============================
PHONE="a22x"
DEFCONFIG="a22x_defconfig"
CLANG="Neutron Clang 19"
ZIPNAME="A22-$(date '+%Y%m%d-%H%M').zip"
COMPILERDIR="$(pwd)/zyc-clang"
export KBUILD_BUILD_USER="zero"
export KBUILD_BUILD_HOST="naifiprjkt"
source bot

# ============================
# Variabel Telegram dan Device Info
# ============================
DATE="$(date '+%Y-%m-%d %H:%M:%S')"
MESSAGE_ERROR="Error Build untuk $PHONE Dibatalkan!"
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

function install_dependencies() {
    echo -e "${cyan}==> Instalasi dependensi...${reset}"
    sudo apt update
    sudo apt install -y bc cpio flex bison aptitude git python-is-python3 tar aria2 perl wget curl lz4 libssl-dev device-tree-compiler
    sudo apt install -y zstd
}

function clang() {
if [ -d $COMPILERDIR ] ; then
echo -e " "
echo -e "\n$green[!] Lets's Build UwU...\033[0m \n"
else
echo -e " "
echo -e "\n$red[!] clang Dir Not Found!!!\033[0m \n"
sleep 2
echo -e "$green[+] Wait.. Cloning clang...\033[0m \n"
sleep 2
wget "$(curl -s https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-link.txt)" -O "zyc-clang.tar.gz"
    rm -rf $COMPILERDIR 
    mkdir $COMPILERDIR 
    tar -xvf zyc-clang.tar.gz -C $COMPILERDIR
    rm -rf zyc-clang.tar.gz
sleep 1
echo
echo -e "\n$green[!] Lets's Build UwU...\033[0m \n"
sleep 1
fi
}

function verify_toolchain_versions() {
    echo -e "${green} Clang  : $(${CLANG_DIR}/bin/clang --version | head -n 1)${reset}"
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

function send_success_message() {
    tg_channelcast \
        " <b>Build Sukses!</b>" \
        " <b>Device :</b> <code>$DEVICE</code>" \
        " <b>ZIP:</b> <code>$ZIPNAME</code>" \
        " <b>Durasi:</b> <code>$((DIFF / 60)) menit $((DIFF % 60)) detik</code>"
}

function send_log() {
    curl -s -F "chat_id=${CHAT_ID}" -F "document=@log.txt" -F "caption=${MESSAGE_ERROR}" "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" > /dev/null
}

function clean() {
    echo -e "${red}[!] Clean...${reset}"
    rm -rf log.txt full-build.log out/full_defconfig "$ZIPNAME"
}

function clean_out_dir() {
    echo -e "${red}[!] Bersihkan out/...${reset}"
    [ -d out ] && rm -rf out/* || mkdir out
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
    make -j$(nproc --all) O=out ARCH=arm64 ${DEFCONFIG}
    if [ $? -ne 0 ]
then
    echo -e "\n"
    echo -e "$red [!] BUILD FAILED \033[0m"
    echo -e "\n"
else
    echo -e "\n"
    echo -e "$green==================================\033[0m"
    echo -e "$green= [!] START BUILD ${DEFCONFIG}\033[0m"
    echo -e "$green==================================\033[0m"
    echo -e "\n"
fi

# Speed up build process
MAKE="./makeparallel"

# Build Start Here

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
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee full-build.log

    grep -Ei "(error|warning)" full-build.log > log.txt

    if grep -q "error:" full-build.log || [ ! -f out/arch/arm64/boot/Image ]; then
        echo -e "${red}[!] Build gagal${reset}"
        send_log
        cleanup_files
        return 1
    fi

    echo -e "${green}[+] Build sukses! Packing ZIP...${reset}"

    [ ! -d AnyKernel3 ] && git clone -q https://github.com/makruf1954/AnyKernel3.git -b a22x
    cp -f "$kernel" "$dtb" AnyKernel3/
    [ -f "$dtbo" ] && cp -f "$dtbo" AnyKernel3/
    cd AnyKernel3 || return 1
    zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
    cd .. && rm -rf AnyKernel3

    make O=out ARCH=arm64 savedefconfig
    mv out/defconfig out/full_defconfig

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))

    echo -e "${green} Durasi Build : $((DIFF / 60)) menit $((DIFF % 60)) detik${reset}"
    upload_zip
    send_success_message
    cleanup_files
}

function upload_zip() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" -F document=@"$ZIPNAME" -F chat_id="$CHAT_ID" > /dev/null
}

# ============================
# Eksekusi utama
# ============================
BUILD_START=$(date +"%s")
install_dependencies
clean
clang
build_kernel
