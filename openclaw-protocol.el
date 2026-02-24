;;; openclaw-protocol.el --- JSON-RPC 2.0 / ACP protocol for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; JSON-RPC 2.0 over NDJSON.  Handles request/response correlation and
;; notification dispatch for the ACP protocol used by `openclaw acp`.
;;; Code:

(defvar openclaw--pending-calls (make-hash-table :test 'equal)
  "Hash table mapping request id -> callback (id . callback).")

(defvar openclaw--request-counter 0
  "Counter for generating unique request IDs.")

(defvar openclaw--initialized nil
  "Non-nil when the ACP handshake has completed.")

(defvar openclaw--acp-session-id nil
  "Current ACP session ID returned by session/new or session/list.")

(defvar openclaw--notification-handlers (make-hash-table :test 'equal)
  "Hash table mapping method string -> handler function.")

(defun openclaw--gen-id ()
  "Generate a unique request ID."
  (format "req-%d-%d"
          (cl-incf openclaw--request-counter)
          (random 9999)))

(defun openclaw-rpc-call (method params callback)
  "Send JSON-RPC 2.0 request METHOD with PARAMS.
CALLBACK is called with (result error) when response arrives."
  (let ((id (openclaw--gen-id)))
    (puthash id callback openclaw--pending-calls)
    (openclaw-process-send
     `((jsonrpc . "2.0")
       (id . ,id)
       (method . ,method)
       (params . ,params)))))

(defun openclaw-rpc-notify (method params)
  "Send JSON-RPC 2.0 notification METHOD with PARAMS (no response expected)."
  (openclaw-process-send
   `((jsonrpc . "2.0")
     (method . ,method)
     (params . ,params))))

(defun openclaw-protocol-register-notification (method handler)
  "Register HANDLER for notification METHOD."
  (puthash method handler openclaw--notification-handlers))

(defun openclaw-protocol-handle-message (msg)
  "Dispatch incoming MSG (an alist from JSON parse)."
  (let ((id     (alist-get 'id msg))
        (method (alist-get 'method msg))
        (result (alist-get 'result msg))
        (error  (alist-get 'error msg))
        (params (alist-get 'params msg)))
    (cond
     ;; Response to a request we sent
     ((and id (or result error))
      (let ((cb (gethash id openclaw--pending-calls)))
        (when cb
          (remhash id openclaw--pending-calls)
          (funcall cb result error))))
     ;; Notification from agent (no id, has method)
     ((and method (not id))
      (let ((handler (gethash method openclaw--notification-handlers)))
        (if handler
            (funcall handler params)
          (message "OpenClaw: unhandled notification: %s" method))))
     ;; Request from agent to client (has id and method)
     ((and id method)
      (openclaw-protocol-handle-agent-request id method params))
     (t
      (message "OpenClaw: unknown message shape: %S" msg)))))

(defun openclaw-protocol-handle-agent-request (id method params)
  "Handle agent-initiated request METHOD with PARAMS; respond with ID."
  (cond
   ((equal method "session/request_permission")
    (openclaw-chat-handle-permission-request id params))
   ((equal method "fs/read_text_file")
    (let* ((path (alist-get 'path params))
           (content (condition-case nil
                        (with-temp-buffer
                          (insert-file-contents path)
                          (buffer-string))
                      (error nil))))
      (openclaw-process-send
       `((jsonrpc . "2.0")
         (id . ,id)
         (result . ((content . ,(or content ""))))))))
   ((equal method "fs/write_text_file")
    (let* ((path (alist-get 'path params))
           (content (alist-get 'content params)))
      (condition-case err
          (with-temp-file path
            (insert (or content "")))
        (error (message "OpenClaw: write_text_file error: %s" err)))
      (openclaw-process-send
       `((jsonrpc . "2.0")
         (id . ,id)
         (result . ())))))
   (t
    (openclaw-process-send
     `((jsonrpc . "2.0")
       (id . ,id)
       (error . ((code . -32601)
                 (message . ,(format "Method not found: %s" method)))))))))

(defun openclaw-protocol-initialize ()
  "Perform ACP handshake: initialize, then new/resume session."
  (openclaw-rpc-call
   "initialize"
   `((protocolVersion . 1)
     (clientCapabilities . ((fs . ((readTextFile . t)
                                   (writeTextFile . t))))))
   (lambda (result _err)
     (if result
         (progn
           (message "OpenClaw: connected (protocol v%s)"
                    (or (alist-get 'protocolVersion result) "?"))
           (setq openclaw--initialized t)
           (openclaw-protocol-ensure-session))
       (message "OpenClaw: initialization failed")))))

(defun openclaw-protocol-ensure-session ()
  "Ensure we have an active ACP session ID."
  (if openclaw--acp-session-id
      (openclaw-chat--on-ready)
    (openclaw-rpc-call
     "session/new"
     `((cwd . ,(or default-directory "/tmp"))
       (mcpServers . []))
     (lambda (result _err)
       (if result
           (let ((sid (alist-get 'sessionId result)))
             (setq openclaw--acp-session-id sid)
             (message "OpenClaw: session ready (%s)" sid)
             (openclaw-chat--on-ready))
         (message "OpenClaw: session/new failed"))))))

(provide 'openclaw-protocol)
;;; openclaw-protocol.el ends here
