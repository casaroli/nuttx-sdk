#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2026 Marco Casaroli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build an arm-uclinuxfdpiceabi cross compiler for NuttX FDPIC modules.
#
# Only a stage-1 C compiler is needed.  Modules link -nostdlib and import
# libc from the firmware's symbol table, so no target C library is built --
# which removes the bulk of a normal FDPIC toolchain build.
#
# On macOS two things will otherwise bite:
#
#   * the default filesystem is case-insensitive and GCC will not build on
#     it.  Create a case-sensitive volume first:
#
#       hdiutil create -size 30g -fs "Case-sensitive APFS" \
#           -volname fdpic -type SPARSE fdpic-build.sparseimage
#       hdiutil attach fdpic-build.sparseimage
#
#   * the bundled zlib does not compile against the macOS SDK headers,
#     hence --with-system-zlib below.
#
# Usage: build-toolchain.sh <workdir> [install-prefix]

set -e

WORK="${1:?usage: build-toolchain.sh <workdir> [prefix]}"
PREFIX="${2:-$WORK/toolchain}"
TARGET=arm-uclinuxfdpiceabi
BINUTILS=binutils-2.43
GCC=gcc-13.3.0
J="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

mkdir -p "$WORK/src" "$WORK/build"
cd "$WORK/src"

[ -d "$BINUTILS" ] || {
    curl -fL -O "https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz"
    tar xf "$BINUTILS.tar.xz"
}

[ -d "$GCC" ] || {
    curl -fL -O "https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz"
    tar xf "$GCC.tar.xz"
}

echo "=== binutils ==="
mkdir -p "$WORK/build/binutils"
cd "$WORK/build/binutils"
"$WORK/src/$BINUTILS/configure" \
    --target=$TARGET --prefix="$PREFIX" \
    --disable-nls --disable-werror --disable-gdb --disable-sim \
    --disable-readline --disable-libdecnumber \
    --with-system-zlib --disable-gprofng
make -j"$J"
make install

echo "=== gcc (stage 1, C only) ==="
GMP=""; MPFR=""; MPC=""
if [ -d /opt/homebrew/opt/gmp ]; then
    GMP="--with-gmp=/opt/homebrew/opt/gmp"
    MPFR="--with-mpfr=/opt/homebrew/opt/mpfr"
    MPC="--with-mpc=/opt/homebrew/opt/libmpc"
fi

mkdir -p "$WORK/build/gcc"
cd "$WORK/build/gcc"
"$WORK/src/$GCC/configure" \
    --target=$TARGET --prefix="$PREFIX" \
    --enable-languages=c \
    --without-headers --with-newlib \
    --disable-nls --disable-shared --disable-threads \
    --disable-libssp --disable-libgomp --disable-libquadmath \
    --disable-libatomic --disable-libstdcxx \
    --with-system-zlib $GMP $MPFR $MPC
make -j"$J" all-gcc
make install-gcc

echo
echo "Toolchain installed in $PREFIX/bin"
"$PREFIX/bin/$TARGET-gcc" --version | head -1
echo "Add it to PATH:  export PATH=$PREFIX/bin:\$PATH"
