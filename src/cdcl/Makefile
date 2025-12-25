CXX = g++
CXXFLAGS = -O3 -std=c++11 -fPIC
INCLUDES = -I../../deps/cadical/src
LIBS = ../../deps/cadical/build/libcadical.a
OUTPUT = ../../deps/cadical/build/libcadical_mine.dylib
TARGET_OS := $(shell uname -s)

ifeq ($(TARGET_OS), Darwin)
	LDFLAGS = -dynamiclib
else
	LDFLAGS = -shared
	OUTPUT = ../../deps/cadical/build/libcadical_mine.so
endif

.PHONY: all clean

all: $(OUTPUT)

$(OUTPUT): my_cadical.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(LDFLAGS) -o $@ $< $(LIBS)

clean:
	rm -f $(OUTPUT)
