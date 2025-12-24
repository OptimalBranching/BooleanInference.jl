# BooleanInference Makefile
# This Makefile handles building the CaDiCaL dependency and the custom library

.PHONY: all submodule cadical mylib clean clean-all help

# Default target
all: mylib

# Help message
help:
	@echo "Available targets:"
	@echo "  all        - Build everything (default)"
	@echo "  submodule  - Initialize and update git submodules"
	@echo "  cadical    - Build the CaDiCaL library"
	@echo "  mylib      - Build the custom CaDiCaL wrapper library"
	@echo "  clean      - Clean the custom library"
	@echo "  clean-all  - Clean everything including CaDiCaL build"

# Update git submodules
submodule:
	git submodule update --init --recursive

# Build CaDiCaL
cadical: submodule
	@echo "Building CaDiCaL..."
	cd deps/cadical && CXXFLAGS="-fPIC" ./configure && make -j4

# Build the custom library (depends on CaDiCaL)
mylib: cadical
	@echo "Building custom CaDiCaL wrapper..."
	$(MAKE) -C src/cdcl

# Clean custom library only
clean:
	$(MAKE) -C src/cdcl clean

# Clean everything
clean-all: clean
	@echo "Cleaning CaDiCaL build..."
	cd deps/cadical && make clean 2>/dev/null || true
	rm -rf deps/cadical/build
