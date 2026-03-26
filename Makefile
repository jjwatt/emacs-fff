# Makefile — build and install fff.el + dependencies
#
# PREREQUISITES (install these yourself before running make):
#   Rust + cargo   https://rustup.rs
#   Emacs 28.1+    with dynamic module support (--with-modules)
#   C compiler     gcc or clang
#   make, git
#
#   Fedora/RHEL:   sudo dnf install libtool-ltdl-devel
#   Debian/Ubuntu: sudo apt install libltdl-dev
#   macOS:         brew install libtool
#
# USAGE
#   make            — build everything
#   make install    — build + install to INSTALL_DIR
#   make check      — verify prerequisites
#   make clean      — remove build artefacts (keeps installed files)
#   make uninstall  — remove installed files

# ──────────────────────────────────────────────────────────────────
# Configuration — override on the command line if needed
#   make INSTALL_DIR=~/.config/emacs/fff

INSTALL_DIR     ?= $(HOME)/.emacs.local/emacs-fff
EMACS           ?= emacs
CARGO           ?= cargo
GIT             ?= git

FFF_NVIM_REPO   ?= https://github.com/dmtrKovalenko/fff.nvim
EMACS_FFI_REPO  ?= https://github.com/tromey/emacs-ffi

BUILD_DIR       := $(CURDIR)/.build
FFF_NVIM_DIR    := $(BUILD_DIR)/fff.nvim
EMACS_FFI_DIR   := $(BUILD_DIR)/emacs-ffi

# ──────────────────────────────────────────────────────────────────
# Platform detection

OS := $(shell uname -s)

ifeq ($(OS),Darwin)
  LIB_EXT      := dylib
  LIBFFF_C     := libfff_c.$(LIB_EXT)
  LDCONFIG_CMD := true
else
  LIB_EXT      := so
  LIBFFF_C     := libfff_c.$(LIB_EXT)
  LDCONFIG_CMD := true
endif

EMACS_FFI_MODULE := ffi-module.$(LIB_EXT)

# ──────────────────────────────────────────────────────────────────
# Top-level targets

.PHONY: all install check clean uninstall help

all: check \
     $(BUILD_DIR)/$(EMACS_FFI_MODULE) \
     $(BUILD_DIR)/$(LIBFFF_C)
	@echo ""
	@echo "Build complete. Run 'make install' to install to $(INSTALL_DIR)"

install: all
	@echo "==> Installing to $(INSTALL_DIR)"
	@mkdir -p "$(INSTALL_DIR)"
	cp fff.el                              "$(INSTALL_DIR)/fff.el"
	cp fff-helm.el                         "$(INSTALL_DIR)/fff-helm.el"
	cp "$(EMACS_FFI_DIR)/ffi.el"           "$(INSTALL_DIR)/ffi.el"
	cp "$(BUILD_DIR)/$(EMACS_FFI_MODULE)"  "$(INSTALL_DIR)/$(EMACS_FFI_MODULE)"
	cp "$(BUILD_DIR)/$(LIBFFF_C)"          "$(INSTALL_DIR)/$(LIBFFF_C)"
	@# Patch ffi.el: remove the (module-load "ffi-module") call it contains.
	@# emacs-ffi's ffi.el calls module-load with a bare name which doesn't
	@# work reliably. We load the .so by absolute path in init.el before
	@# (require 'ffi), so ffi.el must not try to load it again.
	sed -i.bak 's|(module-load "ffi-module.so")|;; module-load handled in init.el|' \
	  "$(INSTALL_DIR)/ffi.el"
	rm -f "$(INSTALL_DIR)/ffi.el.bak"
	@# Generate a wrapper script that sets LD_LIBRARY_PATH and launches Emacs.
	@# This is the most reliable way to ensure libfff_c.so is found by libltdl
	@# at dlopen time — LD_LIBRARY_PATH must be set before Emacs starts, not
	@# from within init.el (setenv inside Emacs is too late for dlopen).
	@echo "==> Generating emacs-fff wrapper script"
	@printf '#!/bin/sh\nexport LD_LIBRARY_PATH="$(INSTALL_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"\nexec emacs "$$@"\n' \
	  > "$(INSTALL_DIR)/emacs-fff"
	@chmod +x "$(INSTALL_DIR)/emacs-fff"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Installation complete!"
	@echo ""
	@echo "OPTION 1 — Launch Emacs via the wrapper script (recommended):"
	@echo ""
	@echo "  $(INSTALL_DIR)/emacs-fff"
	@echo ""
	@echo "  You can symlink this to ~/bin/emacs-fff or add it to your"
	@echo "  desktop launcher / .desktop file."
	@echo ""
	@echo "OPTION 2 — Set LD_LIBRARY_PATH in your shell before launching Emacs:"
	@echo ""
	@echo "  Add to ~/.profile or ~/.bash_profile:"
	@echo "  export LD_LIBRARY_PATH=\"$(INSTALL_DIR):\$$LD_LIBRARY_PATH\""
	@echo ""
	@echo "Then add this to your init.el:"
	@echo ""
	@echo "  ;; fff — fuzzy file finder"
	@echo "  (add-to-list 'load-path \"$(INSTALL_DIR)\")"
	@echo "  (module-load (expand-file-name \"$(INSTALL_DIR)/$(EMACS_FFI_MODULE)\"))"
	@echo "  (require 'fff-helm)  ; or fff-consult, fff-ivy, or just fff"
	@echo "  (global-set-key (kbd \"C-c f f\") #'fff-find-file)"
	@echo "  (global-set-key (kbd \"C-c f g\") #'fff-grep)"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ──────────────────────────────────────────────────────────────────
# Prerequisite check

check:
	@echo "==> Checking prerequisites"
	@command -v $(EMACS) >/dev/null 2>&1 || \
	  { echo "ERROR: emacs not found. Install Emacs 28.1+ with --with-modules."; exit 1; }
	@$(EMACS) -Q --batch --eval \
	  "(unless (fboundp 'module-load) \
	     (message \"ERROR: Emacs was built without dynamic module support\") \
	     (kill-emacs 1))" || exit 1
	@command -v $(CARGO) >/dev/null 2>&1 || \
	  { echo "ERROR: cargo not found. Install Rust from https://rustup.rs"; exit 1; }
	@command -v $(GIT) >/dev/null 2>&1 || \
	  { echo "ERROR: git not found."; exit 1; }
	@command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || \
	  command -v clang >/dev/null 2>&1 || \
	  { echo "ERROR: no C compiler found. Install gcc or clang."; exit 1; }
	@echo "#include <ltdl.h>" | cc -x c - -c -o /dev/null 2>/dev/null || \
	  { echo ""; \
	    echo "ERROR: ltdl headers not found."; \
	    echo "  Fedora/RHEL:   sudo dnf install libtool-ltdl-devel"; \
	    echo "  Debian/Ubuntu: sudo apt install libltdl-dev"; \
	    echo "  macOS:         brew install libtool"; \
	    echo ""; exit 1; }
	@echo "  [ok] emacs"
	@echo "  [ok] cargo"
	@echo "  [ok] git"
	@echo "  [ok] C compiler"
	@echo "  [ok] ltdl headers"

# ──────────────────────────────────────────────────────────────────
# emacs-ffi

$(EMACS_FFI_DIR)/.git:
	@echo "==> Cloning emacs-ffi"
	@mkdir -p "$(BUILD_DIR)"
	$(GIT) clone --depth=1 "$(EMACS_FFI_REPO)" "$(EMACS_FFI_DIR)"

$(BUILD_DIR)/$(EMACS_FFI_MODULE): $(EMACS_FFI_DIR)/.git
	@echo "==> Building emacs-ffi ($(EMACS_FFI_MODULE))"
	@# Do not pass CFLAGS or LDFLAGS — emacs-ffi handles its own -shared
	@# linking and passing LDFLAGS causes "undefined reference to main".
	$(MAKE) -C "$(EMACS_FFI_DIR)" EMACS="$(EMACS)"
	cp "$(EMACS_FFI_DIR)/$(EMACS_FFI_MODULE)" "$(BUILD_DIR)/$(EMACS_FFI_MODULE)"

# ──────────────────────────────────────────────────────────────────
# libfff_c

$(FFF_NVIM_DIR)/.git:
	@echo "==> Cloning fff.nvim"
	@mkdir -p "$(BUILD_DIR)"
	$(GIT) clone --depth=1 "$(FFF_NVIM_REPO)" "$(FFF_NVIM_DIR)"

$(BUILD_DIR)/$(LIBFFF_C): $(FFF_NVIM_DIR)/.git
	@echo "==> Building libfff_c (this may take a while)"
	$(CARGO) build --release \
	  --manifest-path "$(FFF_NVIM_DIR)/Cargo.toml" \
	  -p fff-c
	cp "$(FFF_NVIM_DIR)/target/release/$(LIBFFF_C)" \
	   "$(BUILD_DIR)/$(LIBFFF_C)"

# ──────────────────────────────────────────────────────────────────
# Housekeeping

clean:
	@echo "==> Removing build directory"
	rm -rf "$(BUILD_DIR)"

uninstall:
	@echo "==> Removing $(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)"

help:
	@echo "Targets:"
	@echo "  make          — check prerequisites and build everything"
	@echo "  make install  — build + install to INSTALL_DIR"
	@echo "  make check    — verify prerequisites only"
	@echo "  make clean    — remove .build/ directory"
	@echo "  make uninstall — remove INSTALL_DIR"
	@echo ""
	@echo "Variables (override on command line):"
	@echo "  INSTALL_DIR   default: $(HOME)/.emacs.local/emacs-fff"
	@echo "  EMACS         default: emacs"
	@echo "  CARGO         default: cargo"
