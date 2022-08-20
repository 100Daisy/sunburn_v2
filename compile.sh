#!/bin/sh

# Option on whether to upload the produced build to a file hosting service [Useful for CI builds]
UPLD=1
	if [ $UPLD = 1 ]; then
	UPLD_PROV="https://transfer.sh"
        UPLD_PROV2="https://oshi.at"
	fi

# Setup build env
sudo apt-get install ccache gzip cpio flex

# Clone toolchain from its repository
mkdir clang && curl -Lsq https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android11-release/clang-r383902.tar.gz -o - | tar -xzf - -C clang
git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b android11-release binutils
git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 -b android11-release binutils-32

# Clone AnyKernel3
git clone --depth=1 https://github.com/100Daisy/AnyKernel3 -b sunburn-$1

# Export the PATH variable
export PATH="$(pwd)/clang/bin:$(pwd)/binutils/bin:$(pwd)/binutils-32/bin:$PATH"

# Clean up out
rm -rf out
mkdir out

# Compile the kernel
build_kernel() {
    make -j$(nproc --all) \
    O=out \
    ARCH=arm64 \
    CC=clang \
    HOSTCC=clang \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi-
}

build_modules() {
    make -j$(nproc --all) \
    O=out \
    ARCH=arm64 \
    CC=clang \
    HOSTCC=clang \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- \
    M=$1
}

merge_config() {
    ARCH=arm64 \
    CC=clang \
    HOSTCC=clang \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- \
    scripts/kconfig/merge_config.sh -m -O arch/arm64/configs \
    $1
}

# Defconfig
#merge_config 'arch/arm64/configs/vendor/bengal-perf_defconfig arch/arm64/configs/vendor/ext_config/moto-bengal.config arch/arm64/configs/vendor/ext_config/$1-default.config'
#mv arch/arm64/configs/.config arch/arm64/configs/sunburn_defconfig
make sunburn-$1_defconfig ARCH=arm64 O=out CC=clang

build_kernel

# This will build all possible modules. 
# Building some of them might result in a fail.
# Some of the modules shouldn't been built with tag you merged, that's why.

for i in $(find motorola/kernel/modules -name "Android.mk" -exec dirname {} \;)
do
    build_modules $i
done

# Move modules
for i in $(find out/motorola/kernel/modules -name "*.ko";)
do
    cp $i AnyKernel3/modules/vendor/lib/modules
done

# Zip up the kernel
zip_kernelimage() {
    rm -rf AnyKernel3/Image.gz-dtb
    cp out/arch/arm64/boot/Image.gz-dtb AnyKernel3
    rm -rf AnyKernel3/*.zip
    BUILD_TIME=$(date +"%d%m%Y-%H%M")
    cd AnyKernel3
    KERNEL_NAME=SunBurn-$1-"${BUILD_TIME}"
    zip -r9 "$KERNEL_NAME".zip ./*
    cd ..
}

FILE="$(pwd)/out/arch/arm64/boot/Image.gz-dtb"
if [ -f "$FILE" ]; then
    zip_kernelimage $1
    KERN_FINAL="$(pwd)/AnyKernel3/"$KERNEL_NAME".zip"
    echo "The kernel has successfully been compiled and can be found in $KERN_FINAL"
    if [ "$UPLD" = 1 ]; then
        for i in "$UPLD_PROV" "$UPLD_PROV2"; do
            curl --connect-timeout 5 -T "$KERN_FINAL" "$i"
            echo " "
        done
    fi
else
    echo "The kernel has failed to compile. Please check the terminal output for further details."
    exit 1
fi
