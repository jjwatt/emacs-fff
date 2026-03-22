;;; fff.el --- Emacs frontend for fff via emacs-ffi + libfff_c -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "28.1") (ffi "0.1"))
;; Keywords: files, fuzzy, search
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Calls into libfff_c.so using tromey/emacs-ffi.
;; Ensure libfff_c.so is on LD_LIBRARY_PATH before launching Emacs.
;;
;; SETUP
;; 1. Add libfff_c.so to LD_LIBRARY_PATH:
;;      export LD_LIBRARY_PATH="$HOME/git/fff.nvim/target/release:$LD_LIBRARY_PATH"
;; 2. Load emacs-ffi:
;;      (module-load "/path/to/emacs-ffi/ffi-module.so")
;;      (add-to-list 'load-path "/path/to/emacs-ffi")
;; 3. Load this file and bind keys:
;;      (require 'fff)
;;      (global-set-key (kbd "C-c f f") #'fff-find-file)
;;      (global-set-key (kbd "C-c f g") #'fff-grep)

;;; Code:

(require 'ffi)
(require 'cl-lib)
(require 'project)

;;; ──────────────────────────────────────────────────────────────────
;;; Library

(define-ffi-library fff--lib "libfff_c")

;;; ──────────────────────────────────────────────────────────────────
;;; Struct layouts (all repr(C), 64-bit)
;;
;; FffResult:
;;   bool         success    ; offset 0
;;   [7 pad]
;;   *mut c_char  error      ; offset 8
;;   *mut c_void  handle     ; offset 16
;;   i64          int_value  ; offset 24
;;
;; FffFileItem:
;;   *mut c_char  path                        ; offset 0
;;   *mut c_char  relative_path               ; offset 8
;;   *mut c_char  file_name                   ; offset 16
;;   *mut c_char  git_status                  ; offset 24
;;   u64          size                        ; offset 32
;;   u64          modified                    ; offset 40
;;   i64          access_frecency_score       ; offset 48
;;   i64          modification_frecency_score ; offset 56
;;   i64          total_frecency_score        ; offset 64
;;   bool         is_binary                   ; offset 72
;;
;; FffSearchResult:
;;   *mut FffFileItem items        ; offset 0
;;   *mut FffScore    scores       ; offset 8
;;   u32              count        ; offset 16
;;   u32              total_matched; offset 20
;;   u32              total_files  ; offset 24
;;
;; FffGrepMatch:
;;   *mut c_char      path                  ; offset 0
;;   *mut c_char      relative_path         ; offset 8
;;   *mut c_char      file_name             ; offset 16
;;   *mut c_char      git_status            ; offset 24
;;   *mut c_char      line_content          ; offset 32
;;   *mut FffMatchRange match_ranges        ; offset 40
;;   *mut*mut c_char  context_before        ; offset 48
;;   *mut*mut c_char  context_after         ; offset 56
;;   u64              size                  ; offset 64
;;   u64              modified              ; offset 72
;;   i64              total_frecency_score  ; offset 80
;;   i64              access_frecency_score ; offset 88
;;   i64              modification_frecency_score ; offset 96
;;   u64              line_number           ; offset 104
;;   u64              byte_offset           ; offset 112
;;   u32              col                   ; offset 120
;;   u32              match_ranges_count    ; offset 124
;;   u32              context_before_count  ; offset 128
;;   u32              context_after_count   ; offset 132
;;   u16              fuzzy_score           ; offset 136
;;   bool             has_fuzzy_score       ; offset 138
;;   bool             is_binary             ; offset 139
;;   bool             is_definition         ; offset 140
;;
;; FffGrepResult:
;;   *mut FffGrepMatch items               ; offset 0
;;   u32               count               ; offset 8
;;   u32               total_matched       ; offset 12
;;   u32               total_files_searched; offset 16
;;   u32               total_files         ; offset 20
;;   u32               filtered_file_count ; offset 24
;;   u32               next_file_offset    ; offset 28
;;   *mut c_char       regex_fallback_error; offset 32

;;; ──────────────────────────────────────────────────────────────────
;;; FFI function declarations

;; *mut FffResult fff_create_instance(
;;   const char *base_path,
;;   const char *frecency_db_path,  /* NULL/empty to skip */
;;   const char *history_db_path,   /* NULL/empty to skip */
;;   bool use_unsafe_no_lock,
;;   bool warmup_mmap_cache,
;;   bool ai_mode)
(define-ffi-function fff--ffi-create-instance
  "fff_create_instance" :pointer
  [:pointer :pointer :pointer :bool :bool :bool]
  fff--lib)

;; void fff_destroy(void *fff_handle)
(define-ffi-function fff--ffi-destroy
  "fff_destroy" :void [:pointer] fff--lib)

;; *mut FffResult fff_search(
;;   void *fff_handle, const char *query,
;;   const char *current_file,       /* NULL/empty to skip */
;;   uint32_t max_threads,           /* 0 = auto */
;;   uint32_t page_index,            /* 0 = first page */
;;   uint32_t page_size,             /* 0 = default 100 */
;;   int32_t  combo_boost_multiplier,/* 0 = default 100 */
;;   uint32_t min_combo_count)       /* 0 = default 3 */
(define-ffi-function fff--ffi-search
  "fff_search" :pointer
  [:pointer :pointer :pointer :uint32 :uint32 :uint32 :int32 :uint32]
  fff--lib)

;; *mut FffResult fff_live_grep(
;;   void *fff_handle, const char *query,
;;   uint8_t mode,                    /* 0=plain 1=regex 2=fuzzy */
;;   uint64_t max_file_size,          /* 0 = default 10MB */
;;   uint32_t max_matches_per_file,   /* 0 = unlimited */
;;   bool smart_case,
;;   uint32_t file_offset,            /* 0 = start */
;;   uint32_t page_limit,             /* 0 = default 50 */
;;   uint64_t time_budget_ms,         /* 0 = unlimited */
;;   uint32_t before_context,
;;   uint32_t after_context,
;;   bool classify_definitions)
(define-ffi-function fff--ffi-live-grep
  "fff_live_grep" :pointer
  [:pointer :pointer :uint8 :uint64 :uint32 :bool :uint32 :uint32 :uint64 :uint32 :uint32 :bool]
  fff--lib)

;; *mut FffResult fff_scan_files(void *fff_handle)
(define-ffi-function fff--ffi-scan-files
  "fff_scan_files" :pointer [:pointer] fff--lib)

;; bool fff_is_scanning(void *fff_handle)
(define-ffi-function fff--ffi-is-scanning
  "fff_is_scanning" :bool [:pointer] fff--lib)

;; *mut FffResult fff_restart_index(void *fff_handle, const char *new_path)
(define-ffi-function fff--ffi-restart-index
  "fff_restart_index" :pointer [:pointer :pointer] fff--lib)

;; *mut FffResult fff_refresh_git_status(void *fff_handle)
(define-ffi-function fff--ffi-refresh-git-status
  "fff_refresh_git_status" :pointer [:pointer] fff--lib)

;; *mut FffResult fff_track_query(void *fff_handle,
;;   const char *query, const char *file_path)
(define-ffi-function fff--ffi-track-query
  "fff_track_query" :pointer [:pointer :pointer :pointer] fff--lib)

;; void fff_free_result(*mut FffResult)
;; Frees the envelope + error string. Does NOT free handle.
(define-ffi-function fff--ffi-free-result
  "fff_free_result" :void [:pointer] fff--lib)

;; void fff_free_search_result(*mut FffSearchResult)
(define-ffi-function fff--ffi-free-search-result
  "fff_free_search_result" :void [:pointer] fff--lib)

;; void fff_free_grep_result(*mut FffGrepResult)
(define-ffi-function fff--ffi-free-grep-result
  "fff_free_grep_result" :void [:pointer] fff--lib)

;; void fff_free_string(*mut c_char)
(define-ffi-function fff--ffi-free-string
  "fff_free_string" :void [:pointer] fff--lib)

;; *const FffFileItem fff_search_result_get_item(
;;   *const FffSearchResult, uint32_t index)
(define-ffi-function fff--ffi-search-result-get-item
  "fff_search_result_get_item" :pointer [:pointer :uint32] fff--lib)

;; *const FffGrepMatch fff_grep_result_get_match(
;;   *const FffGrepResult, uint32_t index)
(define-ffi-function fff--ffi-grep-result-get-match
  "fff_grep_result_get_match" :pointer [:pointer :uint32] fff--lib)

;;; ──────────────────────────────────────────────────────────────────
;;; FffResult accessors

(defun fff--result-ok-p (result-ptr)
  "Return non-nil if FffResult at RESULT-PTR succeeded (error field is null)."
  (ffi-pointer-null-p
   (ffi--mem-ref (ffi-pointer+ result-ptr 8) :pointer)))

(defun fff--result-error (result-ptr)
  "Return error string from FffResult, or nil on success."
  (let ((err-ptr (ffi--mem-ref (ffi-pointer+ result-ptr 8) :pointer)))
    (unless (ffi-pointer-null-p err-ptr)
      (ffi-get-c-string err-ptr))))

(defun fff--result-handle (result-ptr)
  "Return handle pointer from FffResult (offset 16)."
  (ffi--mem-ref (ffi-pointer+ result-ptr 16) :pointer))

(defun fff--result-int (result-ptr)
  "Return int_value from FffResult (offset 24)."
  (ffi--mem-ref (ffi-pointer+ result-ptr 24) :int64))

;;; ──────────────────────────────────────────────────────────────────
;;; Struct field readers

(defun fff--file-item-path (item-ptr)
  (ffi-get-c-string (ffi--mem-ref item-ptr :pointer)))

(defun fff--file-item-git-status (item-ptr)
  (let ((p (ffi--mem-ref (ffi-pointer+ item-ptr 24) :pointer)))
    (unless (ffi-pointer-null-p p) (ffi-get-c-string p))))

(defun fff--search-result-count (sr-ptr)
  (ffi--mem-ref (ffi-pointer+ sr-ptr 16) :uint32))

(defun fff--grep-result-count (gr-ptr)
  (ffi--mem-ref (ffi-pointer+ gr-ptr 8) :uint32))

(defun fff--grep-match-path (match-ptr)
  (ffi-get-c-string (ffi--mem-ref match-ptr :pointer)))

(defun fff--grep-match-line (match-ptr)
  (ffi--mem-ref (ffi-pointer+ match-ptr 104) :uint64))

(defun fff--grep-match-col (match-ptr)
  (ffi--mem-ref (ffi-pointer+ match-ptr 120) :uint32))

(defun fff--grep-match-line-content (match-ptr)
  (let ((p (ffi--mem-ref (ffi-pointer+ match-ptr 32) :pointer)))
    (unless (ffi-pointer-null-p p) (ffi-get-c-string p))))

;;; ──────────────────────────────────────────────────────────────────
;;; Helpers

(defmacro fff--with-cstring (var string &rest body)
  "Bind VAR to a NUL-terminated C copy of STRING; run BODY; ffi-free."
  (declare (indent 2))
  `(let ((,var (ffi-make-c-string ,string)))
     (unwind-protect (progn ,@body)
       (ffi-free ,var))))

(defmacro fff--with-result (var call &rest body)
  "Execute CALL (returns *mut FffResult), bind VAR to its handle, run BODY.
Signals an error with the Rust message on failure.
Always frees the FffResult envelope; caller must free the handle."
  (declare (indent 2))
  (let ((rptr (gensym "result")))
    `(let ((,rptr ,call))
       (unwind-protect
           (if (fff--result-ok-p ,rptr)
               (let ((,var (fff--result-handle ,rptr)))
                 ,@body)
             (error "fff: %s" (fff--result-error ,rptr)))
         (fff--ffi-free-result ,rptr)))))

;;; ──────────────────────────────────────────────────────────────────
;;; Reload helper
;;
;; define-ffi-function uses defun, so reloading the file won't rebind
;; functions that are already defined. Call fff-reload after updating
;; the file to force all FFI bindings to be refreshed.

(defun fff-reload ()
  "Unbind all fff FFI functions and reload the file."
  (interactive)
  (dolist (sym '(fff--ffi-create-instance fff--ffi-destroy
                 fff--ffi-search fff--ffi-live-grep
                 fff--ffi-scan-files fff--ffi-is-scanning
                 fff--ffi-restart-index fff--ffi-refresh-git-status
                 fff--ffi-track-query fff--ffi-free-result
                 fff--ffi-free-search-result fff--ffi-free-grep-result
                 fff--ffi-free-string fff--ffi-search-result-get-item
                 fff--ffi-grep-result-get-match))
    (fmakunbound sym))
  (load-file (locate-library "fff"))
  (message "fff: reloaded"))

;;; ──────────────────────────────────────────────────────────────────
;;; Customisation

(defgroup fff nil "Emacs frontend for fff." :group 'tools :prefix "fff-")

(defcustom fff-max-results 100
  "Max results per search." :type 'integer :group 'fff)
(defcustom fff-max-threads 0
  "Worker threads (0 = auto)." :type 'integer :group 'fff)
(defcustom fff-debounce-delay 0.08
  "Keystroke debounce in seconds." :type 'float :group 'fff)
(defcustom fff-preview-enabled t
  "Show a file-preview pane." :type 'boolean :group 'fff)
(defcustom fff-smart-case t
  "Case-insensitive when query is all lowercase." :type 'boolean :group 'fff)

(defcustom fff-frecency-db-path
  (expand-file-name "fff_nvim" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Frecency LMDB path (share with Neovim for cross-editor scores)."
  :type 'string :group 'fff)

(defcustom fff-history-db-path
  (expand-file-name "fff_queries" (or (getenv "XDG_DATA_HOME") "~/.local/share"))
  "Query-history LMDB path."
  :type 'string :group 'fff)

;;; ──────────────────────────────────────────────────────────────────
;;; Internal state

(defvar fff--instance nil "Opaque FffInstance handle, or nil.")
(defvar fff--current-base-path nil)
(defvar fff--picker-results '() "List of result plists.")
(defvar fff--picker-selected-index 0)
(defvar fff--picker-mode 'files)
(defvar fff--picker-grep-mode 0 "0=plain 1=regex 2=fuzzy.")
(defvar fff--picker-query "")
(defvar fff--picker-debounce-timer nil)
(defvar fff--picker-window-config nil)

(defconst fff--buffer-name "*fff*")
(defconst fff--preview-buffer-name "*fff-preview*")

;;; ──────────────────────────────────────────────────────────────────
;;; Instance lifecycle

(defun fff--project-root ()
  (expand-file-name
   (or (when-let ((p (project-current))) (project-root p))
       default-directory)))

(defun fff--ensure-instance (base-path)
  "Ensure a live FffInstance for BASE-PATH."
  (unless (string-equal fff--current-base-path base-path)
    (fff--destroy-instance))
  (unless fff--instance
    (fff--with-cstring bp base-path
      (fff--with-cstring fp (expand-file-name fff-frecency-db-path)
        (fff--with-cstring hp (expand-file-name fff-history-db-path)
          (fff--with-result handle
              (fff--ffi-create-instance bp fp hp nil nil nil)
            (setq fff--instance handle
                  fff--current-base-path base-path)))))))

(defun fff--destroy-instance ()
  (when fff--instance
    (fff--ffi-destroy fff--instance)
    (setq fff--instance nil
          fff--current-base-path nil)))

(defun fff--wait-for-scan-poll (timeout-ms)
  "Poll fff_is_scanning until done or TIMEOUT-MS elapses.
Returns t if scan completed, nil if timed out."
  (let ((deadline (+ (float-time) (/ timeout-ms 1000.0))))
    (while (and (fff--ffi-is-scanning fff--instance)
                (< (float-time) deadline))
      (sleep-for 0.05)))
  (not (fff--ffi-is-scanning fff--instance)))

;;; ──────────────────────────────────────────────────────────────────
;;; Search

(defun fff--collect-search-results (sr-ptr)
  "Read FffFileItems from SR-PTR into a list of plists."
  (let ((count (fff--search-result-count sr-ptr))
        results)
    (dotimes (i count)
      (let ((item (fff--ffi-search-result-get-item sr-ptr i)))
        (unless (ffi-pointer-null-p item)
          (push (list :path       (fff--file-item-path item)
                      :git-status (fff--file-item-git-status item))
                results))))
    (nreverse results)))

(defun fff--collect-grep-results (gr-ptr)
  "Read FffGrepMatches from GR-PTR into a list of plists."
  (let ((count (fff--grep-result-count gr-ptr))
        results)
    (dotimes (i count)
      (let ((match (fff--ffi-grep-result-get-match gr-ptr i)))
        (unless (ffi-pointer-null-p match)
          (push (list :path    (fff--grep-match-path match)
                      :line    (fff--grep-match-line match)
                      :col     (fff--grep-match-col match)
                      :content (fff--grep-match-line-content match))
                results))))
    (nreverse results)))

(defun fff--call-search-files (query)
  (when fff--instance
    (fff--with-cstring qp query
      (fff--with-result sr-ptr
          (fff--ffi-search fff--instance qp (ffi-null-pointer)
                           fff-max-threads 0 fff-max-results 0 0)
        (unwind-protect
            (setq fff--picker-results   (fff--collect-search-results sr-ptr)
                  fff--picker-selected-index 0)
          (fff--ffi-free-search-result sr-ptr)))))
  (fff--render-results))

(defun fff--call-live-grep (query)
  (when fff--instance
    (fff--with-cstring qp query
      (fff--with-result gr-ptr
          (fff--ffi-live-grep fff--instance qp
                              fff--picker-grep-mode
                              0 0                ; max_file_size, max_matches_per_file
                              fff-smart-case
                              0                  ; file_offset
                              fff-max-results
                              0 0 0              ; time_budget_ms, before/after context
                              nil)               ; classify_definitions
        (unwind-protect
            (setq fff--picker-results   (fff--collect-grep-results gr-ptr)
                  fff--picker-selected-index 0)
          (fff--ffi-free-grep-result gr-ptr)))))
  (fff--render-results))

(defun fff--dispatch-query (query)
  (pcase fff--picker-mode
    ('files (fff--call-search-files query))
    ('grep  (fff--call-live-grep   query))))

;;; ──────────────────────────────────────────────────────────────────
;;; UI

(defface fff-selected-face
  '((t :inherit highlight)) "Selected result row." :group 'fff)
(defface fff-git-modified-face
  '((t :foreground "orange")) "Git-modified file." :group 'fff)
(defface fff-git-untracked-face
  '((t :foreground "green3")) "Git-untracked file." :group 'fff)
(defface fff-git-staged-face
  '((t :foreground "cyan")) "Git-staged file." :group 'fff)

(defun fff--git-face (s)
  (pcase s
    ("modified"  'fff-git-modified-face)
    ("untracked" 'fff-git-untracked-face)
    ("staged"    'fff-git-staged-face)
    (_           nil)))

(defun fff--render-results ()
  (with-current-buffer (get-buffer-create fff--buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (cl-loop for r in fff--picker-results
               for i from 0
               do (let* ((path  (plist-get r :path))
                         (line  (plist-get r :line))
                         (col   (plist-get r :col))
                         (git   (plist-get r :git-status))
                         (label (if line
                                    (format "%s:%d:%d" path line col)
                                  path))
                         (sel   (= i fff--picker-selected-index))
                         (face  (if sel
                                    'fff-selected-face
                                  (fff--git-face git))))
                    (insert (propertize
                             (concat (if sel "▶ " "  ") label "\n")
                             'face face))))))
  (fff--update-preview))

(defun fff--update-preview ()
  (when fff-preview-enabled
    (when-let* ((r    (nth fff--picker-selected-index fff--picker-results))
                (path (plist-get r :path))
                (line (or (plist-get r :line) 1)))
      (when (file-regular-p path)
        (with-current-buffer (get-buffer-create fff--preview-buffer-name)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (condition-case nil
                (progn
                  (insert-file-contents path nil 0 (* 50 1024))
                  (let ((buffer-file-name path))
                    (ignore-errors (set-auto-mode)))
                  (goto-char (point-min))
                  (forward-line (1- line)))
              (error
               (insert (format "(Cannot preview: %s)" path))))))))))

(defvar fff-picker-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-n")       #'fff-picker-next)
    (define-key m (kbd "C-p")       #'fff-picker-prev)
    (define-key m (kbd "<down>")    #'fff-picker-next)
    (define-key m (kbd "<up>")      #'fff-picker-prev)
    (define-key m (kbd "RET")       #'fff-picker-select)
    (define-key m (kbd "C-s")       #'fff-picker-select-split)
    (define-key m (kbd "C-v")       #'fff-picker-select-vsplit)
    (define-key m (kbd "C-g")       #'fff-picker-quit)
    (define-key m (kbd "<escape>")  #'fff-picker-quit)
    (define-key m (kbd "<backtab>") #'fff-picker-cycle-grep-mode)
    m)
  "Keymap active in the fff minibuffer.")

(defun fff--setup-windows ()
  (setq fff--picker-window-config (current-window-configuration))
  (delete-other-windows)
  (switch-to-buffer (get-buffer-create fff--buffer-name))
  (with-current-buffer fff--buffer-name
    (setq buffer-read-only t)
    (setq-local cursor-type nil))
  (when fff-preview-enabled
    (split-window-horizontally)
    (other-window 1)
    (switch-to-buffer (get-buffer-create fff--preview-buffer-name))
    (setq buffer-read-only t)
    (other-window -1)))

(defun fff--teardown-windows ()
  (when fff--picker-window-config
    (set-window-configuration fff--picker-window-config)
    (setq fff--picker-window-config nil)))

(defun fff--post-command-hook ()
  (let ((q (minibuffer-contents)))
    (unless (string-equal q fff--picker-query)
      (setq fff--picker-query q)
      (when fff--picker-debounce-timer
        (cancel-timer fff--picker-debounce-timer))
      (setq fff--picker-debounce-timer
            (run-with-timer fff-debounce-delay nil
                            (lambda () (fff--dispatch-query q)))))))

(defun fff--read-query (prompt)
  (let ((map (copy-keymap minibuffer-local-map)))
    (set-keymap-parent map fff-picker-map)
    (add-hook 'post-command-hook #'fff--post-command-hook nil t)
    (unwind-protect
        (read-from-minibuffer prompt nil map)
      (remove-hook 'post-command-hook #'fff--post-command-hook t)
      (when fff--picker-debounce-timer
        (cancel-timer fff--picker-debounce-timer)
        (setq fff--picker-debounce-timer nil)))))

;;; ──────────────────────────────────────────────────────────────────
;;; Actions

(defun fff-picker-next ()
  "Move selection down one row."
  (interactive)
  (setq fff--picker-selected-index
        (min (1+ fff--picker-selected-index)
             (1- (max 1 (length fff--picker-results)))))
  (fff--render-results))

(defun fff-picker-prev ()
  "Move selection up one row."
  (interactive)
  (setq fff--picker-selected-index
        (max 0 (1- fff--picker-selected-index)))
  (fff--render-results))

(defun fff--selected-result ()
  (nth fff--picker-selected-index fff--picker-results))

(defun fff--open-result (result &optional split)
  (let ((path (plist-get result :path))
        (line (plist-get result :line)))
    (when (and fff--instance
               fff--picker-query
               (not (string-empty-p fff--picker-query)))
      (fff--with-cstring qp fff--picker-query
        (fff--with-cstring pp path
          (let ((r (fff--ffi-track-query fff--instance qp pp)))
            (fff--ffi-free-result r)))))
    (fff-picker-quit)
    (pcase split
      (:h (split-window-below) (other-window 1))
      (:v (split-window-right) (other-window 1)))
    (find-file path)
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))

(defun fff-picker-select ()
  "Open selected result in current window."
  (interactive)
  (when-let ((r (fff--selected-result))) (fff--open-result r)))

(defun fff-picker-select-split ()
  "Open selected result in horizontal split."
  (interactive)
  (when-let ((r (fff--selected-result))) (fff--open-result r :h)))

(defun fff-picker-select-vsplit ()
  "Open selected result in vertical split."
  (interactive)
  (when-let ((r (fff--selected-result))) (fff--open-result r :v)))

(defun fff-picker-cycle-grep-mode ()
  "Cycle grep mode: plain → regex → fuzzy."
  (interactive)
  (setq fff--picker-grep-mode (mod (1+ fff--picker-grep-mode) 3))
  (message "fff grep mode: %s"
           (pcase fff--picker-grep-mode (0 "plain") (1 "regex") (2 "fuzzy")))
  (fff--dispatch-query fff--picker-query))

(defun fff-picker-quit ()
  "Close the picker without selecting."
  (interactive)
  (fff--teardown-windows)
  (when (minibufferp) (abort-recursive-edit)))

;;; ──────────────────────────────────────────────────────────────────
;;; Backend protocol
;;
;; A backend is a plist with these keys, all functions:
;;
;;  :pick-file  (lambda (get-candidates open-fn) ...)
;;    Called by fff-find-file. get-candidates is a function that
;;    takes a query string and returns a list of (display . plist)
;;    cons cells. open-fn is called with the chosen plist.
;;
;;  :pick-grep  (lambda (get-candidates open-fn) ...)
;;    Same but for grep results.
;;
;; get-candidates signature: (lambda (query) ...) → list of (label . plist)
;; open-fn      signature:   (lambda (result-plist) ...)

(defvar fff-backend nil
  "Active fff UI backend plist.
Set this to `fff-backend-helm', `fff-backend-consult',
`fff-backend-ivy', or `fff-backend-default' before calling
any fff entry point.  If nil, `fff-backend-default' is used.")

(defun fff--backend ()
  (or fff-backend fff-backend-default))

(defun fff--backend-pick-file (get-candidates open-fn)
  (funcall (plist-get (fff--backend) :pick-file) get-candidates open-fn))

(defun fff--backend-pick-grep (get-candidates open-fn)
  (funcall (plist-get (fff--backend) :pick-grep) get-candidates open-fn))

(defun fff--file-candidates (query)
  "Return (label . plist) pairs for file search QUERY."
  (fff--call-search-files query)   ; updates fff--picker-results
  (mapcar (lambda (r)
            (cons (or (plist-get r :path) "")
                  r))
          fff--picker-results))

(defun fff--grep-candidates (query)
  "Return (label . plist) pairs for grep QUERY."
  (fff--call-live-grep query)
  (mapcar (lambda (r)
            (cons (format "%s:%d:%d"
                          (plist-get r :path)
                          (or (plist-get r :line) 0)
                          (or (plist-get r :col)  0))
                  r))
          fff--picker-results))

(defun fff--open-plist (plist)
  "Open the file described by result PLIST."
  (let ((path (plist-get plist :path))
        (line (plist-get plist :line)))
    (when (and fff--instance
               fff--picker-query
               (not (string-empty-p fff--picker-query)))
      (fff--with-cstring qp fff--picker-query
        (fff--with-cstring pp path
          (fff--ffi-free-result
           (fff--ffi-track-query fff--instance qp pp)))))
    (find-file path)
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))

;;; ──────────────────────────────────────────────────────────────────
;;; Public entry points
;;;###autoload
(defun fff-find-file ()
  (interactive)
  (let ((base (fff--project-root)))
    (fff--ensure-instance base)
    (fff--wait-for-scan-poll 10000)
    (fff--backend-pick-file #'fff--file-candidates #'fff--open-plist)))

;;;###autoload
(defun fff-grep ()
  (interactive)
  (let ((base (fff--project-root)))
    (fff--ensure-instance base)
    (fff--backend-pick-grep #'fff--grep-candidates #'fff--open-plist)))

;;;###autoload
(defun fff-grep-word-at-point ()
  "Grep for the word at point."
  (interactive)
  (let ((word (thing-at-point 'word t)))
    (fff-grep)
    (when word
      (insert word)
      (fff--dispatch-query word))))

;;;###autoload
(defun fff-refresh ()
  "Trigger a rescan of the current project tree."
  (interactive)
  (if fff--instance
      (let ((r (fff--ffi-scan-files fff--instance)))
        (fff--ffi-free-result r)
        (message "fff: rescanning"))
    (message "fff: no active instance")))

;;;###autoload
(defun fff-refresh-git ()
  "Refresh git status in the current picker."
  (interactive)
  (if fff--instance
      (let ((r (fff--ffi-refresh-git-status fff--instance)))
        (fff--ffi-free-result r)
        (message "fff: git status refreshed"))
    (message "fff: no active instance")))

;;;###autoload
(defun fff-stop ()
  "Destroy the fff instance."
  (interactive)
  (fff--destroy-instance)
  (message "fff: stopped"))

;;;###autoload
(defun fff-change-directory (dir)
  "Restart the picker rooted at DIR."
  (interactive "DNew root: ")
  (fff--with-result _handle
      (fff--ffi-restart-index fff--instance
                              (ffi-make-c-string (expand-file-name dir)))
    (setq fff--current-base-path (expand-file-name dir))
    (message "fff: now watching %s" dir)))

(provide 'fff)

(defun fff--file-candidates (query)
  "Return (label . plist) pairs for file search QUERY."
  (fff--call-search-files query)   ; updates fff--picker-results
  (mapcar (lambda (r)
            (cons (or (plist-get r :path) "")
                  r))
          fff--picker-results))

(defun fff--grep-candidates (query)
  "Return (label . plist) pairs for grep QUERY."
  (fff--call-live-grep query)
  (mapcar (lambda (r)
            (cons (format "%s:%d:%d"
                          (plist-get r :path)
                          (or (plist-get r :line) 0)
                          (or (plist-get r :col)  0))
                  r))
          fff--picker-results))

(defun fff--open-plist (plist)
  "Open the file described by result PLIST."
  (let ((path (plist-get plist :path))
        (line (plist-get plist :line)))
    (when (and fff--instance
               fff--picker-query
               (not (string-empty-p fff--picker-query)))
      (fff--with-cstring qp fff--picker-query
        (fff--with-cstring pp path
          (fff--ffi-free-result
           (fff--ffi-track-query fff--instance qp pp)))))
    (find-file path)
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))
;;; fff.el ends here
