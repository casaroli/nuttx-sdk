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

# A shared library and a module that uses it.
#
# The library is built exactly like a module except that it has no entry
# point and is named by its SONAME, which is what the consumer records in
# DT_NEEDED and what the loader searches for at run time.

NUTTX_DIR ?= $(error set NUTTX_DIR)
SDK       := ../..

all: libcounter.so user.fdpic

libcounter.so: libcounter.c
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=libcounter SRCS=libcounter.c \
	    NUTTX_DIR=$(NUTTX_DIR) ENTRY=0 \
	    EXTRA_LDFLAGS="-soname libcounter.so"
	mv libcounter.fdpic libcounter.so

user.fdpic: user.c libcounter.so
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=user SRCS=user.c \
	    NUTTX_DIR=$(NUTTX_DIR) LIBS=libcounter.so

clean:
	rm -f *.o *.fdpic *.so .nuttx-exports
