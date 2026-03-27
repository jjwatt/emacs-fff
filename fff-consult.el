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
;; Loading this file automatically sets `fff-backend' to `fff-backend-consult'.
;;
;; Uses consult--async-dynamic so that fff re-queries on every keystroke,
;; giving you live frecency-scored results as you type.

;;; Code:

(require 'consult)
(require 'fff)

;;; ──────────────────────────────────────────────────────────────────
;;; Reload helper

(defun fff-consult-reload ()
  "Force reload of fff-consult, unbinding stale definitions first."
  (interactive)
  (dolist (sym '(fff-consult-reload))
    (fmakunbound sym))
  (load-file (locate-library "fff-consult"))
  (message "fff-consult: reloaded"))

;;; ──────────────────────────────────────────────────────────────────
;;; Backend definition

(defvar fff-backend-consult
  (list
   :pick-file
   (lambda (_candidate-fn action-fn)
     (let ((lookup (make-hash-table :test 'equal)))
       (when-let
           ((chosen
             (consult--read
              (consult--async-dynamic
               (lambda (input)
                 (let ((cands (fff-file-candidates input)))
                   (clrhash lookup)
                   (mapcar (lambda (c)
                             (puthash (car c) (cdr c) lookup)
                             (car c))
                           cands))))
              :prompt   "fff › "
              :sort     nil
              :category 'file
              ;; consult calls :lookup with (cand cands input narrow)
              :lookup   (lambda (cand _cands _input _narrow)
                          (gethash cand lookup)))))
         (funcall action-fn chosen))))

   :pick-grep
   (lambda (_candidate-fn action-fn)
     (let ((lookup (make-hash-table :test 'equal)))
       (when-let
           ((chosen
             (consult--read
              (consult--async-dynamic
               (lambda (input)
                 (let ((cands (fff-grep-candidates input)))
                   (clrhash lookup)
                   (mapcar (lambda (c)
                             (puthash (car c) (cdr c) lookup)
                             (car c))
                           cands))))
              :prompt "fff grep › "
              :sort   nil
              :lookup (lambda (cand _cands _input _narrow)
                        (gethash cand lookup)))))
         (funcall action-fn chosen)))))
  "Consult backend for fff.
Set `fff-backend' to this value to use consult for fff pickers.")

;;; ──────────────────────────────────────────────────────────────────
;;; Activate

(setq fff-backend fff-backend-consult)

(provide 'fff-consult)
;;; fff-consult.el ends here
