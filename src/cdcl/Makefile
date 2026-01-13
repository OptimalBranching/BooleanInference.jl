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

SRCS = my_cadical.cpp ../../deps/cadical/contrib/cadical_assumptions.cpp

$(OUTPUT): $(SRCS)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(LDFLAGS) -o $@ $(SRCS) $(LIBS)

clean:
	rm -f $(OUTPUT)
