CXX ?= g++
CXXFLAGS ?= -O2 -fPIC -std=c++11 -DEASYSAT_NO_MAIN

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
SHARED_EXT := dylib
SHARED_FLAG := -dynamiclib
else
SHARED_EXT := so
SHARED_FLAG := -shared
endif

TARGET := libeasysat.$(SHARED_EXT)
SRCS := EasySAT.cpp
OBJS := $(SRCS:.cpp=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(SHARED_FLAG) -o $@ $(OBJS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)
