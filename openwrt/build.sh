#!/bin/bash -e
export RED_COLOR='\e[1;31m'
export GREEN_COLOR='\e[1;32m'
export YELLOW_COLOR='\e[1;33m'
export BLUE_COLOR='\e[1;34m'
export PINK_COLOR='\e[1;35m'
export SHAN='\e[1;33;5m'
export RES='\e[0m'

#####################################
#  NanoPi R4S OpenWrt Build Script  #
#####################################

# IP Location
ip_info=`curl -s https://ip.cooluc.com`;
export isCN=`echo $ip_info | grep -Po 'country_code\":"\K[^"]+'`;

# script url
if [ "$isCN" = "CN" ]; then
    export mirror=raw.githubusercontent.com/cglcwd/r4s_build_script/master
else
    export mirror=raw.githubusercontent.com/cglcwd/r4s_build_script/master
fi

# private gitea
export gitea=git.cooluc.com

# Check root
if [ "$(id -u)" = "0" ]; then
    echo -e "${RED_COLOR}Building with root user is not supported.${RES}"
    exit 1
fi

# Check CPU
LOW_CPU=$(lscpu | grep "Model name" | grep E5-2673 | wc -l)
if [ "$BUILD_EXTRA" = "y" ] && [ "$(whoami)" = "runner" ] && [ "$LOW_CPU" -ne "0" ]; then
    echo -e "\n${RED_COLOR} Unable to use BUILD_EXTRA=y in low performance GitHub Actions. ${RES}\n"
    exit 1
fi

# Start time
starttime=`date +'%Y-%m-%d %H:%M:%S'`
CURRENT_DATE=$(date +%s)
# Cpus
cores=`expr $(nproc --all) + 1`
# $CURL_BAR
if curl --help | grep progress-bar >/dev/null 2>&1; then
    CURL_BAR="--progress-bar";
fi

# source mirror
if [ "$isCN" = "CN" ]; then
    export github_mirror="https://github.com"
    openwrt_release_mirror="mirror.sjtu.edu.cn/openwrt/releases"
else
    export github_mirror="https://github.com"
    openwrt_release_mirror="downloads.openwrt.org/releases"
fi

# Source branch
if [ "$1" = "dev" ]; then
    export branch=openwrt-23.05
    export version=snapshots-23.05
    export toolchain_version=openwrt-23.05
elif [ "$1" = "rc" ]; then
    latest_release="v$(curl -s https://$mirror/tags/v22)"
    export branch=$latest_release
    export version=rc
    export toolchain_version=openwrt-22.03
elif [ "$1" = "rc2" ]; then
    latest_release="v$(curl -s https://$mirror/tags/v23)"
    export branch=$latest_release
    export version=rc2
    export toolchain_version=openwrt-23.05
elif [ -z "$1" ]; then
    echo -e "\n${RED_COLOR}Building type not specified.${RES}\n"
    echo -e "Usage:\n"
    echo -e "nanopi-r4s releases: ${GREEN_COLOR}bash build.sh rc nanopi-r4s${RES}"
    echo -e "nanopi-r4s snapshots: ${GREEN_COLOR}bash build.sh dev nanopi-r4s${RES}"
    echo -e "nanopi-r5s releases: ${GREEN_COLOR}bash build.sh rc nanopi-r5s${RES}"
    echo -e "nanopi-r5s snapshots: ${GREEN_COLOR}bash build.sh dev nanopi-r5s${RES}"
    echo -e "x86_64 releases: ${GREEN_COLOR}bash build.sh rc x86_64${RES}"
    echo -e "x86_64 snapshots: ${GREEN_COLOR}bash build.sh dev x86_64${RES}\n"
    exit 1
fi

# platform
export platform=$2
[ "$platform" = "nanopi-r4s" ] && export platform="rk3399" toolchain_arch="nanopi-r4s"
[ "$platform" = "nanopi-r5s" ] && export platform="rk3568" toolchain_arch="nanopi-r5s"
[ "$platform" = "x86_64" ] && export platform="x86_64" toolchain_arch="x86_64"

# use glibc - openwrt-22.03
export USE_GLIBC=$USE_GLIBC

# print version
echo -e "\r\n${GREEN_COLOR}Building $branch${RES}\r\n"
if [ "$platform" = "x86_64" ]; then
    echo -e "${GREEN_COLOR}Model: x86_64${RES}"
elif [ "$platform" = "rk3568" ]; then
    echo -e "${GREEN_COLOR}Model: nanopi-r5s/r5c${RES}"
    [ "$1" = "rc" ] || [ "$1" = "rc2" ] && model="nanopi-r5s"
    curl -s https://$mirror/tags/kernel-6.1 > kernel.txt
    kmod_hash=$(grep HASH kernel.txt | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}')
    kmodpkg_name=$(echo $(grep HASH kernel.txt | awk -F'HASH-' '{print $2}' | awk '{print $1}')-1-$(echo $kmod_hash))
    echo -e "${GREEN_COLOR}Kernel: $kmodpkg_name ${RES}"
    rm -f kernel.txt
else
    echo -e "${GREEN_COLOR}Model: nanopi-r4s${RES}"
    [ "$1" = "rc" ] || [ "$1" = "rc2" ] && model="nanopi-r4s"
    curl -s https://$mirror/tags/kernel-6.1 > kernel.txt
    kmod_hash=$(grep HASH kernel.txt | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}')
    kmodpkg_name=$(echo $(grep HASH kernel.txt | awk -F'HASH-' '{print $2}' | awk '{print $1}')-1-$(echo $kmod_hash))
    echo -e "${GREEN_COLOR}Kernel: $kmodpkg_name ${RES}"
    rm -f kernel.txt
fi
echo -e "${GREEN_COLOR}Date: $CURRENT_DATE${RES}\r\n"

# get source
rm -rf openwrt master && mkdir master
# openwrt - releases
git clone --depth=1 $github_mirror/openwrt/openwrt -b $branch

# openwrt master
git clone $github_mirror/openwrt/openwrt master/openwrt --depth=1
git clone $github_mirror/openwrt/packages master/packages --depth=1
git clone $github_mirror/openwrt/luci master/luci --depth=1
git clone $github_mirror/openwrt/routing master/routing --depth=1
# immortalwrt master
git clone $github_mirror/immortalwrt/packages master/immortalwrt_packages --depth=1

if [ -d openwrt ]; then
    cd openwrt
    curl -Os https://$mirror/openwrt/patch/key.tar.gz && tar zxf key.tar.gz && rm -f key.tar.gz
else
    echo -e "${RED_COLOR}Failed to download source code${RES}"
    exit 1
fi

# tags
if [ "$1" = "rc" ] || [ "$1" = "rc2" ]; then
    git describe --abbrev=0 --tags > version.txt
else
    git branch | awk '{print $2}' > version.txt
fi

# kenrel vermagic - https://downloads.openwrt.org/
if [ "$1" = "dev" ]; then
    [ "$platform" = "x86_64" ] && kenrel_vermagic=`curl -s https://$openwrt_release_mirror/23.05-SNAPSHOT/targets/x86/64/packages/Packages | awk -F'[- =)]+' '/^Depends: kernel/{for(i=3;i<=NF;i++){if(length($i)==32){print $i;exit}}}'`
elif [ "$1" = "rc" ]; then
    latest_version="$(curl -s https://$mirror/tags/v22)"
    [ "$platform" = "x86_64" ] && kenrel_vermagic=`curl -s https://$openwrt_release_mirror/"$latest_version"/targets/x86/64/packages/Packages | awk -F'[- =)]+' '/^Depends: kernel/{for(i=3;i<=NF;i++){if(length($i)==32){print $i;exit}}}'`
elif [ "$1" = "rc2" ]; then
    latest_version="$(curl -s https://$mirror/tags/v23)"
    [ "$platform" = "x86_64" ] && kenrel_vermagic=`curl -s https://$openwrt_release_mirror/"$latest_version"/targets/x86/64/packages/Packages | awk -F'[- =)]+' '/^Depends: kernel/{for(i=3;i<=NF;i++){if(length($i)==32){print $i;exit}}}'`
    [ "$platform" = "x86_64" ] && kenrel_version=`curl -s https://$openwrt_release_mirror/"$latest_version"/targets/x86/64/packages/Packages | grep "Depends: kernel" | head -1 | awk -F= '{print $2}' | awk -F\) '{print $1}'`
fi
echo $kenrel_vermagic > .vermagic
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# feeds mirror
if [ "$1" = "rc" ] || [ "$1" = "rc2" ]; then
    packages="^$(grep packages feeds.conf.default | awk -F^ '{print $2}')"
    luci="^$(grep luci feeds.conf.default | awk -F^ '{print $2}')"
    routing="^$(grep routing feeds.conf.default | awk -F^ '{print $2}')"
    telephony="^$(grep telephony feeds.conf.default | awk -F^ '{print $2}')"
else
    packages=";$branch"
    luci=";$branch"
    routing=";$branch"
    telephony=";$branch"
fi
cat > feeds.conf <<EOF
src-git packages $github_mirror/openwrt/packages.git$packages
src-git luci $github_mirror/openwrt/luci.git$luci
src-git routing $github_mirror/openwrt/routing.git$routing
src-git telephony $github_mirror/openwrt/telephony.git$telephony
EOF

# Init feeds
./scripts/feeds update -a
./scripts/feeds install -a

# loader dl
if [ -f ../dl.gz ]; then
    tar xf ../dl.gz -C .
fi

###############################################

echo -e "\n${GREEN_COLOR}Patching ...${RES}\n"

# scripts
curl -sO https://$mirror/openwrt/scripts/00-prepare_base.sh
curl -sO https://$mirror/openwrt/scripts/01-prepare_base-mainline.sh
curl -sO https://$mirror/openwrt/scripts/02-prepare_package.sh
curl -sO https://$mirror/openwrt/scripts/03-convert_translation.sh
curl -sO https://$mirror/openwrt/scripts/04-fix_kmod.sh
curl -sO https://$mirror/openwrt/scripts/05-fix-source.sh
curl -sO https://$mirror/openwrt/scripts/99_clean_build_cache.sh
chmod 0755 *sh
bash 00-prepare_base.sh
bash 02-prepare_package.sh
bash 03-convert_translation.sh
bash 05-fix-source.sh
if [ "$platform" = "rk3568" ] || [ "$platform" = "rk3399" ]; then
    bash 01-prepare_base-mainline.sh
    bash 04-fix_kmod.sh
fi
rm -f 0*-*.sh
rm -rf ../master

# Load devices Config
if [ "$platform" = "x86_64" ]; then
    curl -s https://$mirror/openwrt/22-config-musl-x86 > .config
    ALL_KMODS=y
elif [ "$platform" = "rk3568" ]; then
    curl -s https://$mirror/openwrt/22-config-musl-r5s > .config
    ALL_KMODS=y
else
    curl -s https://$mirror/openwrt/22-config-musl-r4s > .config
fi

# ota
[ "$ENABLE_OTA" = "y" ] && [ "$version" = "rc2" ] && echo 'CONFIG_PACKAGE_luci-app-ota=y' >> .config

# bpf
[ "$ENABLE_BPF" = "y" ] && curl -s https://$mirror/openwrt/config-bpf >> .config

# extra
[ "$BUILD_EXTRA" = "y" ] && curl -s https://$mirror/openwrt/config-extra >> .config

# glibc
if [ "$USE_GLIBC" = "y" ]; then
    curl -s https://$mirror/openwrt/config-glibc >> .config
fi

# sdk
[ "$BUILD_SDK" = "y" ] && curl -s https://$mirror/openwrt/config-sdk >> .config

# openwrt-23.05 gcc11
if [ ! "$USE_GLIBC" = "y" ]; then
    [ "$version" = "snapshots-23.05" ] || [ "$version" = "rc2" ] && curl -s https://$mirror/openwrt/config-gcc11 >> .config
fi

# clean directory - github actions
[ "$(whoami)" = "runner" ] && echo 'CONFIG_AUTOREMOVE=y' >> .config

# uhttpd
[ "$ENABLE_UHTTPD" = "y" ] && sed -i '/nginx/d' .config && echo 'CONFIG_PACKAGE_ariang=y' >> .config

# Toolchain Cache
if [ "$BUILD_FAST" = "y" ] && [ "$(whoami)" = "runner" ]; then
    [ "$USE_GLIBC" = "y" ] && LIBC=glibc || LIBC=musl
    echo -e "\n${GREEN_COLOR}Download Toolchain ...${RES}"
    curl -L https://github.com/sbwml/toolchain-cache/releases/latest/download/toolchain_"$LIBC"_"$toolchain_arch".tar.gz -o toolchain.tar.gz $CURL_BAR
    echo -e "\n${GREEN_COLOR}Process Toolchain ...${RES}"
    tar -zxf toolchain.tar.gz && rm -f toolchain.tar.gz
    mkdir bin
    find ./staging_dir/ -name '*' -exec touch {} \; >/dev/null 2>&1
    find ./tmp/ -name '*' -exec touch {} \; >/dev/null 2>&1
fi

# init openwrt config
rm -rf tmp/*
if [ "$BUILD" = "n" ]; then
    exit 0
else
    make defconfig
fi

# Compile
if [ "$BUILD_TOOLCHAIN" = "y" ]; then
    echo -e "\r\n${GREEN_COLOR}Building Toolchain ...${RES}\r\n"
    make -j$cores toolchain/compile || make -j$cores toolchain/compile V=s || exit 1
    mkdir -p toolchain-cache
    [ "$USE_GLIBC" = "y" ] && LIBC=glibc || LIBC=musl
    tar -zcf toolchain-cache/toolchain_"$LIBC"_"$toolchain_arch".tar.gz ./{build_dir,dl,staging_dir,tmp} && echo -e "${GREEN_COLOR} Build success! ${RES}"
    exit 0
else
    echo -e "\r\n${GREEN_COLOR}Building OpenWrt ...${RES}\r\n"
    sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
    sed -i "/BUILD_ID/aBUILD_DATE=\"$CURRENT_DATE\"" package/base-files/files/usr/lib/os-release
    make -j$cores
fi

# Compile time
endtime=`date +'%Y-%m-%d %H:%M:%S'`
start_seconds=$(date --date="$starttime" +%s);
end_seconds=$(date --date="$endtime" +%s);
SEC=$((end_seconds-start_seconds));

if [ "$platform" = "x86_64" ]; then
    if [ -f bin/targets/x86/64*/*-ext4-combined-efi.img.gz ]; then
        echo -e "${GREEN_COLOR} Build success! ${RES}"
        echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
        if [ "$ALL_KMODS" = y ]; then
            cp -a bin/targets/x86/*/packages $kenrel_version
            rm -f $kenrel_version/Packages*
            bash kmod-sign $kenrel_version
            tar zcf kmod-$kenrel_version.tar.gz $kenrel_version
            rm -rf $kenrel_version
        fi
        # OTA json
        if [ "$1" = "rc2" ]; then
            mkdir -p ota
            curl -Lso ota.json https://us.cooluc.com/openwrt_ota/fw.json || exit 0
            VERSION=$(sed 's/v//g' version.txt)
            SHA256=$(sha256sum bin/targets/x86/64/*-generic-squashfs-combined-efi.img.gz | awk '{print $1}')
            jq ".\"x86_64\"[0].build_date=\"$CURRENT_DATE\"|.\"x86_64\"[0].sha256sum=\"$SHA256\"|.\"x86_64\"[0].url=\"http://gh.cooluc.com/https://github.com/sbwml/builder/releases/latest/download/openwrt-$VERSION-x86-64-generic-squashfs-combined-efi.img.gz\"" ota.json > ota/fw.json
        fi
        # Backup download cache
        if [ "$isCN" = "CN" ] && [ "$1" = "rc" ] || [ "$1" = "rc2" ]; then
            rm -rf dl/geo* dl/go-mod-cache
            tar cf ../dl.gz dl
        fi
        exit 0
    else
        [ "$(whoami)" = "runner" ] && make V=s
        echo -e "\n${RED_COLOR} Build error... ${RES}"
        echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
        echo
        exit 1
    fi
else
    if [ -f bin/targets/rockchip/armv8*/*-r5s-ext4-sysupgrade.img.gz ] || [ -f bin/targets/rockchip/armv8*/*-r5c-ext4-sysupgrade.img.gz ] || [ -f bin/targets/rockchip/armv8*/*-r4s-ext4-sysupgrade.img.gz ]; then
        if [ "$ALL_KMODS" = y ]; then
            cp -a bin/targets/rockchip/armv8*/packages $kmodpkg_name
            rm -f $kmodpkg_name/Packages*
            # driver firmware
            cp -a bin/packages/aarch64_generic/base/*firmware*.ipk $kmodpkg_name/
            bash kmod-sign $kmodpkg_name
            tar zcf kmod-$kmodpkg_name.tar.gz $kmodpkg_name
            rm -rf $kmodpkg_name
        fi
        echo -e "${GREEN_COLOR} Build success! ${RES}"
        echo -e " Build time: ${GREEN_COLOR}$(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s${RES}"
        # OTA json
        if [ "$1" = "rc2" ]; then
            mkdir -p ota
            curl -Lso ota.json https://us.cooluc.com/openwrt_ota/fw.json || exit 0
            VERSION=$(sed 's/v//g' version.txt)
            if [ "$model" = "nanopi-r4s" ]; then
                SHA256=$(sha256sum bin/targets/rockchip/armv8*/*-squashfs-sysupgrade.img.gz | awk '{print $1}')
                jq ".\"friendlyarm,nanopi-r4s\"[0].build_date=\"$CURRENT_DATE\"|.\"friendlyarm,nanopi-r4s\"[0].sha256sum=\"$SHA256\"|.\"friendlyarm,nanopi-r4s\"[0].url=\"http://gh.cooluc.com/https://github.com/sbwml/builder/releases/latest/download/openwrt-$VERSION-rockchip-armv8-friendlyarm_nanopi-r4s-squashfs-sysupgrade.img.gz\"" ota.json > ota/fw.json
            elif [ "$model" = "nanopi-r5s" ]; then
                SHA256_R5C=$(sha256sum bin/targets/rockchip/armv8*/*-r5c-squashfs-sysupgrade.img.gz | awk '{print $1}')
                SHA256_R5S=$(sha256sum bin/targets/rockchip/armv8*/*-r5s-squashfs-sysupgrade.img.gz | awk '{print $1}')
                jq ".\"friendlyarm,nanopi-r5s\"[0].build_date=\"$CURRENT_DATE\"|.\"friendlyarm,nanopi-r5s\"[0].sha256sum=\"$SHA256_R5S\"|.\"friendlyarm,nanopi-r5s\"[0].url=\"http://gh.cooluc.com/https://github.com/sbwml/builder/releases/latest/download/openwrt-$VERSION-rockchip-armv8-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz\"|.\"friendlyarm,nanopi-r5c\"[0].build_date=\"$CURRENT_DATE\"|.\"friendlyarm,nanopi-r5c\"[0].sha256sum=\"$SHA256_R5C\"|.\"friendlyarm,nanopi-r5c\"[0].url=\"http://gh.cooluc.com/https://github.com/sbwml/builder/releases/latest/download/openwrt-$VERSION-rockchip-armv8-friendlyarm_nanopi-r5c-squashfs-sysupgrade.img.gz\"" ota.json > ota/fw.json
            fi
        fi
        # Backup download cache
        if [ "$isCN" = "CN" ] && [ "$1" = "rc" ] || [ "$version" = "rc2" ]; then
            rm -rf dl/geo* dl/go-mod-cache
            tar -cf ../dl.gz dl
        fi
        exit 0
    else
        [ "$(whoami)" = "runner" ] && make V=s
        echo -e "\n${RED_COLOR} Build error... ${RES}"
        echo -e " Build time: ${RED_COLOR}$(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s${RES}"
        echo
        exit 1
    fi
fi

# 很少有人会告诉你为什么要这样做，而是会要求你必须要这样做。
