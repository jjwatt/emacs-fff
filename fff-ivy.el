;;; fff-ivy.el --- Ivy backend for fff -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "28.1") (ivy "0.13") (fff "0.1"))
;; Keywords: files, fuzzy, search
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Ivy UI backend for fff.el.
;;
;; USAGE
;;   (require 'fff-ivy)
;;   (global-set-key (kbd "C-c f f") #'fff-find-file)
;;   (global-set-key (kbd "C-c f g") #'fff-grep)
;;
;; Loading this file automatically sets `fff-backend' to `fff-backend-ivy'.
;;
;; If you reload fff-ivy.el during development, call M-x fff-ivy-reload
;; instead of load-file, to clear stale function definitions first.

;;; Code:

(require 'ivy)
(require 'fff)

;;; ──────────────────────────────────────────────────────────────────
;;; Reload helper

(defun fff-ivy-reload ()
  "Force reload of fff-ivy, unbinding stale definitions first."
  (interactive)
  (dolist (sym '(fff-ivy-reload))
    (fmakunbound sym))
  (load-file (locate-library "fff-ivy"))
  (message "fff-ivy: reloaded"))

;;; ──────────────────────────────────────────────────────────────────
;;; Internal state
;;
;; Ivy's dynamic collection function receives a query string and must
;; return a list of display strings synchronously. We cache the full
;; (display . plist) alist so the action function can look up the
;; chosen display string and retrieve the plist.

(defvar fff--ivy-candidates nil
  "Most recent alist of (display . plist) pairs, used by ivy actions.")

;;; ──────────────────────────────────────────────────────────────────
;;; Dynamic collection functions
;;
;; These are passed to ivy-read as :dynamic-collection functions.
;; They are called with the current query string on every keypress.

(defun fff--ivy-file-collection (query)
  "Return display strings for file search QUERY, caching plists."
  (let ((cands (fff-file-candidates query)))
    (setq fff--ivy-candidates cands)
    (mapcar #'car cands)))

(defun fff--ivy-grep-collection (query)
  "Return display strings for grep QUERY, caching plists."
  (let ((cands (fff-grep-candidates query)))
    (setq fff--ivy-candidates cands)
    (mapcar #'car cands)))

;;; ──────────────────────────────────────────────────────────────────
;;; Action helpers

(defun fff--ivy-action (action-fn display)
  "Look up DISPLAY in `fff--ivy-candidates' and call ACTION-FN with its plist."
  (when-let ((plist (cdr (assoc display fff--ivy-candidates))))
    (funcall action-fn plist)))

(defun fff--ivy-action-split-h (action-fn x)
  "Open result in a horizontal split. X is a (display . plist) cons."
  (split-window-below)
  (other-window 1)
  (funcall action-fn (cdr x)))

(defun fff--ivy-action-split-v (action-fn x)
  "Open result in a vertical split. X is a (display . plist) cons."
  (split-window-right)
  (other-window 1)
  (funcall action-fn (cdr x)))

;;; ──────────────────────────────────────────────────────────────────
;;; Backend definition

(defvar fff-backend-ivy
  (list
   :pick-file
   (lambda (candidate-fn action-fn)
     (let ((lookup (make-hash-table :test 'equal)))
       (ivy-read
        "fff › "
        (lambda (query)
          (let ((cands (funcall candidate-fn query)))
            (mapcar (lambda (c)
                      (puthash (car c) (cdr c) lookup)
                      (car c))
                    cands)))
        :dynamic-collection t
        :require-match t
        :action
        ;; Ivy allows a list of actions: (default-index (key func doc) ...)
        ;; Using `list` here instead of quote ensures our closures capture `lookup`.
        (list 1
              (list "o" (lambda (cand)
                          (when-let ((plist (gethash cand lookup)))
                            (funcall action-fn plist)))
                    "open")
              (list "h" (lambda (cand)
                          (when-let ((plist (gethash cand lookup)))
                            (split-window-below)
                            (other-window 1)
                            (funcall action-fn plist)))
                    "open in horizontal split")
              (list "v" (lambda (cand)
                          (when-let ((plist (gethash cand lookup)))
                            (split-window-right)
                            (other-window 1)
                            (funcall action-fn plist)))
                    "open in vertical split"))
        :caller 'fff-find-file)))

   :pick-grep
   (lambda (candidate-fn action-fn)
     (let ((lookup (make-hash-table :test 'equal)))
       (ivy-read
        "fff grep › "
        (lambda (query)
          (let ((cands (funcall candidate-fn query)))
            (mapcar (lambda (c)
                      (puthash (car c) (cdr c) lookup)
                      (car c))
                    cands)))
        :dynamic-collection t
        :require-match t
        :action
        (list 1
              (list "o" (lambda (cand)
                          (when-let ((plist (gethash cand lookup)))
                            (funcall action-fn plist)))
                    "jump")
              (list "h" (lambda (cand)
                          (when-let ((plist (gethash cand lookup)))
                            (split-window-below)
                            (other-window 1)
                            (funcall action-fn plist)))
                    "jump in horizontal split")
              (list "v" (lambda (cand)
                          (when-let ((plist (gethash cand lookup)))
                            (split-window-right)
                            (other-window 1)
                            (funcall action-fn plist)))
                    "jump in vertical split"))
        :caller 'fff-grep))))
  "Ivy backend for fff.
Set `fff-backend' to this value to use ivy for fff pickers.")

;;; ──────────────────────────────────────────────────────────────────
;;; Extra ivy actions (accessible via M-o in the ivy buffer)

(ivy-set-actions
 'fff-find-file
 '(("h" (lambda (x)
          (fff--ivy-action-split-h #'fff-open-result x))
    "open in horizontal split")
   ("v" (lambda (x)
          (fff--ivy-action-split-v #'fff-open-result x))
    "open in vertical split")))

(ivy-set-actions
 'fff-grep
 '(("h" (lambda (x)
          (fff--ivy-action-split-h #'fff-open-result x))
    "jump in horizontal split")
   ("v" (lambda (x)
          (fff--ivy-action-split-v #'fff-open-result x))
    "jump in vertical split")))

;;; ──────────────────────────────────────────────────────────────────
;;; Activate

(setq fff-backend fff-backend-ivy)

(provide 'fff-ivy)
;;; fff-ivy.el ends here
