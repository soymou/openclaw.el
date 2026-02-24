;;; openclaw.el --- OpenClaw AI assistant integration for Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2026
;; Author: Mou
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: ai, assistant, tools
;; URL: https://github.com/openclaw/openclaw.el

;;; Commentary:
;; Full Emacs integration for the OpenClaw AI assistant.
;;
;; Connects to a remote (or local) OpenClaw Gateway via `openclaw acp'`,
;; which uses JSON-RPC 2.0 over NDJSON on stdin/stdout.
;;
;; Quick start:
;;   1. Configure the gateway URL and token (see below)
;;   2. M-x openclaw-setup-keys     ; bind C-c o prefix
;;   3. C-c o o                     ; open chat sidebar
;;
;; Minimal configuration:
;;   (setq openclaw-gateway-url   "ws://YOUR_SERVER:18789")
;;   (setq openclaw-gateway-token "YOUR_TOKEN")
;;
;; Full use-package example:
;;   (use-package openclaw
;;     :load-path "~/Desktop/openclaw.el"
;;     :config
;;     (setq openclaw-executable    "/opt/homebrew/bin/openclaw"
;;           openclaw-gateway-url   "ws://192.168.1.100:18789"
;;           openclaw-gateway-token "secret")
;;     (openclaw-setup-keys))

;;; Code:

(require 'cl-lib)
(require 'json)

;; Load sub-modules in dependency order
(require 'openclaw-ui)
(require 'openclaw-process)
(require 'openclaw-protocol)
(require 'openclaw-sessions)
(require 'openclaw-context)
(require 'openclaw-chat)
(require 'openclaw-commands)

;; ---------------------------------------------------------------------------
;; Customization
;; ---------------------------------------------------------------------------

(defgroup openclaw nil
  "OpenClaw AI assistant integration."
  :group 'tools
  :prefix "openclaw-")

(defcustom openclaw-executable "/opt/homebrew/bin/openclaw"
  "Path to the openclaw executable."
  :type 'string
  :group 'openclaw)

(defcustom openclaw-gateway-url nil
  "WebSocket URL of the OpenClaw Gateway, e.g. \"ws://192.168.1.100:18789\".
Required when the gateway is on a remote machine.
Nil means `openclaw acp\' will try to connect to the default local gateway."
  :type '(choice (string :tag "Remote URL  (ws://host:port)")
                 (const  :tag "Local gateway (default)" nil))
  :group 'openclaw)

(defcustom openclaw-gateway-token nil
  "Auth token for the OpenClaw Gateway.
Must match the token configured on the gateway (OPENCLAW_GATEWAY_TOKEN).
Nil means no token is sent."
  :type '(choice (string :tag "Token")
                 (const  :tag "None" nil))
  :group 'openclaw)

(defcustom openclaw-default-agent "main"
  "Default agent ID to use when creating new sessions."
  :type 'string
  :group 'openclaw)

(defcustom openclaw-window-width 0.35
  "Width of the OpenClaw chat sidebar as a fraction of the frame width."
  :type 'float
  :group 'openclaw)

;; ---------------------------------------------------------------------------
;; Global key prefix
;; ---------------------------------------------------------------------------



;; ---------------------------------------------------------------------------
;; Setup wizard
;; ---------------------------------------------------------------------------

(defun openclaw-setup ()
  "Interactive setup wizard for OpenClaw connection settings."
  (interactive)
  (let* ((url (read-string "Gateway URL (e.g. ws://192.168.1.100:18789): "
                           (or openclaw-gateway-url "")))
         (token (read-passwd "Gateway token (leave blank if none): ")))
    (setq openclaw-gateway-url   (if (string-empty-p url) nil url))
    (setq openclaw-gateway-token (if (string-empty-p token) nil token))
    (message "OpenClaw: configured. Run M-x openclaw-chat-toggle to open chat.")))

(provide 'openclaw)
;;; openclaw.el ends here
