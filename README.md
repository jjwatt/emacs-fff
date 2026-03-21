# fff.el — Emacs frontend for fff via `emacs-ffi` + `libfff_c.so`

An Emacs extension that calls directly into `libfff_c.so` — the **C FFI shared
library** built by the [fff.nvim](https://github.com/dmtrKovalenko/fff.nvim)
workspace — using [tromey/emacs-ffi](https://github.com/tromey/emacs-ffi).

```
C-c f f  →  fuzzy file picker
C-c f g  →  live grep
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Emacs process                                                   │
│                                                                  │
│  fff.el  ──  define-ffi-function  (emacs-ffi / libffi)          │
│                       │                                          │
└───────────────────────│──────────────────────────────────────────┘
                        │  dlopen + C ABI calls
                        ▼
              ┌────────────────────┐
              │  libfff_c.so       │   ← crates/fff-c/  (cdylib)
              │  synchronous C API │
              └─────────┬──────────┘
                        │
                        ▼
              ┌────────────────────┐
              │  fff-core  (Rust)  │
              │  • file index      │
              │  • fuzzy search    │
              │  • frecency LMDB   │
              │  • git status      │
              │  • live grep       │
              └────────────────────┘
```

### Why this approach vs. the previous version

The first draft of this extension assumed fff used a *socket-based JSON-RPC*
protocol (like many LSP-style tools).  Looking at the actual build output,
the project ships **three** consumer-facing interfaces:

| Artefact | Interface | Consumers |
|---|---|---|
| `libfff_nvim.so` | `mlua` Lua module | Neovim Lua runtime |
| `libfff_c.so` | **stable C ABI**, JSON over FFI | Bun, Node.js, Python — and now Emacs |
| `fff-mcp` binary | stdio MCP protocol | AI agents |

`libfff_c.so` is explicitly labelled "C FFI library" in the release assets.
The C API is **synchronous**, **opaque-handle** based, and returns
heap-allocated JSON strings that the caller must free.  This is exactly what
`emacs-ffi` (`define-ffi-function`) is designed for.

### C API surface (as bound in `fff.el`)

```c
// Memory
void  fff_free_string(char *ptr);

// Databases (frecency + combo-boost history)
bool  fff_init_db(const char *db_path);
bool  fff_init_history_db(const char *db_path);
void  fff_destroy_db(void);

// FilePicker lifecycle
void* fff_picker_create(const char *base_path, int max_threads);
void  fff_picker_destroy(void *picker);
bool  fff_picker_wait_for_scan(void *picker, uint64_t timeout_ms);
bool  fff_picker_is_scan_active(void *picker);
void  fff_picker_rescan(void *picker);
void  fff_picker_refresh_git_status(void *picker);

// Search — return heap-allocated JSON; caller calls fff_free_string()
char* fff_fuzzy_search_files(void *picker, const char *query,
                              int max_results, int max_threads,
                              const char *current_file /*nullable*/);
char* fff_live_grep(void *picker, const char *query,
                    const char *mode /*"plain"|"regex"|"fuzzy"*/,
                    int max_results);

// Frecency recording
void  fff_record_file_open(const char *path);
void  fff_record_query_match(const char *query, const char *path);
```

> **Verify symbol names on your build:**
> ```bash
> nm -D target/release/libfff_c.so | grep ' T '
> ```
> Or run `M-x fff-dump-symbols` after loading the package.

---

## Installation

### 1. Build (or download) `libfff_c.so`

```bash
# Build from source
cd path/to/fff.nvim
cargo build --release -p fff-c
# → target/release/libfff_c.so  (Linux)
# → target/release/libfff_c.dylib (macOS)
cp target/release/libfff_c.so ~/.local/lib/
```

Or grab the prebuilt `c-lib-{target}.so` from the
[GitHub Releases](https://github.com/dmtrKovalenko/fff.nvim/releases) page.

### 2. Install `emacs-ffi`

```bash
git clone https://github.com/tromey/emacs-ffi
cd emacs-ffi
make
```

Add the directory to your `load-path`.

### 3. Configure

```emacs-lisp
(add-to-list 'load-path "/path/to/emacs-ffi")
(add-to-list 'load-path "/path/to/fff.el")

(setq fff-library-path (expand-file-name "~/.local/lib/libfff_c.so"))

(require 'fff)
(global-set-key (kbd "C-c f f") #'fff-find-file)
(global-set-key (kbd "C-c f g") #'fff-grep)
(global-set-key (kbd "C-c f w") #'fff-grep-word-at-point)
```

Or with `use-package` + `straight.el`:

```emacs-lisp
(use-package ffi
  :straight (:host github :repo "tromey/emacs-ffi"))

(use-package fff
  :straight (:host github :repo "your/fff.el")
  :custom
  (fff-library-path (expand-file-name "~/.local/lib/libfff_c.so"))
  (fff-max-results 100)
  (fff-preview-enabled t)
  :bind (("C-c f f" . fff-find-file)
         ("C-c f g" . fff-grep)
         ("C-c f w" . fff-grep-word-at-point)))
```

---

## Usage

| Command | Description |
|---|---|
| `M-x fff-find-file` | Fuzzy file picker for the current project |
| `M-x fff-grep` | Live grep (cycle modes with `<backtab>`) |
| `M-x fff-grep-word-at-point` | Grep for the word under the cursor |
| `M-x fff-refresh` | Rescan the project directory |
| `M-x fff-refresh-git` | Refresh git status |
| `M-x fff-stop` | Destroy the picker + close databases |
| `M-x fff-change-directory` | Switch to a different root |
| `M-x fff-dump-symbols` | Show exported C symbols from the .so |
| `M-x fff-check-symbols` | Verify all expected symbols are present |

### Picker keybindings

| Key | Action |
|---|---|
| `C-n` / `↓` | Move selection down |
| `C-p` / `↑` | Move selection up |
| `RET` | Open in current window |
| `C-s` | Open in horizontal split |
| `C-v` | Open in vertical split |
| `<backtab>` | Cycle grep mode (plain → regex → fuzzy) |
| `C-g` / `<escape>` | Quit without selecting |

---

## Configuration

```emacs-lisp
(setq fff-library-path     "~/.local/lib/libfff_c.so"
      fff-max-results      100
      fff-max-threads      4
      fff-debounce-delay   0.08
      fff-preview-enabled  t
      fff-frecency-db-path "~/.cache/fff_nvim"   ; share with Neovim
      fff-history-db-path  "~/.local/share/fff_queries")
```

Setting `fff-frecency-db-path` and `fff-history-db-path` to the same
paths used by the Neovim plugin means frecency and combo-boost scores
are shared between both editors.

---

## JSON result shapes

**`fff_fuzzy_search_files`:**
```json
[
  {
    "path": "src/main.rs",
    "git_status": "modified",
    "is_current_file": false,
    "score": 1234.5
  }
]
```

**`fff_live_grep`:**
```json
[
  {
    "path": "src/main.rs",
    "line": 42,
    "col": 5,
    "text": "    let result = search(query);"
  }
]
```

---

## Troubleshooting

**`Library not found` error:**
Run `M-x fff-dump-symbols` — if it produces output, the path is correct.
If empty, check `fff-library-path`.

**Symbol not found at runtime:**
Run `M-x fff-check-symbols`.  If symbols are missing, the `fff-c` crate
may have changed names since this file was written.  Check the actual
exports with `nm -D libfff_c.so | grep ' T '` and update the string
arguments in the `define-ffi-function` calls accordingly.

**Frecency not persisting:**
Make sure `fff-frecency-db-path` points to a writable directory, and
that `fff_init_db` returned `t` (check `*Messages*`).
