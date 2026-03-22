;;; fff-helm.el --- Helm backend for fff -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "28.1") (helm "3.0") (fff "0.1"))
;; Keywords: files, fuzzy, search
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Helm UI backend for fff.el.
;;
;; USAGE
;;   (require 'fff-helm)
;;   (global-set-key (kbd "C-c f f") #'fff-find-file)
;;   (global-set-key (kbd "C-c f g") #'fff-grep)
;;
;; Loading this file automatically sets `fff-backend' to `fff-backend-helm'.
;;
;; If you reload fff-helm.el during development, call M-x fff-helm-reload
;; instead of load-file, to clear stale function definitions first.

;;; Code:

(require 'helm)
(require 'fff)

;;; ──────────────────────────────────────────────────────────────────
;;; Reload helper

(defun fff-helm-reload ()
  "Force reload of fff-helm, unbinding stale definitions first."
  (interactive)
  (dolist (sym '(fff--helm-candidates
                 fff--helm-grep-candidates
                 fff--helm-file-source
                 fff--helm-grep-source
                 fff-helm-reload))
    (fmakunbound sym))
  (load-file (locate-library "fff-helm"))
  (message "fff-helm: reloaded"))

;;; ──────────────────────────────────────────────────────────────────
;;; Named candidate functions
;;
;; These must be top-level defuns, not lambdas.
;; Helm looks up :candidates by symbol at call time, so the function
;; must be globally interned — an anonymous lambda in a dynamic
;; binding context will fail with void-function.

(defun fff--helm-candidates ()
  "Return fff file candidates for the current helm pattern."
  (fff-file-candidates (or helm-pattern "")))

(defun fff--helm-grep-candidates ()
  "Return fff grep candidates for the current helm pattern."
  (fff-grep-candidates (or helm-pattern "")))

;;; ──────────────────────────────────────────────────────────────────
;;; Source constructors

(defun fff--helm-file-source (action-fn)
  "Build a helm source for file search, calling ACTION-FN on selection."
  (helm-make-source "fff files" 'helm-source-sync
    :candidates 'fff--helm-candidates
    :match (lambda (_) t)
    :volatile t
    :action
    (helm-make-actions
     "Open file"
     action-fn
     "Open in horizontal split"
     (lambda (plist)
       (split-window-below)
       (other-window 1)
       (funcall action-fn plist))
     "Open in vertical split"
     (lambda (plist)
       (split-window-right)
       (other-window 1)
       (funcall action-fn plist)))))

(defun fff--helm-grep-source (action-fn)
  "Build a helm source for grep, calling ACTION-FN on selection."
  (helm-make-source "fff grep" 'helm-source-sync
    :candidates 'fff--helm-grep-candidates
    :match (lambda (_) t)
    :volatile t
    :action
    (helm-make-actions
     "Jump to match"
     action-fn
     "Jump in horizontal split"
     (lambda (plist)
       (split-window-below)
       (other-window 1)
       (funcall action-fn plist))
     "Jump in vertical split"
     (lambda (plist)
       (split-window-right)
       (other-window 1)
       (funcall action-fn plist)))))

;;; ──────────────────────────────────────────────────────────────────
;;; Backend definition

(defvar fff-backend-helm
  (list
   :pick-file
   (lambda (_candidate-fn action-fn)
     (helm :sources (fff--helm-file-source action-fn)
           :buffer  "*helm fff*"
           :prompt  "fff › "))
   :pick-grep
   (lambda (_candidate-fn action-fn)
     (helm :sources (fff--helm-grep-source action-fn)
           :buffer  "*helm fff grep*"
           :prompt  "fff grep › ")))
  "Helm backend for fff.
Set `fff-backend' to this value to use helm for fff pickers.")

;;; ──────────────────────────────────────────────────────────────────
;;; Activate

(setq fff-backend fff-backend-helm)

(provide 'fff-helm)
;;; fff-helm.el ends here
