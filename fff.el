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
;; 3. Choose a backend and load:
;;      (require 'fff-helm)    ; for helm
;;      (require 'fff-consult) ; for consult
;;      (require 'fff-ivy)     ; for ivy
;;      (require 'fff)         ; for the built-in default
;; 4. Bind keys:
;;      (global-set-key (kbd "C-c f f") #'fff-find-file)
;;      (global-set-key (kbd "C-c f g") #'fff-grep)

;;; Code:

(require 'ffi)
(require 'cl-lib)
(require 'project)

;;; ──────────────────────────────────────────────────────────────────
;;; Library

;; Determine the correct extension for the OS.
(defvar fff--lib-extension (if (eq system-type 'darwin) ".dylib" ".so"))

;; Find the library relative to THIS file's location.
(defvar fff--lib-path
  (let ((dir (file-name-directory (or load-file-name buffer-file-name))))
    (expand-file-name (concat "libfff_c" fff--lib-extension) dir)))

;; Fallback: If it's not in the folder, let the system try to find it
(unless (file-exists-p fff--lib-path)
  (setq fff--lib-path "libfff_c"))

(define-ffi-library fff--lib fff--lib-path)

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
;;   *mut c_char      path                       ; offset 0
;;   *mut c_char      relative_path              ; offset 8
;;   *mut c_char      file_name                  ; offset 16
;;   *mut c_char      git_status                 ; offset 24
;;   *mut c_char      line_content               ; offset 32
;;   *mut FffMatchRange match_ranges             ; offset 40
;;   *mut*mut c_char  context_before             ; offset 48
;;   *mut*mut c_char  context_after              ; offset 56
;;   u64              size                       ; offset 64
;;   u64              modified                   ; offset 72
;;   i64              total_frecency_score       ; offset 80
;;   i64              access_frecency_score      ; offset 88
;;   i64              modification_frecency_score; offset 96
;;   u64              line_number                ; offset 104
;;   u64              byte_offset                ; offset 112
;;   u32              col                        ; offset 120
;;   u32              match_ranges_count         ; offset 124
;;   u32              context_before_count       ; offset 128
;;   u32              context_after_count        ; offset 132
;;   u16              fuzzy_score                ; offset 136
;;   bool             has_fuzzy_score            ; offset 138
;;   bool             is_binary                  ; offset 139
;;   bool             is_definition              ; offset 140
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

(define-ffi-function fff--ffi-create-instance
  "fff_create_instance" :pointer
  [:pointer :pointer :pointer :bool :bool :bool]
  fff--lib)

(define-ffi-function fff--ffi-destroy
  "fff_destroy" :void [:pointer] fff--lib)

(define-ffi-function fff--ffi-search
  "fff_search" :pointer
  [:pointer :pointer :pointer :uint32 :uint32 :uint32 :int32 :uint32]
  fff--lib)

(define-ffi-function fff--ffi-live-grep
  "fff_live_grep" :pointer
  [:pointer :pointer :uint8 :uint64 :uint32 :bool :uint32 :uint32 :uint64 :uint32 :uint32 :bool]
  fff--lib)

(define-ffi-function fff--ffi-scan-files
  "fff_scan_files" :pointer [:pointer] fff--lib)

(define-ffi-function fff--ffi-is-scanning
  "fff_is_scanning" :bool [:pointer] fff--lib)

(define-ffi-function fff--ffi-restart-index
  "fff_restart_index" :pointer [:pointer :pointer] fff--lib)

(define-ffi-function fff--ffi-refresh-git-status
  "fff_refresh_git_status" :pointer [:pointer] fff--lib)

(define-ffi-function fff--ffi-track-query
  "fff_track_query" :pointer [:pointer :pointer :pointer] fff--lib)

(define-ffi-function fff--ffi-free-result
  "fff_free_result" :void [:pointer] fff--lib)

(define-ffi-function fff--ffi-free-search-result
  "fff_free_search_result" :void [:pointer] fff--lib)

(define-ffi-function fff--ffi-free-grep-result
  "fff_free_grep_result" :void [:pointer] fff--lib)

(define-ffi-function fff--ffi-free-string
  "fff_free_string" :void [:pointer] fff--lib)

(define-ffi-function fff--ffi-search-result-get-item
  "fff_search_result_get_item" :pointer [:pointer :uint32] fff--lib)

(define-ffi-function fff--ffi-grep-result-get-match
  "fff_grep_result_get_match" :pointer [:pointer :uint32] fff--lib)

;;; ──────────────────────────────────────────────────────────────────
;;; FffResult accessors

(defun fff--result-ok-p (result-ptr)
  "Return non-nil if FffResult succeeded (error field at offset 8 is null)."
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
Signals an error on failure. Always frees the FffResult envelope."
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

(defun fff-reload ()
  "Unbind all fff FFI functions and reload the file.
Preserves the active backend across reloads."
  (interactive)
  (let ((saved-backend fff-backend))
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
    (setq fff-backend saved-backend)
    (message "fff: reloaded")))

;;; ──────────────────────────────────────────────────────────────────
;;; Customisation

(defgroup fff nil "Emacs frontend for fff." :group 'tools :prefix "fff-")

(defcustom fff-max-results 100
  "Max results per search." :type 'integer :group 'fff)
(defcustom fff-max-threads 0
  "Worker threads (0 = auto)." :type 'integer :group 'fff)
(defcustom fff-smart-case t
  "Case-insensitive when query is all lowercase." :type 'boolean :group 'fff)

(defcustom fff-default-directory nil
  "Fallback root directory when not inside a git project.
Set this if you want fff to work outside git repositories.
`fff-change-directory' updates this automatically."
  :type '(choice (const :tag "None" nil) directory)
  :group 'fff)

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
(defvar fff--last-query "" "Most recent query string, for frecency tracking.")

;;; ──────────────────────────────────────────────────────────────────
;;; Instance lifecycle

(defun fff--project-root ()
  "Return the git project root, signalling an error if not in a project."
  (expand-file-name
   (or (when-let ((p (project-current))) (project-root p))
       (user-error "fff: not in a project (no .git found). \
Use M-x fff-change-directory to set a root"))))

(defun fff--get-base-path ()
  "Return the base path to use for the picker.
Prefers the git project root of the current buffer, then
`fff-default-directory', then the existing instance path.
This means the picker automatically switches project when you
change to a buffer in a different git repo."
  (or
   ;; 1. Git project root for the current buffer (auto-switches per project)
   (ignore-errors (fff--project-root))
   ;; 2. Explicit fallback set by fff-change-directory
   (and fff-default-directory
	(expand-file-name fff-default-directory))
   ;; 3. Keep existing instance rather than error
   fff--current-base-path
   ;; 4. Give up
   (user-error "fff: cannot determine project root. \
Use M-x fff-change-directory to set one")))

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
  "Poll fff_is_scanning until done or TIMEOUT-MS elapses."
  (let ((deadline (+ (float-time) (/ timeout-ms 1000.0))))
    (while (and (fff--ffi-is-scanning fff--instance)
		(< (float-time) deadline))
      (sleep-for 0.05)))
  (not (fff--ffi-is-scanning fff--instance)))

;;; ──────────────────────────────────────────────────────────────────
;;; Candidate builders

(defun fff--search-raw (query)
  "Run file search for QUERY, return raw list of result plists."
  (when fff--instance
    (fff--with-cstring qp query
      (fff--with-result sr-ptr
	  (fff--ffi-search fff--instance qp (ffi-null-pointer)
			   fff-max-threads 0 fff-max-results 0 0)
	(let ((count (fff--search-result-count sr-ptr))
	      results)
	  (dotimes (i count)
	    (let ((item (fff--ffi-search-result-get-item sr-ptr i)))
	      (unless (ffi-pointer-null-p item)
		(push (list :path       (fff--file-item-path item)
			    :git-status (fff--file-item-git-status item))
		      results))))
	  (fff--ffi-free-search-result sr-ptr)
	  (nreverse results))))))

(defun fff--grep-raw (query)
  "Run grep for QUERY, return raw list of result plists."
  (when fff--instance
    (fff--with-cstring qp query
      (fff--with-result gr-ptr
	  (fff--ffi-live-grep fff--instance qp
			      0              ; mode: plain
			      0 0            ; max_file_size, max_matches_per_file
			      fff-smart-case
			      0              ; file_offset
			      fff-max-results
			      0 0 0          ; time_budget_ms, before/after context
			      nil)           ; classify_definitions
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
	  (fff--ffi-free-grep-result gr-ptr)
	  (nreverse results))))))

(defun fff-file-candidates (query)
  "Return (display . plist) candidates for file search QUERY."
  (setq fff--last-query query)
  (mapcar (lambda (r) (cons (plist-get r :path) r))
	  (fff--search-raw query)))

(defun fff-grep-candidates (query)
  "Return (display . plist) candidates for grep QUERY."
  (setq fff--last-query query)
  (mapcar (lambda (r)
	    (cons (format "%s:%d:%d  %s"
			  (plist-get r :path)
			  (or (plist-get r :line) 0)
			  (or (plist-get r :col)  0)
			  (or (plist-get r :content) ""))
		  r))
	  (fff--grep-raw query)))

;;; ──────────────────────────────────────────────────────────────────
;;; Open action

(defun fff-open-result (plist)
  "Open the file described by result PLIST."
  (let ((path (plist-get plist :path))
	(line (plist-get plist :line)))
    (when (and fff--instance
	       (not (string-empty-p fff--last-query)))
      (fff--with-cstring qp fff--last-query
	(fff--with-cstring pp path
	  (fff--ffi-free-result
	   (fff--ffi-track-query fff--instance qp pp)))))
    (find-file path)
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))

;;; ──────────────────────────────────────────────────────────────────
;;; Backend protocol

(defvar fff-backend nil
  "Active fff UI backend plist.
Set to `fff-backend-helm', `fff-backend-consult', `fff-backend-ivy',
or leave nil to use the built-in `fff-backend-default'.")

(defun fff--active-backend ()
  (or fff-backend (fff--make-default-backend)))

(defun fff--backend-pick-file (candidate-fn action-fn)
  (funcall (plist-get (fff--active-backend) :pick-file)
	   candidate-fn action-fn))

(defun fff--backend-pick-grep (candidate-fn action-fn)
  (funcall (plist-get (fff--active-backend) :pick-grep)
	   candidate-fn action-fn))

;;; ──────────────────────────────────────────────────────────────────
;;; Default backend (plain completing-read)

(defun fff--make-default-backend ()
  (list
   :pick-file
   (lambda (candidate-fn action-fn)
     (let* ((cands  (funcall candidate-fn ""))
	    (chosen (completing-read "fff › " (mapcar #'car cands) nil t)))
       (when chosen
	 (funcall action-fn (cdr (assoc chosen cands))))))
   :pick-grep
   (lambda (candidate-fn action-fn)
     (let* ((query  (read-string "fff grep › "))
	    (cands  (funcall candidate-fn query))
	    (chosen (completing-read "match › " (mapcar #'car cands) nil t)))
       (when chosen
	 (funcall action-fn (cdr (assoc chosen cands))))))))

;;; ──────────────────────────────────────────────────────────────────
;;; Public entry points

;;;###autoload
(defun fff-find-file ()
  "Fuzzy file picker for the current project."
  (interactive)
  (let ((base (fff--get-base-path)))
    (fff--ensure-instance base)
    ;; Check if the scan completes within the window
    (if (fff--wait-for-scan-poll 10000)
	(fff--backend-pick-file #'fff-file-candidates #'fff-open-result)
      ;; Timeout: Abort and warn the user.
      (user-error "fff: Initial file scan timed out. Try M-x fff-refresh"))))

;;;###autoload
(defun fff-grep ()
  "Live grep picker for the current project."
  (interactive)
  (let ((base (fff--get-base-path)))
    (fff--ensure-instance base)
    (fff--backend-pick-grep #'fff-grep-candidates #'fff-open-result)))

;;;###autoload
(defun fff-grep-word-at-point ()
  "Grep for the word at point."
  (interactive)
  (let ((base (fff--get-base-path))
	(word (thing-at-point 'word t)))
    (fff--ensure-instance base)
    (setq fff--last-query (or word ""))
    (fff--backend-pick-grep
     (lambda (query)
       (fff-grep-candidates (if (string-empty-p query) (or word "") query)))
     #'fff-open-result)))

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
  "Set DIR as the fallback root for fff when outside a git project.
The new instance will be created on the next `fff-find-file' call."
  (interactive "DNew root: ")
  (let ((path (expand-file-name dir)))
    (setq fff-default-directory path)
    ;; Destroy existing instance so it gets recreated with the new path
    (fff--destroy-instance)
    (message "fff: default directory set to %s" path)))

(provide 'fff)
;;; fff.el ends here
