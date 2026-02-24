;;; openclaw-process.el --- Subprocess management for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; Manages the `openclaw acp` subprocess and NDJSON I/O.
;;; Code:

(defvar openclaw--process nil
  "The openclaw acp subprocess.")

(defvar openclaw--output-buffer ""
  "Accumulated stdout for partial NDJSON line parsing.")

(defun openclaw-process-running-p ()
  "Return non-nil if the subprocess is alive."
  (and openclaw--process
       (process-live-p openclaw--process)))

(defun openclaw-process-ensure ()
  "Start the subprocess if not running. Return the process."
  (unless (openclaw-process-running-p)
    (openclaw-process-start))
  openclaw--process)

(defun openclaw-process-start ()
  "Start the openclaw acp subprocess."
  (when (openclaw-process-running-p)
    (openclaw-process-stop))
  (setq openclaw--output-buffer "")
  (let* ((cmd openclaw-executable)
         (args (list "acp"))
         (args (if openclaw-gateway-url
                   (append args (list "--url" openclaw-gateway-url))
                 args))
         (args (if openclaw-gateway-token
                   (append args (list "--token" openclaw-gateway-token))
                 args)))
    (message "OpenClaw: starting process: %s %s" cmd (string-join args " "))
    (setq openclaw--process
          (make-process
           :name "openclaw-acp"
           :buffer nil
           :command (cons cmd args)
           :connection-type 'pipe
           :filter #'openclaw-process-filter
           :sentinel #'openclaw-process-sentinel
           :noquery t))
    (openclaw-protocol-initialize)))

(defun openclaw-process-stop ()
  "Stop the subprocess."
  (interactive)
  (when (openclaw-process-running-p)
    (delete-process openclaw--process))
  (setq openclaw--process nil
        openclaw--output-buffer ""
        openclaw--initialized nil
        openclaw--acp-session-id nil
        openclaw--pending-calls (make-hash-table :test 'equal)))

(defun openclaw-process-send (json-obj)
  "Serialize JSON-OBJ and write as NDJSON line to subprocess stdin."
  (openclaw-process-ensure)
  (let ((line (concat (json-serialize json-obj) "\n")))
    (process-send-string openclaw--process line)))

(defun openclaw-process-filter (proc string)
  "Handle output from PROC. Parse complete NDJSON lines from STRING."
  (setq openclaw--output-buffer (concat openclaw--output-buffer string))
  (let ((lines (split-string openclaw--output-buffer "\n")))
    ;; Last element may be incomplete — keep it in the buffer
    (setq openclaw--output-buffer (car (last lines)))
    (dolist (line (butlast lines))
      (let ((trimmed (string-trim line)))
        (when (> (length trimmed) 0)
          (condition-case err
              (let ((msg (json-parse-string trimmed
                                           :object-type 'alist
                                           :array-type 'list
                                           :null-object nil
                                           :false-object nil)))
                (run-with-timer 0 nil #'openclaw-protocol-handle-message msg))
            (error
             (message "OpenClaw: JSON parse error: %s | line: %s"
                      (error-message-string err)
                      (substring trimmed 0 (min 80 (length trimmed))))))))))
  (ignore proc))

(defun openclaw-process-sentinel (proc event)
  "Handle subprocess PROC lifecycle events (EVENT)."
  (let ((status (string-trim event)))
    (cond
     ((string-prefix-p "finished" status)
      (message "OpenClaw: process finished")
      (openclaw-chat--on-process-exit "Process finished"))
     ((string-prefix-p "exited" status)
      (message "OpenClaw: process exited: %s" status)
      (openclaw-chat--on-process-exit (format "Process exited: %s" status)))
     ((string-prefix-p "killed" status)
      (message "OpenClaw: process killed"))
     (t
      (message "OpenClaw: process event: %s" status))))
  ;; Reset all state variables on process death.
  (setq openclaw--process nil
        openclaw--initialized nil
        openclaw--acp-session-id nil
        openclaw--awaiting-response nil) ; <-- The fix
  (ignore proc))

(provide 'openclaw-process)
;;; openclaw-process.el ends here
