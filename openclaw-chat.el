;;; openclaw-chat.el --- Chat UI for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; Main chat interface with sidebar window, streaming output, and input.
;;; Code:

(require 'openclaw-ui)
(require 'openclaw-protocol)
(require 'openclaw-process)

(defvar openclaw--prompt-marker nil
  "Marker for the start of user input area.")

(defvar openclaw--output-end-marker nil
  "Marker for where to insert new output.")

(defvar openclaw--current-message-buffer nil
  "Accumulating assistant message text.")

(defvar openclaw--awaiting-response nil
  "Non-nil when waiting for agent response.")

(defvar openclaw--input-history nil
  "List of previous inputs.")

(defvar openclaw--input-history-pos 0
  "Current position in input history.")

(defvar openclaw-chat-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'openclaw-chat-send)
    (define-key map (kbd "C-c C-c") #'openclaw-chat-abort)
    (define-key map (kbd "C-c C-k") #'openclaw-chat-clear)
    (define-key map (kbd "C-c C-s") #'openclaw-sessions-switch)
    (define-key map (kbd "C-c C-n") #'openclaw-sessions-new)
    (define-key map (kbd "M-p") #'openclaw-chat-history-previous)
    (define-key map (kbd "M-n") #'openclaw-chat-history-next)
    (define-key map (kbd "TAB") #'openclaw-commands-complete)
    map)
  "Keymap for `openclaw-chat-mode'.")

(define-derived-mode openclaw-chat-mode fundamental-mode "OpenClaw"
  "Major mode for OpenClaw chat interface."
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (setq-local buffer-read-only nil)
  (setq-local openclaw--current-message-buffer "")
  (setq-local openclaw--awaiting-response nil)
  (use-local-map openclaw-chat-mode-map))

(defun openclaw-chat-toggle ()
  "Toggle the OpenClaw chat sidebar."
  (interactive)
  (let ((buf (get-buffer "*OpenClaw*")))
    (if (and buf (get-buffer-window buf))
        (delete-window (get-buffer-window buf))
      (openclaw-chat-open))))

(defun openclaw-chat-open ()
  "Open the OpenClaw chat sidebar."
  (interactive)
  (let ((buf (get-buffer-create "*OpenClaw*")))
    (with-current-buffer buf
      (unless (eq major-mode 'openclaw-chat-mode)
        (openclaw-chat-mode)
        (openclaw-chat--setup-buffer)))
    (let ((win (display-buffer-in-side-window
                buf
                `((side . right)
                  (window-width . ,openclaw-window-width)
                  (window-parameters . ((no-delete-other-windows . t)))))))
      (select-window win)
      (goto-char (point-max))
      (openclaw-process-ensure))))

(defun openclaw-chat--setup-buffer ()
  "Initialize the chat buffer structure."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "OpenClaw Chat\n"
                        'face 'openclaw-header-face
                        'read-only t))
    (insert (propertize (openclaw-ui-make-separator 60)
                        'read-only t))
    (insert "\n\n")
    (setq openclaw--output-end-marker (point-marker))
    (set-marker-insertion-type openclaw--output-end-marker nil)
    (insert "\n")
    (insert (propertize (openclaw-ui-make-separator 60)
                        'read-only t
                        'rear-nonsticky t))
    (insert "\n")
    (insert (propertize "▶ "
                        'face 'openclaw-prompt-face
                        'read-only t
                        'rear-nonsticky t
                        'front-sticky t))
    (setq openclaw--prompt-marker (point-marker))
    (set-marker-insertion-type openclaw--prompt-marker t))
  (openclaw-chat--update-header))

(defun openclaw-chat--update-header ()
  "Update the header line with current session info."
  (with-current-buffer (get-buffer-create "*OpenClaw*")
    (setq header-line-format
          (openclaw-ui-header-line
           openclaw-default-agent
           (or openclaw--acp-session-id "connecting...")
           "sonnet-4"
           nil))))

(defun openclaw-chat--get-input ()
  "Get the current input text from the prompt area."
  (with-current-buffer "*OpenClaw*"
    (buffer-substring-no-properties openclaw--prompt-marker (point-max))))

(defun openclaw-chat--clear-input ()
  "Clear the input area."
  (with-current-buffer "*OpenClaw*"
    (let ((inhibit-read-only t))
      (delete-region openclaw--prompt-marker (point-max)))))

(defun openclaw-chat--append-output (text &optional face)
  "Append TEXT to the output area with optional FACE."
  (with-current-buffer (get-buffer-create "*OpenClaw*")
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char openclaw--output-end-marker)
        (insert (if face
                    (propertize text 'face face)
                  text))
        (set-marker openclaw--output-end-marker (point))))
    (openclaw-chat--scroll-to-bottom)))

(defun openclaw-chat--scroll-to-bottom ()
  "Scroll chat window to bottom."
  (let ((win (get-buffer-window "*OpenClaw*")))
    (when win
      (with-selected-window win
        (goto-char (point-max))))))

(defun openclaw-chat-send ()
  "Send the current input to the agent."
  (interactive)
  (when openclaw--awaiting-response
    (message "OpenClaw: already waiting for response")
    (cl-return-from openclaw-chat-send))
  (let ((input (string-trim (openclaw-chat--get-input))))
    (when (string-empty-p input)
      (cl-return-from openclaw-chat-send))
    ;; Check for slash commands
    (when (string-prefix-p "/" input)
      (openclaw-commands-execute-input input)
      (openclaw-chat--clear-input)
      (cl-return-from openclaw-chat-send))
    ;; Regular message
    (push input openclaw--input-history)
    (setq openclaw--input-history-pos 0)
    (openclaw-chat--clear-input)
    (openclaw-chat--append-output
     (format "[%s] You\n" (openclaw-ui-format-timestamp))
     'openclaw-timestamp-face)
    (openclaw-chat--append-output
     (concat (openclaw-ui-render-markdown input) "\n\n")
     'openclaw-user-face)
    (openclaw-chat--send-prompt input)))

(defun openclaw-chat--send-prompt (text)
  "Send TEXT as a prompt to the agent via ACP."
  (unless openclaw--acp-session-id
    (message "OpenClaw: no session yet, waiting...")
    (cl-return-from openclaw-chat--send-prompt))
  (setq openclaw--awaiting-response t
        openclaw--current-message-buffer "")
  (openclaw-chat--append-output
   (format "[%s] Assistant\n" (openclaw-ui-format-timestamp))
   'openclaw-timestamp-face)
  (let* ((context-parts (openclaw-context-build-prompt-parts))
         (prompt-parts (append context-parts
                              `(((type . "text")
                                 (text . ,text))))))
    (openclaw-context-clear)
    (openclaw-rpc-call
     "session/prompt"
     `((sessionId . ,openclaw--acp-session-id)
       (prompt . ,prompt-parts))
     (lambda (result err)
       (openclaw-chat--on-prompt-complete result err)))))

(defun openclaw-chat--on-prompt-complete (result err)
  "Handle completion of session/prompt with RESULT or ERR."
  (setq openclaw--awaiting-response nil)
  (when openclaw--current-message-buffer
    (openclaw-chat--append-output "\n\n"))
  (setq openclaw--current-message-buffer "")
  (when err
    (openclaw-chat--append-output
     (format "[Error: %s]\n\n" err)
     'openclaw-error-face))
  (when result
    (let ((stop-reason (alist-get 'stopReason result)))
      (when (equal stop-reason "cancelled")
        (openclaw-chat--append-output "[Cancelled]\n\n" 'openclaw-tool-face)))))

(defun openclaw-chat-abort ()
  "Abort the current agent run."
  (interactive)
  (when openclaw--awaiting-response
    (openclaw-rpc-call
     "session/cancel"
     `((sessionId . ,openclaw--acp-session-id))
     (lambda (_result _err)
       (message "OpenClaw: cancelled"))))
  (setq openclaw--awaiting-response nil))

(defun openclaw-chat-clear ()
  "Clear the chat display."
  (interactive)
  (with-current-buffer (get-buffer-create "*OpenClaw*")
    (let ((inhibit-read-only t))
      (delete-region (point-min) openclaw--output-end-marker)
      (goto-char (point-min))
      (insert "\n")
      (set-marker openclaw--output-end-marker (point)))))

(defun openclaw-chat-history-previous ()
  "Replace input with previous history item."
  (interactive)
  (when (< openclaw--input-history-pos (length openclaw--input-history))
    (cl-incf openclaw--input-history-pos)
    (openclaw-chat--clear-input)
    (insert (nth (1- openclaw--input-history-pos) openclaw--input-history))))

(defun openclaw-chat-history-next ()
  "Replace input with next history item."
  (interactive)
  (when (> openclaw--input-history-pos 1)
    (cl-decf openclaw--input-history-pos)
    (openclaw-chat--clear-input)
    (insert (nth (1- openclaw--input-history-pos) openclaw--input-history))))

(defun openclaw-chat--on-ready ()
  "Called when the ACP session is ready."
  (openclaw-chat--update-header)
  (with-current-buffer (get-buffer-create "*OpenClaw*")
    (openclaw-chat--append-output
     (format "[Connected - session ready]\n\n")
     'openclaw-tool-face)))

(defun openclaw-chat--on-process-exit (reason)
  "Called when the subprocess exits with REASON."
  (with-current-buffer (get-buffer-create "*OpenClaw*")
    (openclaw-chat--append-output
     (format "\n[Process exited: %s]\n" reason)
     'openclaw-error-face)))

(defun openclaw-chat--on-session-update (params)
  "Handle session/update notification with PARAMS."
  (let* ((update (alist-get 'update params))
         (session-update (alist-get 'sessionUpdate update)))
    (pcase session-update
      ("agent_message_chunk"
       (let* ((content (alist-get 'content update))
              (content-type (alist-get 'type content))
              (text (alist-get 'text content)))
         (when (equal content-type "text")
           (setq openclaw--current-message-buffer
                 (concat openclaw--current-message-buffer text))
           (openclaw-chat--append-output
            (openclaw-ui-render-markdown-inline text)))))
      ("tool_call"
       (let ((title (alist-get 'title update))
             (status (alist-get 'status update)))
         (openclaw-chat--append-output
          (format "\n[Tool: %s (%s)]\n" title status)
          'openclaw-tool-face)))
      ("tool_call_update"
       (let ((tool-id (alist-get 'toolCallId update))
             (status (alist-get 'status update)))
         (openclaw-chat--append-output
          (format "[Tool %s: %s]\n" tool-id status)
          'openclaw-tool-face)))
      ("completed"
       nil)
      (_
       (message "OpenClaw: unknown session update: %s" session-update)))))

(defun openclaw-chat-handle-permission-request (id params)
  "Handle permission request from agent with ID and PARAMS."
  (let* ((tool-call (alist-get 'toolCall params))
         (title (alist-get 'title tool-call))
         (options (alist-get 'options params))
         (option-names (mapcar (lambda (opt) (alist-get 'name opt)) options))
         (choice (completing-read
                  (format "Permission: %s? " title)
                  option-names
                  nil t)))
    (let* ((selected-opt (cl-find choice options
                                  :test #'equal
                                  :key (lambda (o) (alist-get 'name o))))
           (option-id (alist-get 'optionId selected-opt)))
      (openclaw-process-send
       `((jsonrpc . "2.0")
         (id . ,id)
         (result . ((outcome . ((outcome . "selected")
                                (optionId . ,option-id))))))))))

;; Register session/update notification handler
(openclaw-protocol-register-notification
 "session/update"
 #'openclaw-chat--on-session-update)

(provide 'openclaw-chat)
;;; openclaw-chat.el ends here
