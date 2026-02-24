;;; openclaw-ui.el --- UI utilities for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; Faces, markdown rendering helpers, and UI formatting utilities.
;;; Code:

;; --- Faces ---

(defface openclaw-user-face
  '((t (:foreground "#7ECFFF" :weight bold)))
  "Face for user messages in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-assistant-face
  '((t (:foreground "#D4D4D4")))
  "Face for assistant messages in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-tool-face
  '((t (:foreground "#FFB86C" :slant italic)))
  "Face for tool call notifications in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-header-face
  '((t (:foreground "#A6E22E" :weight bold)))
  "Face for section headers in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-prompt-face
  '((t (:foreground "#FF79C6" :weight bold)))
  "Face for the input prompt in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-timestamp-face
  '((t (:foreground "#6272A4" :height 0.85)))
  "Face for timestamps in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-separator-face
  '((t (:foreground "#44475A")))
  "Face for separator lines in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-code-face
  '((t (:inherit fixed-pitch :background "#282A36" :foreground "#F8F8F2")))
  "Face for inline code in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-code-block-face
  '((t (:inherit fixed-pitch :background "#21222C" :foreground "#F8F8F2")))
  "Face for code blocks in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-error-face
  '((t (:foreground "#FF5555" :weight bold)))
  "Face for error messages in OpenClaw chat."
  :group 'openclaw)

(defface openclaw-header-line-face
  '((t (:background "#282A36" :foreground "#BD93F9" :weight bold)))
  "Face for the header line of the OpenClaw chat buffer."
  :group 'openclaw)

;; --- Formatting utilities ---

(defun openclaw-ui-format-timestamp ()
  "Return current time as HH:MM string."
  (format-time-string "%H:%M"))

(defun openclaw-ui-make-separator (&optional width)
  "Return a separator string of WIDTH chars with `openclaw-separator-face`."
  (let ((w (or width 60)))
    (propertize (make-string w ?─) 'face 'openclaw-separator-face)))

(defun openclaw-ui-header-line (agent session model thinking)
  "Generate header-line-format string showing AGENT, SESSION, MODEL, THINKING."
  (list
   (propertize " 🦞 " 'face 'openclaw-header-line-face)
   (propertize (or agent "?") 'face '(:foreground "#FF79C6" :weight bold))
   (propertize " │ " 'face 'openclaw-separator-face)
   (propertize (or session "no session") 'face '(:foreground "#8BE9FD"))
   (propertize " │ " 'face 'openclaw-separator-face)
   (propertize (or model "model?") 'face '(:foreground "#50FA7B"))
   (when thinking
     (concat
      (propertize " │ " 'face 'openclaw-separator-face)
      (propertize (format "thinking:%s" thinking) 'face '(:foreground "#FFB86C"))))))

;; --- Markdown rendering ---

(defun openclaw-ui-render-markdown-inline (text)
  "Return TEXT with basic inline markdown rendered as Emacs text properties."
  (with-temp-buffer
    (insert text)
    ;; Code spans: `code`
    (goto-char (point-min))
    (while (re-search-forward "`\\([^`\n]+\\)`" nil t)
      (let ((content (match-string 1))
            (beg (match-beginning 0))
            (end (match-end 0)))
        (replace-match (propertize content 'face 'openclaw-code-face) t t)))
    ;; Bold: **text**
    (goto-char (point-min))
    (while (re-search-forward "\\*\\*\\([^*\n]+\\)\\*\\*" nil t)
      (replace-match (propertize (match-string 1) 'face '(:weight bold)) t t))
    ;; Italic: *text* or _text_
    (goto-char (point-min))
    (while (re-search-forward "\\*\\([^*\n]+\\)\\*" nil t)
      (replace-match (propertize (match-string 1) 'face '(:slant italic)) t t))
    (buffer-string)))

(defun openclaw-ui-render-markdown (text)
  "Return TEXT with markdown formatting applied as text properties."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    ;; Headers
    (while (re-search-forward "^\\(#{1,3}\\) \\(.*\\)$" nil t)
      (let ((content (match-string 2)))
        (replace-match
         (propertize content 'face 'openclaw-header-face) t t)))
    ;; Code blocks: ```lang\n...\n```
    (goto-char (point-min))
    (while (re-search-forward "^```[^\n]*\n" nil t)
      (let ((block-start (match-beginning 0))
            (code-start (match-end 0)))
        (when (re-search-forward "^```\n?" nil t)
          (let ((code-end (match-beginning 0))
                (block-end (match-end 0)))
            (let* ((code (buffer-substring-no-properties code-start code-end))
                   (rendered (propertize code 'face 'openclaw-code-block-face)))
              (delete-region block-start block-end)
              (goto-char block-start)
              (insert "\n" rendered "\n")
              (goto-char block-start)))))
    ;; Inline code: `code`
    (goto-char (point-min))
    (while (re-search-forward "`\\([^`\n]+\\)`" nil t)
      (replace-match (propertize (match-string 1) 'face 'openclaw-code-face) t t))
    ;; Bold: **text**
    (goto-char (point-min))
    (while (re-search-forward "\\*\\*\\([^*\n]+\\)\\*\\*" nil t)
      (replace-match (propertize (match-string 1) 'face '(:weight bold)) t t))
    ;; Italic: *text*
    (goto-char (point-min))
    (while (re-search-forward "\\*\\([^*\n]+\\)\\*" nil t)
      (replace-match (propertize (match-string 1) 'face '(:slant italic)) t t)))
    (buffer-string)))

(provide 'openclaw-ui)
;;; openclaw-ui.el ends here
