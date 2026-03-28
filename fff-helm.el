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
  (dolist (sym '(fff--helm-current-candidate-fn
                 fff--helm-candidates
                 fff--helm-build-source
                 fff-helm-reload))
    (fmakunbound sym))
  (load-file (locate-library "fff-helm"))
  (message "fff-helm: reloaded"))

;;; ──────────────────────────────────────────────────────────────────
;;; Dynamic State & Generic Candidate Function

(defvar fff--helm-current-candidate-fn nil
  "Dynamically bound candidate generator for the active Helm session.
This allows us to pass different candidate functions (files vs. grep)
to a single globally interned Helm source without hardcoding them.")

(defun fff--helm-candidates ()
  "Call the active candidate function with the current helm pattern.
Helm requires `:candidates` to be a globally interned symbol, not a lambda."
  (when fff--helm-current-candidate-fn
    (funcall fff--helm-current-candidate-fn (or helm-pattern ""))))

;;; ──────────────────────────────────────────────────────────────────
;;; Generic Source Constructor

(defun fff--helm-build-source (name action-fn)
  "Build a generic Helm sync source named NAME using ACTION-FN."
  (helm-build-sync-source name
    :candidates 'fff--helm-candidates
    :match (lambda (_) t)
    :volatile t
    :action
    (helm-make-actions
     "Open / Jump"
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

;;; ──────────────────────────────────────────────────────────────────
;;; Backend definition

(defvar fff-backend-helm
  (list
   :pick-file
   (lambda (candidate-fn action-fn)
     ;; Dynamically bind the candidate-fn so the global symbol can see it
     (let ((fff--helm-current-candidate-fn candidate-fn))
       (helm :sources (fff--helm-build-source "fff files" action-fn)
             :buffer  "*helm fff*"
             :prompt  "fff › ")))

   :pick-grep
   (lambda (candidate-fn action-fn)
     (let ((fff--helm-current-candidate-fn candidate-fn))
       (helm :sources (fff--helm-build-source "fff grep" action-fn)
             :buffer  "*helm fff grep*"
             :prompt  "fff grep › "))))
  "Helm backend for fff.
Set `fff-backend' to this value to use helm for fff pickers.")

;;; ──────────────────────────────────────────────────────────────────
;;; Activate

(setq fff-backend fff-backend-helm)

(provide 'fff-helm)
;;; fff-helm.el ends here
