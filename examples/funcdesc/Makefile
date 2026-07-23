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

# A module that exercises R_ARM_FUNCDESC.
#
# Built the ordinary way -- there is nothing special about the link.  What
# makes it different is the source: it takes the *address* of imported
# functions, which is what makes the linker ask the loader to manufacture
# descriptors rather than laying them out itself.

NUTTX_DIR ?= $(error set NUTTX_DIR)
SDK       := ../..

all: funcdesc.fdpic

funcdesc.fdpic: funcdesc.c
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=funcdesc SRCS=funcdesc.c \
	    NUTTX_DIR=$(NUTTX_DIR)

clean:
	rm -f *.o *.fdpic .nuttx-exports
