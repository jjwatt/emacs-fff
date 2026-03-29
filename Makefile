# Makefile — build and install fff.el + dependencies
#
# PREREQUISITES (install these yourself before running make):
#   Rust + cargo   https://rustup.rs
#   Emacs 28.1+    with dynamic module support (--with-modules)
#   C compiler     gcc or clang
#   make, git
#
#   Fedora/RHEL:   sudo dnf install libtool-ltdl-devel libffi-devel
#   Debian/Ubuntu: sudo apt install libltdl-dev libffi-dev
#   macOS:         brew install libtool libffi
#
# USAGE
#   make           — build everything
#   make install   — build + install to INSTALL_DIR
#   make check     — verify prerequisites
#   make clean     — remove build artefacts (keeps installed files)
#   make uninstall — remove installed files
#
# OVERRIDES
#   make INSTALL_DIR=~/.config/emacs/fff
#   make EMACS_INCLUDE=/path/to/dir/containing/emacs-module.h

# ──────────────────────────────────────────────────────────────────
# Configuration

INSTALL_DIR    ?= $(HOME)/.emacs.local/emacs-fff
EMACS          ?= emacs
CARGO          ?= cargo
GIT            ?= git

FFF_NVIM_REPO  ?= https://github.com/dmtrKovalenko/fff.nvim

# Path to your vendored emacs-ffi directory
VENDORED_FFI_DIR := $(CURDIR)/emacs-ffi

BUILD_DIR      := $(CURDIR)/.build
FFF_NVIM_DIR   := $(BUILD_DIR)/fff.nvim

# ──────────────────────────────────────────────────────────────────
# Platform detection

OS := $(shell uname -s)

ifeq ($(OS),Darwin)
  LIB_EXT      := dylib
  LIBFFF_C     := libfff_c.$(LIB_EXT)
  LDCONFIG_CMD := true
  SHARED_FLAG  := -dynamiclib

  # Homebrew prefix — Apple Silicon uses /opt/homebrew, Intel uses /usr/local
  HOMEBREW_PREFIX := $(shell brew --prefix 2>/dev/null || \
    { test -d /opt/homebrew && echo /opt/homebrew || echo /usr/local; })

  LTDL_PREFIX  := $(shell brew --prefix libtool 2>/dev/null || \
    echo "$(HOMEBREW_PREFIX)/opt/libtool")
  LIBFFI_PREFIX := $(shell brew --prefix libffi 2>/dev/null || \
    echo "$(HOMEBREW_PREFIX)/opt/libffi")

  LTDL_CFLAGS  := -I$(LTDL_PREFIX)/include
  LTDL_LIBS    := -L$(LTDL_PREFIX)/lib -lltdl
  LIBFFI_CFLAGS := -I$(LIBFFI_PREFIX)/include
  LIBFFI_LIBS  := -L$(LIBFFI_PREFIX)/lib -lffi

else
  LIB_EXT      := so
  LIBFFF_C     := libfff_c.$(LIB_EXT)
  LDCONFIG_CMD := true
  SHARED_FLAG  := -shared

  LTDL_CFLAGS  := $(shell pkg-config --cflags libltdl 2>/dev/null || echo "")
  LTDL_LIBS    := $(shell pkg-config --libs   libltdl 2>/dev/null || echo "-lltdl")
  LIBFFI_CFLAGS := $(shell pkg-config --cflags libffi  2>/dev/null || echo "")
  LIBFFI_LIBS  := $(shell pkg-config --libs   libffi  2>/dev/null || echo "-lffi")
endif

EMACS_FFI_MODULE := ffi-module.$(LIB_EXT)

# ──────────────────────────────────────────────────────────────────
# Locate emacs-module.h

ifndef EMACS_INCLUDE
  ifeq ($(OS),Darwin)
    EMACS_INCLUDE := $(shell \
      find "$(HOMEBREW_PREFIX)/Cellar/emacs" \
           "$(HOMEBREW_PREFIX)/Cellar/emacs-plus"* \
           "$(HOMEBREW_PREFIX)/Cellar/emacs-mac"* \
           /Applications \
           -name "emacs-module.h" 2>/dev/null | \
      head -1 | xargs -I{} dirname {})
  else
    EMACS_INCLUDE := $(shell \
      find /usr/include /usr/local/include \
           -name "emacs-module.h" 2>/dev/null | \
      head -1 | xargs -I{} dirname {})
  endif
  ifeq ($(EMACS_INCLUDE),)
    # Last resort: ask Emacs where it lives and search nearby
    EMACS_INCLUDE := $(shell \
      dir=$$($(EMACS) -Q --batch \
               --eval "(princ invocation-directory)" 2>/dev/null); \
      find "$$dir" "$$dir/.." "$$dir/../include" "$$dir/../../include" \
           -name "emacs-module.h" 2>/dev/null | \
      head -1 | xargs -I{} dirname {})
  endif
endif

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
	cp fff-ivy.el                          "$(INSTALL_DIR)/fff-ivy.el"
	cp fff-consult.el                      "$(INSTALL_DIR)/fff-consult.el"
	cp "$(VENDORED_FFI_DIR)/ffi.el"        "$(INSTALL_DIR)/ffi.el"
	cp "$(BUILD_DIR)/$(EMACS_FFI_MODULE)"  "$(INSTALL_DIR)/$(EMACS_FFI_MODULE)"
	cp "$(BUILD_DIR)/$(LIBFFF_C)"          "$(INSTALL_DIR)/$(LIBFFF_C)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Installation complete!"

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
	@echo "#include <ltdl.h>" | cc -x c - -c -o /dev/null $(LTDL_CFLAGS) 2>/dev/null || \
	  { echo ""; \
	    echo "ERROR: ltdl headers not found."; \
	    echo "  Fedora/RHEL:   sudo dnf install libtool-ltdl-devel"; \
	    echo "  Debian/Ubuntu: sudo apt install libltdl-dev"; \
	    echo "  macOS:         brew install libtool"; \
	    echo ""; exit 1; }
	@echo "#include <ffi.h>" | cc -x c - -c -o /dev/null $(LIBFFI_CFLAGS) 2>/dev/null || \
	  { echo ""; \
	    echo "ERROR: libffi headers not found."; \
	    echo "  Fedora/RHEL:   sudo dnf install libffi-devel"; \
	    echo "  Debian/Ubuntu: sudo apt install libffi-dev"; \
	    echo "  macOS:         brew install libffi"; \
	    echo ""; exit 1; }
	@test -n "$(EMACS_INCLUDE)" || \
	  { echo ""; \
	    echo "ERROR: emacs-module.h not found."; \
	    echo "  This file ships with Emacs itself."; \
	    echo "  Find it: find / -name emacs-module.h 2>/dev/null"; \
	    echo "  Then:    make EMACS_INCLUDE=/path/to/dir/containing/it"; \
	    echo ""; exit 1; }
	@test -d "$(VENDORED_FFI_DIR)" || \
	  { echo "ERROR: Vendored emacs-ffi directory not found at $(VENDORED_FFI_DIR)"; exit 1; }
	@echo "  [ok] emacs"
	@echo "  [ok] cargo"
	@echo "  [ok] git"
	@echo "  [ok] C compiler"
	@echo "  [ok] ltdl headers"
	@echo "  [ok] libffi headers"
	@echo "  [ok] emacs-module.h ($(EMACS_INCLUDE))"
	@echo "  [ok] vendored emacs-ffi"

# ──────────────────────────────────────────────────────────────────
# emacs-ffi (Vendored)

$(BUILD_DIR)/$(EMACS_FFI_MODULE): $(VENDORED_FFI_DIR)/ffi-module.c
	@echo "==> Building vendored ffi-module"
	@mkdir -p "$(BUILD_DIR)"
	cc -g -fPIC $(SHARED_FLAG) \
	  -I"$(EMACS_INCLUDE)" \
	  $(LTDL_CFLAGS) \
	  $(LIBFFI_CFLAGS) \
	  -o "$@" \
	  "$(VENDORED_FFI_DIR)/ffi-module.c" \
	  $(LTDL_LIBS) \
	  $(LIBFFI_LIBS)
ifeq ($(OS),Darwin)
	@echo "==> Patching macOS dynamic library links for ffi-module"
	install_name_tool -id "@loader_path/$(EMACS_FFI_MODULE)" "$@"
endif

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
	cp "$(FFF_NVIM_DIR)/target/release/$(LIBFFF_C)" "$@"
ifeq ($(OS),Darwin)
	@echo "==> Patching macOS dynamic library links for libfff_c"
	install_name_tool -id "@loader_path/$(LIBFFF_C)" "$@"
endif

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
	@echo "  make            — check prerequisites and build everything"
	@echo "  make install    — build + install to INSTALL_DIR"
	@echo "  make clean      — remove .build/ directory"
