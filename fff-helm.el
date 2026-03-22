(require 'helm)
(require 'fff)

(defun fff--helm-make-source (name get-candidates)
  (helm-make-source name 'helm-source-sync
    :candidates (lambda () (funcall get-candidates (or (helm-pattern) "")))
    :match-dynamic t
    :volatile t
    :action (lambda (plist) (fff--open-plist plist))))

(defvar fff-backend-helm
  (list
   :pick-file
   (lambda (get-candidates open-fn)
     (ignore open-fn)  ; helm handles opening via :action
     (helm :sources (fff--helm-make-source "fff files" get-candidates)
           :buffer "*helm fff*"
           :prompt "fff › "))
   :pick-grep
   (lambda (get-candidates open-fn)
     (ignore open-fn)
     (helm :sources (fff--helm-make-source "fff grep" get-candidates)
           :buffer "*helm fff grep*"
           :prompt "fff grep › "))))

;; Convenience: set helm as default when this file is loaded
(setq fff-backend fff-backend-helm)

(provide 'fff-helm)
