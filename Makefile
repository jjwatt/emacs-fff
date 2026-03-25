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
#   macOS:         brew install libtool   (provides ltdl)
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
  LIB_EXT       := dylib
  LIB_PREFIX    := lib
  LTDL_CFLAGS   := $(shell pkg-config --cflags libltdl 2>/dev/null || echo "-I/usr/local/include")
  LTDL_LIBS     := $(shell pkg-config --libs   libltdl 2>/dev/null || echo "-L/usr/local/lib -lltdl")
  LIBFFF_C      := $(LIB_PREFIX)fff_c.$(LIB_EXT)
  LDCONFIG_CMD  := true   # no ldconfig on macOS
else
  LIB_EXT       := so
  LIB_PREFIX    := lib
  LTDL_CFLAGS   := $(shell pkg-config --cflags libltdl 2>/dev/null || echo "")
  LTDL_LIBS     := $(shell pkg-config --libs   libltdl 2>/dev/null || echo "-lltdl")
  LIBFFF_C      := $(LIB_PREFIX)fff_c.$(LIB_EXT)
  LDCONFIG_CMD  := ldconfig $(INSTALL_DIR) 2>/dev/null || true
endif

EMACS_FFI_MODULE := ffi-module.$(LIB_EXT)

# ──────────────────────────────────────────────────────────────────
# Emacs compile flags

EMACS_CFLAGS := $(shell $(EMACS) -Q --batch \
  --eval "(princ (mapconcat #'identity \
    (list (format \"-I%s\" (expand-file-name \"../include\" invocation-directory)) \
          \"-I/usr/include\" \"-I/usr/local/include\") \
    \" \"))" 2>/dev/null)

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
	cp fff.el          "$(INSTALL_DIR)/fff.el"
	cp fff-helm.el     "$(INSTALL_DIR)/fff-helm.el"
	cp "$(EMACS_FFI_DIR)/ffi.el"         "$(INSTALL_DIR)/ffi.el"
	cp "$(BUILD_DIR)/$(EMACS_FFI_MODULE)" "$(INSTALL_DIR)/$(EMACS_FFI_MODULE)"
	cp "$(BUILD_DIR)/$(LIBFFF_C)"         "$(INSTALL_DIR)/$(LIBFFF_C)"
	@$(LDCONFIG_CMD)
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Installation complete!"
	@echo ""
	@echo "Add this to your init.el:"
	@echo ""
	@echo "  ;; fff — fuzzy file finder"
	@echo "  (add-to-list 'load-path \"$(INSTALL_DIR)\")"
	@echo "  (setenv \"LD_LIBRARY_PATH\""
	@echo "          (concat \"$(INSTALL_DIR):\" (getenv \"LD_LIBRARY_PATH\")))"
	@echo "  (load \"$(INSTALL_DIR)/ffi-module\")"
	@echo "  (require 'fff-helm)  ; or fff-consult, fff-ivy, or fff"
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
	  "(unless (fboundp 'module-load) (message \"ERROR: Emacs was built without dynamic module support (--with-modules)\") (kill-emacs 1))" || exit 1
	@command -v $(CARGO) >/dev/null 2>&1 || \
	  { echo "ERROR: cargo not found. Install Rust from https://rustup.rs"; exit 1; }
	@command -v $(GIT) >/dev/null 2>&1 || \
	  { echo "ERROR: git not found."; exit 1; }
	@command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 || \
	  { echo "ERROR: no C compiler found. Install gcc or clang."; exit 1; }
	@# Check for ltdl headers
	@echo "#include <ltdl.h>" | cc -x c - -c -o /dev/null $(LTDL_CFLAGS) 2>/dev/null || \
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
	$(MAKE) -C "$(EMACS_FFI_DIR)" \
	  EMACS="$(EMACS)" \
	  CFLAGS="$(LTDL_CFLAGS) $(EMACS_CFLAGS)" \
	  LDFLAGS="$(LTDL_LIBS)"
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
	@echo "Variables:"
	@echo "  INSTALL_DIR   default: $(HOME)/.emacs.local/emacs-fff"
	@echo "  EMACS         default: emacs"
	@echo "  CARGO         default: cargo"
