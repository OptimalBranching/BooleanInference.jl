# === common settings ===
JOBS ?= $(shell nproc 2>/dev/null || echo 4)
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OUTDIR := $(ROOT)/../artifacts/bin
DATADIR := $(ROOT)/../data
mkdir_p = mkdir -p $1
CMAKE_BUILD_DIR := $(ROOT)/x-sat/build

# === abc (berkeley-abc) ===
ABC_DIR := $(ROOT)/abc
ABC_BIN := $(ABC_DIR)/abc
ABC_LIB := $(ABC_DIR)/libabc.a

.PHONY: all aiger x-sat aig-data yosys kissat abc libabc submodule-abc submodule-cir_bench iscas85 clean distclean

all: aiger x-sat abc aig-data yosys iscas85
	@echo "✅ All third-party benchmarks built."
	@echo "Executables are under $(OUTDIR)"
	@echo "AIG data is under $(DATADIR)/aig"
	@echo "ISCAS85 is under $(DATADIR)/iscas85"

# === aiger ===
aiger:
	@echo ">>> Building aiger..."
	@if [ ! -f "$(ROOT)/aiger/Makefile" ]; then \
		echo ">>> Configuring aiger (generating Makefile)..."; \
		cd $(ROOT)/aiger && ./configure.sh; \
	fi
	$(MAKE) -C $(ROOT)/aiger -j$(JOBS)
	$(call mkdir_p,$(OUTDIR))
	cd $(ROOT)/aiger && \
	find . -maxdepth 1 -type f \( -perm -u+x -o -perm -g+x -o -perm -o+x \) \
		-exec cp -f {} $(OUTDIR)/ \;
	@echo "✓ Aiger tools copied to $(OUTDIR)"

	# for f in aigand aigdd aigflip aigfuzz aiginfo aigjoin aigmiter aigmove aignm aigor aigreset aigselect \
	#          aigsim aigsplit aigstrip aigtoaig aigtoblif aigtocnf aigtobtor aigtodot aigtosmv \
	#          aigunconstraint aigunor aigunroll andtoaig bliftoaig smvtoaig soltostim wrapstim; do \
	#   [ -x "$(AIGER_DIR)/$$f" ] && cp -f "$(AIGER_DIR)/$$f" "$(OUTDIR)/"; \
	# done

# === x-sat ===
x-sat:
	@echo ">>> Building x-sat..."
	$(call mkdir_p,$(CMAKE_BUILD_DIR))
	cd $(CMAKE_BUILD_DIR) && cmake \
	    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	    -DCMAKE_BUILD_TYPE=Release \
	    .. 
	$(MAKE) -C $(CMAKE_BUILD_DIR) -j$(JOBS)
	$(call mkdir_p,$(OUTDIR))
	@if [ -f "$(CMAKE_BUILD_DIR)/csat" ]; then \
	    cp $(CMAKE_BUILD_DIR)/csat $(OUTDIR)/; \
	else \
	    echo "⚠️  Warning: x-sat executable not found, adjust path."; \
	fi

aig-data: aiger
	@echo ">>> Converting and copying AIG data..."
	@if [ -d "$(ROOT)/x-sat/data/airthmetic" ]; then \
		mkdir -p "$(DATADIR)/aig/arithmetic"; \
		for f in "$(ROOT)"/x-sat/data/airthmetic/*.aiger; do \
			if [ -e "$$f" ]; then \
				base=$$(basename "$$f" .aiger); \
				out="$(DATADIR)/aig/arithmetic/$$base.aag"; \
				echo "Converting $$f -> $$out"; \
				"$(OUTDIR)/aigtoaig" -a "$$f" > "$$out"; \
			fi; \
		done; \
	else \
		echo "Warning: $(ROOT)/x-sat/data/airthmetic not found"; \
	fi
	@if [ -d "$(ROOT)/x-sat/data/non-airthmetic" ]; then \
		mkdir -p "$(DATADIR)/aig/non-arithmetic"; \
		for f in "$(ROOT)"/x-sat/data/non-airthmetic/*.aiger; do \
			if [ -e "$$f" ]; then \
				base=$$(basename "$$f" .aiger); \
				out="$(DATADIR)/aig/non-arithmetic/$$base.aag"; \
				echo "Converting $$f -> $$out"; \
				"$(OUTDIR)/aigtoaig" -a "$$f" > "$$out"; \
			fi; \
		done; \
	fi
	@echo "AIG data converted and copied to $(DATADIR)/aig"

yosys:
	@echo ">>> Installing yosys..."
	@if command -v brew >/dev/null 2>&1; then \
		echo "Detected macOS — using Homebrew"; \
		brew install yosys || brew upgrade yosys; \
	elif command -v apt >/dev/null 2>&1; then \
		echo "Detected Ubuntu/Debian — using apt"; \
		sudo apt update && sudo apt install -y yosys; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "Detected Fedora/RHEL — using dnf"; \
		sudo dnf install -y yosys; \
	elif command -v pacman >/dev/null 2>&1; then \
		echo "Detected Arch Linux — using pacman"; \
		sudo pacman -S --noconfirm yosys; \
	else \
		echo "No known package manager found; please install Yosys manually from source."; \
	fi
	@echo "✓ Yosys installation complete."

kissat:
	@echo ">>> Installing kissat..."
	@if command -v brew >/dev/null 2>&1; then \
		echo "Detected macOS — using Homebrew"; \
		brew install kissat || brew upgrade kissat; \
	elif command -v apt >/dev/null 2>&1; then \
		echo "Detected Ubuntu/Debian — using apt"; \
		sudo apt update && sudo apt install -y kissat; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "Detected Fedora/RHEL — using dnf"; \
		sudo dnf install -y kissat; \
	elif command -v pacman >/dev/null 2>&1; then \
		echo "Detected Arch Linux — using pacman"; \
		sudo pacman -S --noconfirm kissat; \
	else \
		echo "No known package manager found; please install Kissat manually from source."; \
	fi
	@echo "✓ Kissat installation complete."

# === abc ===
abc: submodule-abc
	@echo ">>> Building abc (berkeley-abc)..."
	$(MAKE) -C $(ABC_DIR) -j$(JOBS)
	$(call mkdir_p,$(OUTDIR))
	@if [ -f "$(ABC_BIN)" ]; then \
		cp -f "$(ABC_BIN)" "$(OUTDIR)/"; \
		echo "✓ abc copied to $(OUTDIR)"; \
	else \
		echo "⚠️  Warning: abc executable not found at $(ABC_BIN)"; \
	fi

# optional: build PIC static library for downstream linking
libabc: submodule-abc
	@echo ">>> Building libabc.a (PIC) ..."
	$(MAKE) -C $(ABC_DIR) -j$(JOBS) libabc.a ABC_USE_PIC=1
	$(call mkdir_p,$(OUTDIR))
	@if [ -f "$(ABC_LIB)" ]; then \
		cp -f "$(ABC_LIB)" "$(OUTDIR)/"; \
		echo "✓ libabc.a copied to $(OUTDIR)"; \
	else \
		echo "⚠️  Warning: libabc.a not found at $(ABC_LIB)"; \
	fi

# ensure the submodule is initialized
submodule-abc:
	@git submodule update --init --recursive $(ABC_DIR)

# === copy ISCAS85 ===
CIR_BENCH_DIR := $(ROOT)/cir_bench

iscas85: submodule-cir_bench
	@echo ">>> Copying ISCAS85..."
	cp -r $(ROOT)/cir_bench/ISCAS85 $(DATADIR)/iscas85
	@echo "✓ ISCAS85 copied to $(DATADIR)/iscas85"

submodule-cir_bench:
	@git submodule update --init --recursive $(CIR_BENCH_DIR)
	@echo "✓ cir_bench submodule initialized"

# === clean ===
clean:
	@echo ">>> Cleaning..."
	cd $(ROOT)/aiger && $(MAKE) clean || true
	cd $(ABC_DIR) && $(MAKE) clean || true
	rm -rf $(CMAKE_BUILD_DIR)
	rm -rf $(OUTDIR)

distclean: clean
	- git -C $(ABC_DIR) clean -xfd || true
	- git -C $(ROOT)/aiger clean -xfd || true