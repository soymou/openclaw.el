;;; openclaw-context.el --- Context injection for OpenClaw  -*- lexical-binding: t; -*-
;;; Commentary:
;; Add files, regions, and project context to agent prompts.
;;; Code:

(defvar openclaw--context-items nil
  "List of context items to include in next prompt.")

(defun openclaw-context-add-buffer ()
  "Add the current buffer to the context."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (let ((content (buffer-substring-no-properties (point-min) (point-max))))
          (push `((type . "file")
                  (path . ,file)
                  (content . ,content))
                openclaw--context-items)
          (message "OpenClaw: added %s to context" (file-name-nondirectory file)))
      (message "OpenClaw: buffer has no file"))))

(defun openclaw-context-add-region ()
  "Add the selected region to the context."
  (interactive)
  (if (use-region-p)
      (let* ((content (buffer-substring-no-properties (region-beginning) (region-end)))
             (file (or (buffer-file-name) "<buffer>"))
             (start (region-beginning))
             (end (region-end)))
        (push `((type . "region")
                (path . ,file)
                (start . ,start)
                (end . ,end)
                (content . ,content))
              openclaw--context-items)
        (message "OpenClaw: added region (%d chars) to context"
                 (length content)))
    (message "OpenClaw: no region selected")))

(defun openclaw-context-add-project ()
  "Add project file tree to context."
  (interactive)
  (let ((root (or (when (fboundp 'projectile-project-root)
                   (projectile-project-root))
                 (when (fboundp 'project-root)
                   (cdr (project-current)))
                 default-directory)))
    (push `((type . "project")
            (root . ,root))
          openclaw--context-items)
    (message "OpenClaw: added project %s to context" root)))

(defun openclaw-context-clear ()
  "Clear all pending context items."
  (setq openclaw--context-items nil))

(defun openclaw-context-build-prompt-parts ()
  "Convert context items to ACP prompt parts."
  (let ((parts '()))
    (dolist (item (reverse openclaw--context-items))
      (let ((item-type (alist-get 'type item)))
        (pcase item-type
          ("file"
           (let ((path (alist-get 'path item))
                 (content (alist-get 'content item)))
             (push `((type . "text")
                     (text . ,(format "[Context: %s]\n```\n%s\n```\n"
                                     (file-name-nondirectory path)
                                     content)))
                   parts)))
          ("region"
           (let ((path (alist-get 'path item))
                 (content (alist-get 'content item)))
             (push `((type . "text")
                     (text . ,(format "[Context: region from %s]\n```\n%s\n```\n"
                                     (file-name-nondirectory path)
                                     content)))
                   parts)))
          ("project"
           (let ((root (alist-get 'root item)))
             (push `((type . "text")
                     (text . ,(format "[Context: project at %s]\n" root)))
                   parts))))))
    parts))

(provide 'openclaw-context)
;;; openclaw-context.el ends here
