#!/usr/bin/env bash
#  SPDX-License-Identifier: BSD-3-Clause
#  All rights reserved.
#

# exit on errors
set -e

ROOT_DIR=$(readlink -f $(dirname $0))/../..
export CROSS_COMPILE_DIR=$ROOT_DIR/cross_compiling
export SPDK_DIR=$ROOT_DIR/spdk
export DPDK_DIR=$SPDK_DIR/dpdk-install
export FIO_DIR=$SPDK_DIR/../fio

# 定义工具链路径变量
TOOLCHAIN_NAME="gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu"
TOOLCHAIN_PATH="$CROSS_COMPILE_DIR/$TOOLCHAIN_NAME"

# ==============================================================================
# 目标系统根目录 (Sysroot)
# ==============================================================================
TARGET_SYSROOT="$TOOLCHAIN_PATH/aarch64-none-linux-gnu/libc"
TARGET_INCLUDE="$TARGET_SYSROOT/usr/include"
TARGET_LIB="$TARGET_SYSROOT/usr/lib"

# Get Toolchain
function get_cc_toolchain() {
	cd $CROSS_COMPILE_DIR

	if [ ! -d "$TOOLCHAIN_PATH" ]; then
		echo -e "Getting ARM Cross Compiler Toolchain..."
		wget https://developer.arm.com/-/media/Files/downloads/gnu-a/10.2-2020.11/binrel/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu.tar.xz --no-check-certificate
		tar xvf gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu.tar.xz
	else
		echo -e "ARM Cross Compiler Toolchain already downloaded"
	fi

	export PATH=$PATH:$TOOLCHAIN_PATH/bin
}

# NUMA
function cross_compile_numa() {
	cd $CROSS_COMPILE_DIR
    # ... (Numa 部分通常没问题，保持原样，如果有缓存可保留)
	if [ ! -d "$CROSS_COMPILE_DIR/numactl" ]; then
		git clone https://github.com/numactl/numactl.git
		cd numactl/
		git checkout v2.0.13 -b v2.0.13
        cd ..
	fi

	if [ ! -d "$CROSS_COMPILE_DIR/numactl/build" ]; then
        cd numactl
		echo -e "Building NUMA library..."
		./autogen.sh
		autoconf -i
		mkdir build
		./configure --host=aarch64-none-linux-gnu CC=aarch64-none-linux-gnu-gcc --prefix=$CROSS_COMPILE_DIR/numactl/build
		make -j install

		echo -e "Copying NUMA library dependencies..."
		cp build/include/numa*.h $TARGET_INCLUDE/
		cp -d build/lib/libnuma.so* $TARGET_LIB/
		cp build/lib/libnuma.a $TARGET_LIB/
	fi
}

# util-linux UUID
function cross_compile_uuid() {
	cd $CROSS_COMPILE_DIR
	if [ ! -d "$CROSS_COMPILE_DIR/util-linux" ]; then
		git clone https://github.com/karelzak/util-linux.git
	fi

	if [ ! -d "$CROSS_COMPILE_DIR/util-linux/.libs" ]; then
		cd util-linux/
		echo -e "Building util-linux UUID library..."
		./autogen.sh
		CC=aarch64-none-linux-gnu-gcc CXX=aarch64-none-linux-gnu-g++ LD=aarch64-none-linux-gnu-ld \
		CFLAGS+=-Wl,-rpath=$CROSS_COMPILE_DIR/util-linux/.libs \
		./configure --host=aarch64-none-linux-gnu --without-tinfo --without-ncurses --without-ncursesw \
		--disable-mount --disable-libmount --disable-pylibmount --disable-libblkid --disable-fdisks \
		--disable-libfdisk --without-systemd --disable-liblastlog2
		
		make clean
		make -j
		
		cp .libs/libuuid.so.1.3.0 $TARGET_LIB/libuuid.so
		ln -sf libuuid.so $TARGET_LIB/libuuid.so.1
		mkdir -p $TARGET_INCLUDE/uuid/
		cp libuuid/src/uuid.h $TARGET_INCLUDE/uuid/
	fi
}

# Openssl
function cross_compile_crypto_ssl() {
	cd $CROSS_COMPILE_DIR
	if [ ! -d "$CROSS_COMPILE_DIR/openssl" ]; then
		git clone https://github.com/openssl/openssl.git
	fi

	if [ ! -d "$CROSS_COMPILE_DIR/openssl/build" ]; then
		cd openssl
		echo -e "Building Openssl..."
		mkdir build
		./Configure linux-aarch64 --prefix=$CROSS_COMPILE_DIR/openssl/build --cross-compile-prefix=aarch64-none-linux-gnu-
		make -j
		make -j install

		cp -fr build/include/openssl $TARGET_INCLUDE/
		cp -d build/lib/libcrypto.so* $TARGET_LIB/
		cp -d build/lib/libssl.so* $TARGET_LIB/
		cp build/lib/libcrypto.a $TARGET_LIB/
		cp build/lib/libssl.a $TARGET_LIB/
        mkdir -p $TARGET_LIB/pkgconfig
		cp build/lib/pkgconfig/*.pc $TARGET_LIB/pkgconfig/
	fi
}

# Libaio
function cross_compile_libaio() {
	cd $CROSS_COMPILE_DIR
	if [ ! -d "$CROSS_COMPILE_DIR/libaio" ]; then
		wget https://ftp.debian.org/debian/pool/main/liba/libaio/libaio_0.3.112.orig.tar.xz --no-check-certificate
		tar xvf libaio_0.3.112.orig.tar.xz
		mv libaio-0.3.112 libaio
	fi

	if [ ! -d "$CROSS_COMPILE_DIR/libaio/build" ]; then
		cd libaio
		mkdir build
		CC=aarch64-none-linux-gnu-gcc CXX=aarch64-none-linux-gnu-g++ LD=aarch64-none-linux-gnu-ld make -j
		make -j install DESTDIR=$CROSS_COMPILE_DIR/libaio/build
		cp build/usr/include/libaio.h $TARGET_INCLUDE/
		cp build/usr/lib/libaio.so.1.0.1 $TARGET_LIB/libaio.so
		ln -sf libaio.so $TARGET_LIB/libaio.so.1
	fi
}

# Ncurses
function cross_compile_ncurses() {
	cd $CROSS_COMPILE_DIR
	if [ ! -d "$CROSS_COMPILE_DIR/ncurses" ]; then
		wget https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.2.tar.gz --no-check-certificate
		tar xvf ncurses-6.2.tar.gz
		mv ncurses-6.2 ncurses
	fi

	if [ ! -d "$CROSS_COMPILE_DIR/ncurses_build" ]; then
		mkdir ncurses_build
		# 必须加 --with-termlib
		(cd ncurses && ./configure --host=aarch64-none-linux-gnu --prefix=$CROSS_COMPILE_DIR/ncurses_build \
			--disable-stripping --with-termlib --with-shared && make -j install)

		cp -r ncurses_build/include/ncurses $TARGET_INCLUDE/
		cp ncurses_build/include/ncurses/*.h $TARGET_INCLUDE/
		cp -d ncurses_build/lib/lib*.so* $TARGET_LIB/
		cp ncurses_build/lib/*.a $TARGET_LIB/
	fi
}

# CUnit
function cross_compile_cunit() {
	cd $CROSS_COMPILE_DIR
	if [ ! -d "$CROSS_COMPILE_DIR/CUnit" ]; then
		git clone https://github.com/jacklicn/CUnit.git
	fi

	if [ ! -d "$CROSS_COMPILE_DIR/CUnit/build" ]; then
		cd CUnit
		mkdir build
		libtoolize --force
		aclocal
		autoheader
		automake --force-missing --add-missing
		autoconf
		./configure --host=aarch64-none-linux-gnu --prefix=$CROSS_COMPILE_DIR/CUnit/build
		make -j
		make -j install
		cp -fr build/include/CUnit $TARGET_INCLUDE/
		cp build/lib/libcunit.a $TARGET_LIB/
		cp build/lib/libcunit.so.1.0.1 $TARGET_LIB/libcunit.so
	fi
}

# ==============================================================================
# 修复版函数：强制修复软链接为相对路径
# ==============================================================================

# Libmd
function cross_compile_libmd() {
	cd $CROSS_COMPILE_DIR

	if [ ! -d "$CROSS_COMPILE_DIR/libmd" ]; then
		wget https://archive.hadrons.org/software/libmd/libmd-1.1.0.tar.xz --no-check-certificate
		tar xvf libmd-1.1.0.tar.xz
		mv libmd-1.1.0 libmd
	fi

    # 1. 强制清理旧构建
    rm -rf "$CROSS_COMPILE_DIR/libmd/build"
    
	cd libmd
	echo -e "Building libmd library (Forced Rebuild)..."
	mkdir -p build
	
	./configure --host=aarch64-none-linux-gnu --prefix=/usr --libdir=/usr/lib
	make -j
	make install DESTDIR=$CROSS_COMPILE_DIR/libmd/build

	echo -e "Copying libmd library dependencies..."
	
    # 2. 删除所有 .la 文件 (毒药)
	rm -f build/usr/lib/*.la
    rm -f $TARGET_LIB/libmd.la

    # 3. 复制头文件和库文件
	cp build/usr/include/md5.h $TARGET_INCLUDE/
	cp build/usr/include/sha*.h $TARGET_INCLUDE/
	cp -d build/usr/lib/libmd.so* $TARGET_LIB/
	cp build/usr/lib/libmd.a $TARGET_LIB/

    # 4. 【关键修复】进入目标目录，强制重做软链接为相对路径
    # 防止 libmd.so -> /usr/lib/libmd.so.0.0.5 这种情况
    cd $TARGET_LIB
    if [ -L libmd.so ]; then
        rm libmd.so
        # 这里的版本号 1.1.0 对应 libmd.so.0.0.5 (具体看编译生成的文件，通常指向 .so.0)
        # 自动查找真实文件名
        REAL_LIBMD=$(ls libmd.so.*.*.* | head -n 1)
        ln -sf $REAL_LIBMD libmd.so
        ln -sf $REAL_LIBMD libmd.so.0
        echo "Fixed libmd symlinks: libmd.so -> $REAL_LIBMD"
    fi
}

# Libbsd
function cross_compile_libbsd() {
	cd $CROSS_COMPILE_DIR

	if [ ! -d "$CROSS_COMPILE_DIR/libbsd" ]; then
		wget https://libbsd.freedesktop.org/releases/libbsd-0.11.7.tar.xz --no-check-certificate
		tar xvf libbsd-0.11.7.tar.xz
		mv libbsd-0.11.7 libbsd
	fi

    # 1. 强制清理旧构建
    rm -rf "$CROSS_COMPILE_DIR/libbsd/build"

	cd libbsd
	echo -e "Building libbsd library (Forced Rebuild)..."
	mkdir -p build

	./configure --host=aarch64-none-linux-gnu --prefix=/usr --libdir=/usr/lib --disable-static
	make -j
	make install DESTDIR=$CROSS_COMPILE_DIR/libbsd/build

	echo -e "Copying libbsd library dependencies..."
	
    # 2. 删除 .la 文件
	rm -f build/usr/lib/*.la
    rm -f $TARGET_LIB/libbsd.la

    # 3. 复制文件
	cp -r build/usr/include/bsd $TARGET_INCLUDE/
	cp -d build/usr/lib/libbsd.so* $TARGET_LIB/

    # 4. 【关键修复】强制重做 libbsd 的软链接
    # 此时 $TARGET_LIB 里应该有 libbsd.so.0.11.7
    cd $TARGET_LIB
    
    # 删除可能指向 /usr/lib/xxx 的坏链接
    rm -f libbsd.so
    rm -f libbsd.so.0

    # 确认真实文件存在
    if [ -f "libbsd.so.0.11.7" ]; then
        echo "Fixing libbsd symlinks..."
        # 创建相对路径链接
        ln -s libbsd.so.0.11.7 libbsd.so
        ln -s libbsd.so.0.11.7 libbsd.so.0
    else
        echo "Error: libbsd.so.0.11.7 not found in $TARGET_LIB"
        exit 1
    fi
    
    # 5. 修复 pkg-config 文件 (如果存在)
    # 有时候 SPDK 会通过 pkg-config 查找，如果 .pc 文件里写了 prefix=/usr 也会导致问题
    if [ -d "$TARGET_LIB/pkgconfig" ]; then
        cp $CROSS_COMPILE_DIR/libbsd/build/usr/lib/pkgconfig/libbsd.pc $TARGET_LIB/pkgconfig/
        # 将 /usr 替换为相对路径或者置空，这里简单处理，让它依赖 sysroot
        sed -i "s|^prefix=/usr|prefix=$TARGET_SYSROOT/usr|g" $TARGET_LIB/pkgconfig/libbsd.pc
    fi
}

# ISA-L
function cross_compile_isal() {
	cd $SPDK_DIR
    # ISA-L 比较简单，通常不会出这种路径问题，但如果出错也可以考虑 rm -rf build
	if [ ! -d "$SPDK_DIR/isa-l/build" ]; then
		cd isa-l
		./autogen.sh
		mkdir -p build/lib
		ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes ./configure --prefix=$SPDK_DIR/isa-l/build --libdir=$SPDK_DIR/isa-l/build/lib --host=aarch64-none-linux-gnu
		make -j
		make -j install

		cp -fr build/include/isa-l $TARGET_INCLUDE/
		cp build/include/isa-l.h $TARGET_INCLUDE/
		cp build/lib/libisal.a $TARGET_LIB/
		cp -d build/lib/libisal.so* $TARGET_LIB/
	fi
}

# SPDK
function cross_compile_spdk() {
	cd $SPDK_DIR

	echo -e "Building SPDK libraries and binaries..."

	# 清理 SPDK 之前的构建，防止缓存了错误的库路径
	if [ -f mk/config.mk ]; then
		make clean
		rm -f mk/config.mk
	fi
	export PKG_CONFIG_PATH=$DPDK_DIR/lib/pkgconfig:$PKG_CONFIG_PATH

	CC=aarch64-none-linux-gnu-gcc \
	CXX=aarch64-none-linux-gnu-g++ \
	LD=aarch64-none-linux-gnu-ld \
	CFLAGS="-I$DPDK_DIR/include" \
	LDFLAGS="" \
	./configure \
		--cross-prefix=aarch64-none-linux-gnu \
		--without-vhost \
		--with-dpdk=$DPDK_DIR \
		--with-fio=$FIO_DIR \
		--target-arch=armv8-a \
		--without-nvme-cuse \
		--disable-tests \
		--disable-unit-tests \
		--without-crypto \
		--without-rdma \
		--without-vhost \
		--without-virtio \
		--without-rbd

	make -j
}

mkdir -p $CROSS_COMPILE_DIR

get_cc_toolchain

# 确保目标库目录存在
mkdir -p $TARGET_INCLUDE
mkdir -p $TARGET_LIB

# 按顺序执行
cross_compile_packages=(numa uuid crypto_ssl libaio ncurses cunit libmd libbsd isal spdk)

for index in "${cross_compile_packages[@]}"; do
	cross_compile_$index
done