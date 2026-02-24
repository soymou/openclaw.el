;;; openclaw-sessions.el --- Session management for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; List, switch, and create OpenClaw sessions.
;;; Code:

(require 'openclaw-protocol)

(defun openclaw-sessions-list ()
  "List all sessions from the agent."
  (interactive)
  (openclaw-rpc-call
   "session/list"
   '()
   (lambda (result _err)
     (if result
         (let* ((sessions (alist-get 'sessions result))
                (buf (get-buffer-create "*OpenClaw Sessions*")))
           (with-current-buffer buf
             (erase-buffer)
             (insert "OpenClaw Sessions\n\n")
             (if (zerop (length sessions))
                 (insert "No sessions found.\n")
               (dolist (sess sessions)
                 (let ((sid (alist-get 'sessionId sess))
                       (title (alist-get 'title sess))
                       (updated (alist-get 'updatedAt sess)))
                   (insert (format "- [%s] %s\n" sid (or title sid)))
                   (when updated
                     (insert (format "  Updated: %s\n" updated))))))
             (goto-char (point-min))
             (read-only-mode 1)
             (display-buffer buf)))
       (message "OpenClaw: failed to list sessions")))))

(defun openclaw-sessions-switch ()
  "Switch to a different session."
  (interactive)
  (openclaw-rpc-call
   "session/list"
   '()
   (lambda (result _err)
     (if result
         (let* ((sessions (alist-get 'sessions result))
                (titles (mapcar (lambda (s)
                                 (cons (or (alist-get 'title s)
                                          (alist-get 'sessionId s))
                                      (alist-get 'sessionId s)))
                               sessions))
                (choice (completing-read "Switch to session: " titles nil t)))
           (let ((sid (cdr (assoc choice titles))))
             (setq openclaw--acp-session-id sid)
             (openclaw-chat--update-header)
             (message "OpenClaw: switched to session %s" sid)))
       (message "OpenClaw: failed to list sessions")))))

(defun openclaw-sessions-new ()
  "Create a new session."
  (interactive)
  (openclaw-rpc-call
   "session/new"
   `((cwd . ,(or default-directory "/tmp"))
     (mcpServers . []))
   (lambda (result _err)
     (if result
         (let ((sid (alist-get 'sessionId result)))
           (setq openclaw--acp-session-id sid)
           (openclaw-chat--update-header)
           (openclaw-chat-clear)
           (message "OpenClaw: new session %s" sid))
       (message "OpenClaw: failed to create session")))))

(provide 'openclaw-sessions)
;;; openclaw-sessions.el ends here
