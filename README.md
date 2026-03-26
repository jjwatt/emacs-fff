# fff.el

An Emacs frontend for [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim) — a fast, typo-resistant fuzzy file finder with frecency scoring, git status integration, and live grep. This package calls directly into `libfff_c.so`, the C FFI shared library from the fff.nvim project, using [tromey/emacs-ffi](https://github.com/tromey/emacs-ffi).

```
C-c f f  →  fuzzy file picker
C-c f g  →  live grep
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Emacs                                                      │
│                                                             │
│  fff.el          — FFI bindings, search, backend protocol   │
│  fff-helm.el     — Helm UI backend                          │
│                                                             │
│  emacs-ffi       — libffi bridge (tromey/emacs-ffi)         │
└──────────────────────────┬──────────────────────────────────┘
                           │  dlopen + C ABI
                           ▼
                ┌─────────────────────┐
                │   libfff_c.so       │
                │   (Rust, cdylib)    │
                ├─────────────────────┤
                │  • file index       │
                │  • fuzzy search     │
                │  • live grep        │
                │  • frecency LMDB    │
                │  • git status       │
                └─────────────────────┘
```

### Why direct FFI instead of a socket/process?

fff.nvim ships three consumer interfaces: a Neovim Lua module (`libfff_nvim.so`), an MCP server binary (`fff-mcp`), and a **C FFI shared library** (`libfff_c.so`) intended for any language with C FFI support — Bun, Node.js, Python, and now Emacs. The C library has a synchronous API with no async runtime, making it a natural fit for `emacs-ffi`'s `define-ffi-function`.

### Key API facts

- Every `fff_*` function returns `*mut FffResult` — a `repr(C)` envelope with `success`, `error`, `handle`, and `int_value` fields. The `fff--with-result` macro handles checking and freeing this automatically.
- Results are **not JSON** — they are `repr(C)` structs accessed via getter functions (`fff_search_result_get_item`, `fff_grep_result_get_match`). We read field values with `ffi--mem-ref` at computed byte offsets.
- The `FffInstance` is an opaque `void*` created by `fff_create_instance` and destroyed by `fff_destroy`. All other functions take this handle as their first argument.
- Memory is caller-managed: `fff_free_result` frees the envelope, `fff_free_search_result` / `fff_free_grep_result` free the payload, separately.

---

## Installation

### With Makefile

A `Makefile` is provided to make installation a little easier.

```shell
Targets:
  make          — check prerequisites and build everything
  make install  — build + install to INSTALL_DIR
  make check    — verify prerequisites only
  make clean    — remove .build/ directory
  make uninstall — remove INSTALL_DIR

Variables (override on command line):
  INSTALL_DIR   default: /home/jwatt/.emacs.local/emacs-fff
  EMACS         default: emacs
  CARGO         default: cargo
```

```bash
make
make install
```

### Manual

#### 1. Build `libfff_c.so`

```bash
git clone https://github.com/dmtrKovalenko/fff.nvim
cd fff.nvim
cargo build --release -p fff-c
# → target/release/libfff_c.so  (Linux)
# → target/release/libfff_c.dylib (macOS)
```

Or download the prebuilt `c-lib-{target}.so` from the [GitHub Releases](https://github.com/dmtrKovalenko/fff.nvim/releases) page.

#### 2. Make `libfff_c.so` findable

`libltdl` (used by emacs-ffi) searches `LD_LIBRARY_PATH` on Linux and `DYLD_LIBRARY_PATH` on macOS. The simplest approach:

```bash
# In your shell rc or Emacs launcher script:
export LD_LIBRARY_PATH="$HOME/git/fff.nvim/target/release:$LD_LIBRARY_PATH"
```

Or install system-wide:

```bash
sudo cp target/release/libfff_c.so /usr/local/lib/
sudo ldconfig
```

#### 3. Install `emacs-ffi`

```bash
git clone https://github.com/tromey/emacs-ffi
cd emacs-ffi
make
```

You may need to change `emacs-ffi/ffi.el` to load the ffi so module like this:

```elisp
;; (module-load "ffi-module.so")
(load "ffi-module")
```

At least, I had to change it like that. I put both `emacs-ffi` and `emacs-fff` in `~/.emacs.local` and add them both the load path.

#### 4. Install `fff.el`

Copy `fff.el` and `fff-helm.el` (or whichever backend you want) to a directory on your `load-path`.

#### 5. Configure

```elisp
;; Load the native ffi module first — must be an absolute path
(module-load "/path/to/emacs-ffi/ffi-module.so")
(add-to-list 'load-path "/path/to/emacs-ffi")

;; Add fff to load-path
(add-to-list 'load-path "/path/to/emacs-fff")

;; Load your chosen backend (sets fff-backend automatically)
(require 'fff-helm)    ; or fff-consult, fff-ivy, or just fff for default

;; Bind keys
(global-set-key (kbd "C-c f f") #'fff-find-file)
(global-set-key (kbd "C-c f g") #'fff-grep)
(global-set-key (kbd "C-c f w") #'fff-grep-word-at-point)
```

---

## Usage

| Command | Description |
|---|---|
| `M-x fff-find-file` | Fuzzy file picker for the current project |
| `M-x fff-grep` | Live grep (plain text by default) |
| `M-x fff-grep-word-at-point` | Grep for the word under the cursor |
| `M-x fff-change-directory` | Set a fallback root when outside a git repo |
| `M-x fff-refresh` | Trigger a rescan of the project tree |
| `M-x fff-refresh-git` | Refresh git status cache |
| `M-x fff-stop` | Destroy the fff instance and free memory |

### Project root detection

fff automatically uses the git root of the current buffer's directory, and switches automatically when you move to a buffer in a different git repo.

If you're outside a git repo, use `M-x fff-change-directory` to set a fallback root. This sets `fff-default-directory` which persists for the session. You can also set it permanently in your config:

```elisp
(setq fff-default-directory "~/projects/myrepo")
```

The resolution order is:

1. Git root of the current buffer (auto-detected)
2. `fff-default-directory` (set by `fff-change-directory`)
3. Error with a helpful message

---

## Configuration

```elisp
(setq fff-max-results    100)   ; max results returned per search
(setq fff-max-threads    0)     ; worker threads (0 = auto-detect)
(setq fff-smart-case     t)     ; case-insensitive when query is lowercase

;; Share frecency databases with the Neovim plugin for cross-editor scores
(setq fff-frecency-db-path "~/.cache/fff_nvim")
(setq fff-history-db-path  "~/.local/share/fff_queries")

;; Fallback root when outside a git project
(setq fff-default-directory nil) ; set to a path string to enable
```

---

## Backend system

fff.el separates the data layer (FFI calls, result collection) from the UI layer (completion framework). The active backend is set via `fff-backend`.

### Built-in backends

| File | Backend variable | Framework |
|---|---|---|
| `fff-helm.el` | `fff-backend-helm` | [helm](https://github.com/emacs-helm/helm) |
| *(built-in)* | `fff--make-default-backend` | `completing-read` |

Loading `fff-helm.el` automatically sets `fff-backend` to `fff-backend-helm`.

### Writing your own backend

A backend is a plist with two keys:

```elisp
(setq my-backend
  (list
   :pick-file
   (lambda (candidate-fn action-fn)
     ;; candidate-fn: (lambda (query) ...) → list of (display . plist)
     ;; action-fn:    (lambda (plist) ...)  — called with the chosen result
     ...)

   :pick-grep
   (lambda (candidate-fn action-fn)
     ...)))

(setq fff-backend my-backend)
```

The public functions your backend should call:

- `(fff-file-candidates QUERY)` → list of `(path . plist)` cons cells
- `(fff-grep-candidates QUERY)` → list of `("path:line:col  content" . plist)` cons cells
- `(fff-open-result PLIST)` → opens the file, records frecency

### Helm backend notes

The helm backend uses top-level `defun`s for `:candidates` rather than lambdas. This is required because helm evaluates candidate functions in a dynamic binding context where anonymous lambdas that reference other functions by name fail with `void-function`. The named functions `fff--helm-candidates` and `fff--helm-grep-candidates` are always findable by symbol lookup.

---

## Development

### Reloading after edits

`define-ffi-function` uses `defun` internally, so reloading with `load-file` won't rebind already-defined symbols. Use the provided reload helpers instead:

```elisp
;; Reload fff core (preserves fff-backend across reload)
M-x fff-reload

;; Reload helm backend
M-x fff-helm-reload
```

### Verifying the setup

```elisp
;; Check the library opened
(fff--lib)             ; should return a user-ptr

;; Check the instance
fff--instance          ; user-ptr after first fff-find-file
fff--current-base-path ; your project root

;; Check the backend
fff-backend            ; should be a plist, not nil
(featurep 'fff-helm)   ; t if using helm
(fboundp 'fff--helm-candidates) ; t if helm backend loaded correctly
```

### Struct offsets reference

The C struct layouts are documented in comments at the top of `fff.el`. The key offsets used for reading results:

| Struct | Field | Offset | Type |
|---|---|---|---|
| `FffResult` | `error` | 8 | `:pointer` |
| `FffResult` | `handle` | 16 | `:pointer` |
| `FffResult` | `int_value` | 24 | `:int64` |
| `FffFileItem` | `path` | 0 | `:pointer` |
| `FffFileItem` | `git_status` | 24 | `:pointer` |
| `FffSearchResult` | `count` | 16 | `:uint32` |
| `FffGrepResult` | `count` | 8 | `:uint32` |
| `FffGrepMatch` | `path` | 0 | `:pointer` |
| `FffGrepMatch` | `line_content` | 32 | `:pointer` |
| `FffGrepMatch` | `line_number` | 104 | `:uint64` |
| `FffGrepMatch` | `col` | 120 | `:uint32` |

If fff.nvim changes its struct layouts in a future version, update the offset constants in the `;;; Struct field readers` section of `fff.el`.

---

## Troubleshooting

**`module-open-failed` when loading ffi-module.so**

The `.so` needs an absolute path passed to `module-load` before `(require 'ffi)`:
```elisp
(module-load "/absolute/path/to/emacs-ffi/ffi-module.so")
```

**`libfff_c` not found / `define-ffi-library` fails**

Confirm `LD_LIBRARY_PATH` includes the directory with `libfff_c.so` and restart Emacs — environment variables must be set before Emacs starts, not inside `init.el`.

**`peculiar error`**

Confirm `LD_LIBRARY_PATH` includes the directory with `libfff_c.so` and restart Emacs — environment variables must be set before Emacs starts, not inside `init.el`.

**`fff-find-file` errors: "not in a project"**

Run `M-x fff-change-directory` to set a fallback root, or add to your config:
```elisp
(setq fff-default-directory "/path/to/your/project")
```

**No candidates appear in helm**

Run `M-x fff-helm-reload` to ensure the helm functions are freshly bound, then verify:
```elisp
(fboundp 'fff--helm-candidates)  ; must be t
fff-backend                       ; must be non-nil
fff--instance                     ; must be a user-ptr
```

**Emacs crashes when calling fff functions**

Most likely a `uint64` argument is being mishandled by libffi. The `fff--wait-for-scan-poll` function intentionally avoids calling `fff_wait_for_scan` directly (which can crash with large `uint64` values on some libffi versions) and instead polls `fff_is_scanning` in a loop.

**`void-function` errors in helm candidates**

This happens when helm evaluates candidate functions in its dynamic binding context. The fix is already applied — candidate functions must be top-level `defun`s passed as quoted symbols (e.g. `'fff--helm-candidates`), not anonymous lambdas. If you see this after editing `fff-helm.el`, run `M-x fff-helm-reload`.
