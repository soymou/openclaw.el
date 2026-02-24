;;; openclaw-commands.el --- Slash command system for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; Parse and execute /slash commands typed in the chat buffer.
;;; Code:

(require 'openclaw-protocol)
(require 'openclaw-sessions)

(defvar openclaw--commands nil
  "Alist of (name doc . handler) for registered slash commands.")

(defun openclaw-commands-register (name doc handler)
  "Register slash command NAME with DOC string and HANDLER function."
  (setq openclaw--commands
        (cons (list name doc handler)
              (cl-remove name openclaw--commands :key #'car :test #'equal))))

(defun openclaw-commands-parse (input)
  "Parse INPUT string.  Return (command . args) or nil if not a slash command."
  (when (string-prefix-p "/" input)
    (let* ((trimmed (string-trim (substring input 1)))
           (space (string-match " " trimmed))
           (cmd (if space (substring trimmed 0 space) trimmed))
           (args (if space (string-trim (substring trimmed (1+ space))) "")))
      (cons cmd args))))

(defun openclaw-commands-execute-input (input)
  "Parse INPUT as a slash command and execute it."
  (let ((parsed (openclaw-commands-parse input)))
    (if parsed
        (openclaw-commands-execute (car parsed) (cdr parsed))
      (message "OpenClaw: not a slash command: %s" input))))

(defun openclaw-commands-execute (command args)
  "Execute COMMAND with ARGS string."
  (let ((entry (cl-find command openclaw--commands :key #'car :test #'equal)))
    (if entry
        (funcall (nth 2 entry) args)
      (openclaw-chat--append-output
       (format "Unknown command: /%s. Type /help for commands.\n\n" command)
       'openclaw-error-face))))

(defun openclaw-commands-complete ()
  "Completion-at-point for slash commands in the input area."
  (interactive)
  (let* ((input (openclaw-chat--get-input))
         (bounds (when (string-prefix-p "/" input)
                   (cons openclaw--prompt-marker (point-max)))))
    (when bounds
      (let ((names (mapcar (lambda (e) (concat "/" (car e))) openclaw--commands)))
        (completion-at-point-functions-helper names (car bounds) (cdr bounds))))))

;; ---- Built-in commands ----

(openclaw-commands-register
 "/" "not a command"
 (lambda (_) nil))  ;; prevent empty-slash

(openclaw-commands-register
 "help" "Show available slash commands."
 (lambda (_args)
   (let ((buf (get-buffer-create "*OpenClaw Help*")))
     (with-current-buffer buf
       (erase-buffer)
       (insert "OpenClaw Slash Commands\n\n")
       (dolist (entry openclaw--commands)
         (insert (format "  /%-18s %s\n" (car entry) (cadr entry))))
       (goto-char (point-min))
       (read-only-mode 1))
     (display-buffer buf))))

(openclaw-commands-register
 "status" "Show current session status (tokens, model)."
 (lambda (_args)
   (openclaw-rpc-call
    "session/list"
    '()
    (lambda (result _err)
      (if result
          (let ((sessions (alist-get 'sessions result)))
            (openclaw-chat--append-output
             (format "[Status] %d session(s). Active: %s\n\n"
                     (length sessions)
                     (or openclaw--acp-session-id "none"))
             'openclaw-tool-face))
        (message "OpenClaw: status call failed"))))))

(openclaw-commands-register
 "model" "Switch model. Usage: /model <name>  (e.g. opus, sonnet)"
 (lambda (args)
   (if (string-empty-p args)
       (openclaw-chat--append-output
        "Usage: /model <name>  (e.g. opus, sonnet, haiku)\n\n"
        'openclaw-tool-face)
     (openclaw-rpc-call
      "session/set_model"
      `((sessionId . ,openclaw--acp-session-id)
        (modelId . ,args))
      (lambda (result _err)
        (if result
            (openclaw-chat--append-output
             (format "[Model set to: %s]\n\n" args)
             'openclaw-tool-face)
          (openclaw-chat--append-output
           (format "[Failed to set model: %s]\n\n" args)
           'openclaw-error-face)))))))

(openclaw-commands-register
 "thinking" "Set thinking level. Usage: /thinking <off|minimal|low|medium|high>"
 (lambda (args)
   (let ((valid '("off" "minimal" "low" "medium" "high")))
     (if (member args valid)
         (openclaw-rpc-call
          "session/set_mode"
          `((sessionId . ,openclaw--acp-session-id)
            (modeId . ,args))
          (lambda (result _err)
            (if result
                (openclaw-chat--append-output
                 (format "[Thinking set to: %s]\n\n" args)
                 'openclaw-tool-face)
              (openclaw-chat--append-output
               "[Failed to set thinking level]\n\n"
               'openclaw-error-face))))
       (openclaw-chat--append-output
        (format "[Invalid thinking level: %s. Valid: %s]\n\n"
                args (string-join valid ", "))
        'openclaw-error-face)))))

(openclaw-commands-register
 "session" "List or switch sessions. Usage: /session [key]"
 (lambda (args)
   (if (string-empty-p args)
       (openclaw-sessions-list)
     (setq openclaw--acp-session-id args)
     (openclaw-chat--update-header)
     (openclaw-chat--append-output
      (format "[Switched to session: %s]\n\n" args)
      'openclaw-tool-face))))

(openclaw-commands-register
 "new" "Create a new session."
 (lambda (_args)
   (openclaw-sessions-new)))

(openclaw-commands-register
 "clear" "Clear the chat display."
 (lambda (_args)
   (openclaw-chat-clear)))

(openclaw-commands-register
 "stop" "Abort the current agent run."
 (lambda (_args)
   (openclaw-chat-abort)
   (openclaw-chat--append-output
    "[Stopped]\n\n" 'openclaw-tool-face)))

(openclaw-commands-register
 "context" "Show pending context items."
 (lambda (_args)
   (if openclaw--context-items
       (openclaw-chat--append-output
        (format "[Context: %d item(s) pending]\n%s\n\n"
                (length openclaw--context-items)
                (mapconcat
                 (lambda (item)
                   (let ((path (alist-get 'path item))
                         (type (alist-get 'type item)))
                     (format "  - [%s] %s" type
                             (or (and path (file-name-nondirectory path)) "?"))))
                 (reverse openclaw--context-items) "\n"))
        'openclaw-tool-face)
     (openclaw-chat--append-output
      "[No context items pending]\n\n" 'openclaw-tool-face))))

(openclaw-commands-register
 "reconnect" "Restart the openclaw acp subprocess."
 (lambda (_args)
   (openclaw-process-stop)
   (run-with-timer 0.5 nil #'openclaw-process-start)
   (openclaw-chat--append-output
    "[Reconnecting...]\n\n" 'openclaw-tool-face)))

(provide 'openclaw-commands)
;;; openclaw-commands.el ends here
