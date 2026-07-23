# A C++ shared library and a C++ module that uses it.
#
# Same shape as examples/shared, in C++: the library has no entry point and
# is named by its SONAME, which is what the consumer records in DT_NEEDED
# and what the loader searches for at run time.
#
# The compiler here is the stock arm-none-eabi-g++, not the FDPIC
# toolchain, which has no C++ compiler.  Only the link is FDPIC.  See the
# CXX block in nuttx-fdpic.mk.

NUTTX_DIR ?= $(error set NUTTX_DIR)
SDK       := ../..

all: libshape.so cxxuser.fdpic

libshape.so: libshape.cpp
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=libshape CXXSRCS=libshape.cpp \
	    NUTTX_DIR=$(NUTTX_DIR) ENTRY=0 \
	    EXTRA_LDFLAGS="-soname libshape.so"
	mv libshape.fdpic libshape.so

cxxuser.fdpic: user.cpp libshape.so
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=cxxuser CXXSRCS=user.cpp \
	    NUTTX_DIR=$(NUTTX_DIR) LIBS=libshape.so

clean:
	rm -f *.o *.fdpic *.so .nuttx-exports
