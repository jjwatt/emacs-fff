;;; fff-consult.el --- Consult backend for fff -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "28.1") (consult "0.35") (fff "0.1"))
;; Keywords: files, fuzzy, search
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Consult UI backend for fff.el.
;;
;; USAGE
;;   (require 'fff-consult)
;;   (global-set-key (kbd "C-c f f") #'fff-find-file)
;;   (global-set-key (kbd "C-c f g") #'fff-grep)
;;
;; This backend uses completing-read with a proper metadata table rather
;; than consult's internal async API. Since consult installs itself as
;; completing-read-function, you get the full consult UI automatically —
;; preview, narrowing, embark integration — without fighting consult's
;; private internals.

;;; Code:

(require 'consult)
(require 'fff)

;;; ──────────────────────────────────────────────────────────────────
;;; Reload helper

(defun fff-consult-reload ()
  "Force reload of fff-consult, unbinding stale definitions first."
  (interactive)
  (dolist (sym '(fff--consult-table
                 fff-consult-reload))
    (fmakunbound sym))
  (load-file (locate-library "fff-consult"))
  (message "fff-consult: reloaded"))

;;; ──────────────────────────────────────────────────────────────────
;;; Collection table builder

(defun fff--consult-table (cands category)
  "Build a completing-read table from CANDS with metadata CATEGORY.
CANDS is a list of (display . plist) cons cells.
Returns a programmed completion table that consult understands."
  (let ((strings (mapcar #'car cands)))
    (lambda (str pred flag)
      (pcase flag
        ('metadata
         `(metadata
           (category . ,category)
           ;; Tell consult/vertico not to re-sort — fff already scored
           (display-sort-function . identity)
           (cycle-sort-function   . identity)))
        ('t
         (all-completions str strings pred))
        (_
         (try-completion str strings pred))))))

;;; ──────────────────────────────────────────────────────────────────
;;; Backend definition

(defvar fff-backend-consult
  (list
   :pick-file
   (lambda (_candidate-fn action-fn)
     (let* ((cands  (fff-file-candidates ""))
            (table  (fff--consult-table cands 'file))
            (chosen (completing-read "fff › " table nil t)))
       (when (and chosen (not (string-empty-p chosen)))
         (when-let ((plist (cdr (assoc chosen cands))))
           (funcall action-fn plist)))))

   :pick-grep
   (lambda (_candidate-fn action-fn)
     (let* ((query  (read-string "fff grep query: "))
            (cands  (fff-grep-candidates query))
            (table  (fff--consult-table cands 'fff-grep))
            (chosen (completing-read
                     (format "fff grep [%s] › " query)
                     table nil t)))
       (when (and chosen (not (string-empty-p chosen)))
         (when-let ((plist (cdr (assoc chosen cands))))
           (funcall action-fn plist))))))
  "Consult backend for fff.
Set `fff-backend' to this value to use consult for fff pickers.")

;;; ──────────────────────────────────────────────────────────────────
;;; Activate

(setq fff-backend fff-backend-consult)

(provide 'fff-consult)
;;; fff-consult.el ends here
