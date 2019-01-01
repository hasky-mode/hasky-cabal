;;; hasky-cabal.el --- Interface to the Cabal package manager -*- lexical-binding: t; -*-
;;
;; Copyright © 2018–2019 Mark Karpov <markkarpov92@gmail.com>
;;
;; Author: Mark Karpov <markkarpov92@gmail.com>
;; URL: https://github.com/hasky-mode/hasky-cabal
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.4") (f "0.18.0") (magit-popup "2.10"))
;; Keywords: tools, haskell
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation, either version 3 of the License, or (at your
;; option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
;; Public License for more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; TODO

;;; Code:

(require 'cl-lib)
(require 'f)
(require 'magit-popup)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Settings & variables

(defgroup hasky-cabal nil
  "Interface to the Cabal package manager."
  :group  'programming
  :tag    "Hasky Cabal"
  :prefix "hasky-cabal-"
  :link   '(url-link :tag "GitHub"
                     "https://github.com/hasky-mode/hasky-cabal"))

(defface hasky-cabal-project-name
  '((t (:inherit font-lock-function-name-face)))
  "Face used to display name of current project.")

(defface hasky-cabal-project-version
  '((t (:inherit font-lock-doc-face)))
  "Face used to display version of current project.")

(defvar hasky-cabal--last-directory nil
  "Path to project's directory last time `hasky-cabal--prepare' was called.

This is mainly used to check when we need to reload/re-parse
project-local settings that user might have.")

(defvar hasky-cabal--cabal-mod-time nil
  "Time of last modification of \"*.cabal\" file.

This is usually set by `hasky-cabal--prepare'.")

(defvar hasky-cabal--project-name nil
  "Name of current project extracted from \"*.cabal\" file.

This is usually set by `hasky-cabal--prepare'.")

(defvar hasky-cabal--project-version nil
  "Version of current project extracted from \"*.cabal\" file.

This is usually set by `hasky-cabal--prepare'.")

(defvar hasky-cabal--project-targets nil
  "List of build targets (strings) extracted from \"*.cabal\" file.

This is usually set by `hasky-cabal--prepare'.")

(defvar hasky-cabal--package-action-package nil
  "This variable is temporarily bound to name of package.")

(defcustom hasky-cabal-executable nil
  "Path to Cabal executable.

If it's not NIL, this value is used in invocation of Cabal
commands instead of the standard \"cabal\" string.  Set this
variable if your Cabal is not on PATH.

Note that the path is quoted with `shell-quote-argument' before
being used to compose command line."
  :tag  "Path to Cabal Executable"
  :type '(choice (file :must-match t)
                 (const :tag "Use Default" nil)))

(defcustom hasky-cabal-config-dir "~/.cabal"
  "Path to Cabal configuration directory."
  :tag  "Path to Cabal configuration directory"
  :type 'directory)

(defcustom hasky-cabal-read-function #'completing-read
  "Function to be called when user has to choose from list of alternatives."
  :tag  "Completing Function"
  :type '(radio (function-item completing-read)))

(defcustom hasky-cabal-auto-target nil
  "Whether to automatically select the default build target."
  :tag  "Build auto-target"
  :type 'boolean)

(defcustom hasky-cabal-auto-open-coverage-reports nil
  "Whether to attempt to automatically open coverage report in browser."
  :tag  "Automatically open coverage reports"
  :type 'boolean)

(defcustom hasky-cabal-auto-open-haddocks nil
  "Whether to attempt to automatically open Haddocks in browser."
  :tag  "Automatically open Haddocks"
  :type 'boolean)

(defcustom hasky-cabal-auto-newest-version nil
  "Whether to install newest version of package without asking.

This is used in `hasky-cabal-package-action'."
  :tag  "Automatically install newest version"
  :type 'boolean)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Various utilities

(defun hasky-cabal--all-matches (regexp)
  "Return list of all stings matching REGEXP in current buffer."
  (let (matches
        (case-fold-search t))
    (goto-char (point-min))
    (while (re-search-forward regexp nil t)
      (push (match-string-no-properties 1) matches))
    (reverse matches)))

(defun hasky-cabal--parse-cabal-file (filename)
  "Parse \"*.cabal\" file with name FILENAME and set some variables.

The following variables are set:

  `hasky-cabal--project-name'
  `hasky-cabal--project-version'
  `hasky-cabal--project-targets'

This is used by `hasky-cabal--prepare'."
  (with-temp-buffer
    (insert-file-contents filename)
    ;; project name
    (setq hasky-cabal--project-name
          (car (hasky-cabal--all-matches
                "^[[:blank:]]*name:[[:blank:]]+\\([[:word:]-]+\\)")))
    ;; project version
    (setq hasky-cabal--project-version
          (car (hasky-cabal--all-matches
                "^[[:blank:]]*version:[[:blank:]]+\\([[:digit:]\\.]+\\)")))
    ;; project targets
    (setq
     hasky-cabal--project-targets
     (append
      ;; library
      (mapcar (lambda (_) (format "%s:lib:%s"
                                  hasky-cabal--project-name
                                  hasky-cabal--project-name))
              (hasky-cabal--all-matches
               "^[[:blank:]]*library[[:blank:]]*"))
      ;; executables
      (mapcar (lambda (x) (format "%s:exe:%s" hasky-cabal--project-name x))
              (hasky-cabal--all-matches
               "^[[:blank:]]*executable[[:blank:]]+\\([[:word:]-]+\\)"))
      ;; test suites
      (mapcar (lambda (x) (format "%s:test:%s" hasky-cabal--project-name x))
              (hasky-cabal--all-matches
               "^[[:blank:]]*test-suite[[:blank:]]+\\([[:word:]-]+\\)"))
      ;; benchmarks
      (mapcar (lambda (x) (format "%s:bench:%s" hasky-cabal--project-name x))
              (hasky-cabal--all-matches
               "^[[:blank:]]*benchmark[[:blank:]]+\\([[:word:]-]+\\)"))))))

(defun hasky-cabal--home-page-from-cabal-file (filename)
  "Parse package home page from \"*.cabal\" file with FILENAME."
  (with-temp-buffer
    (insert-file-contents filename)
    (or
     (car (hasky-cabal--all-matches
           "^[[:blank:]]*homepage:[[:blank:]]+\\(.+\\)"))
     (let ((without-scheme
            (car
             (hasky-cabal--all-matches
              "^[[:blank:]]*location:[[:blank:]]+.*:\\(.+\\)\\(\\.git\\)?"))))
       (when without-scheme
         (concat "https:" without-scheme))))))

(defun hasky-cabal--find-dir-of-file (regexp)
  "Find file whose name satisfies REGEXP traversing upwards.

Return absolute path to directory containing that file or NIL on
failure.  Returned path is guaranteed to have trailing slash."
  (let ((dir (f-traverse-upwards
              (lambda (path)
                (directory-files path t regexp t))
              (f-full default-directory))))
    (when dir
      (f-slash dir))))

(defun hasky-cabal--mod-time (filename)
  "Return time of last modification of file FILENAME."
  (nth 5 (file-attributes filename 'integer)))

(defun hasky-cabal--executable ()
  "Return path to cabal executable if it's available and NIL otherwise."
  (let ((default "cabal")
        (custom  hasky-cabal-executable))
    (cond ((executable-find default)     default)
          ((and custom (f-file? custom)) custom))))

(defun hasky-cabal--index-file ()
  "Get path to Hackage index file."
  (f-expand "packages/hackage.haskell.org/00-index.tar" hasky-cabal-config-dir))

(defun hasky-cabal--index-dir ()
  "Get path to directory that is to contain unpackaed Hackage index."
  (file-name-as-directory
   (f-expand "packages/hackage.haskell.org/00-index" hasky-cabal-config-dir)))

(defun hasky-cabal--index-stamp-file ()
  "Get path to Hackage index time stamp file."
  (f-expand "ts" (hasky-cabal--index-dir)))

(defun hasky-cabal--ensure-indices ()
  "Make sure that we have downloaded and untar-ed Hackage package indices.

This uses external ‘tar’ command, so it probably won't work on
Windows."
  (let ((index-file (hasky-cabal--index-file))
        (index-dir (hasky-cabal--index-dir))
        (index-stamp (hasky-cabal--index-stamp-file)))
    (unless (f-file? index-file)
      ;; No indices in place, need to run cabal update to get them.
      (message "Cannot find Hackage indices, trying to download them")
      (shell-command (concat (hasky-cabal--executable) " update")))
    (if (f-file? index-file)
        (when (or (not (f-file? index-stamp))
                  (time-less-p (hasky-cabal--mod-time index-stamp)
                               (hasky-cabal--mod-time index-file)))
          (f-mkdir index-dir)
          (let ((default-directory index-dir))
            (message "Extracting Hackage indices, please be patient")
            (shell-command
             (concat "tar -xf " (shell-quote-argument index-file))))
          (f-touch index-stamp)
          (message "Finished preparing Hackage indices"))
      (error "%s" "Failed to fetch indices, something is wrong!"))))

(defun hasky-cabal--packages ()
  "Return list of all packages in Hackage indices."
  (hasky-cabal--ensure-indices)
  (mapcar
   #'f-filename
   (f-entries (hasky-cabal--index-dir) #'f-directory?)))

(defun hasky-cabal--package-versions (package)
  "Return list of all available versions of PACKAGE."
  (mapcar
   #'f-filename
   (f-entries (f-expand package (hasky-cabal--index-dir))
              #'f-directory?)))

(defun hasky-cabal--latest-version (versions)
  "Return latest version from VERSIONS."
  (cl-reduce (lambda (x y) (if (version< y x) x y))
             versions))

(defun hasky-cabal--package-with-version (package version)
  "Render identifier of PACKAGE with VERSION."
  (concat package "-" version))

(defun hasky-cabal--completing-read (prompt &optional collection require-match)
  "Read user's input using `hasky-cabal-read-function'.

PROMPT is the prompt to show and COLLECTION represents valid
choices.  If REQUIRE-MATCH is not NIL, don't let user input
something different from items in COLLECTION.

COLLECTION is allowed to be a string, in this case it's
automatically wrapped to make it one-element list.

If COLLECTION contains \"none\", and user selects it, interpret
it as NIL.  If user aborts entering of the input, return NIL.

Finally, if COLLECTION is nil, plain `read-string' is used."
  (let* ((collection
          (if (listp collection)
              collection
            (list collection)))
         (result
          (if collection
              (funcall hasky-cabal-read-function
                       prompt
                       collection
                       nil
                       require-match
                       nil
                       nil
                       (car collection))
            (read-string prompt))))
    (unless (and (string= result "none")
                 (member result collection))
      result)))

(defun hasky-cabal--select-target (prompt)
  "Present the user with a choice of build target using PROMPT."
  (if hasky-cabal-auto-target
      hasky-cabal--project-name
    (hasky-cabal--completing-read
     prompt
     (cons hasky-cabal--project-name
           hasky-cabal--project-targets)
     t)))

(defun hasky-cabal--select-package-version (package)
  "Present the user with a choice of PACKAGE version."
  (let ((versions (hasky-cabal--package-versions package)))
    (if hasky-cabal-auto-newest-version
        (hasky-cabal--latest-version versions)
      (hasky-cabal--completing-read
       (format "Version of %s: " package)
       (cl-sort versions (lambda (x y) (version< y x)))
       t))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Preparation

(defun hasky-cabal--prepare ()
  "Locate, read, and parse configuration files and set various variables.

This commands searches for first \"*.cabal\" files traversing
directories upwards beginning with `default-directory'.  When
Cabal file is found, the following variables are set:

  `hasky-cabal--project-name'
  `hasky-cabal--project-version'
  `hasky-cabal--project-targets'

At the end, `hasky-cabal--last-directory' and
`hasky-cabal--cabal-mod-time' are set.  Note that this function
is smart enough to avoid re-parsing all the stuff every time.  It
can detect when we are in different project or when some files
have been changed since its last invocation.

Returned value is T on success and NIL on failure (when no
\"*.cabal\" files is found)."
  (let* ((project-directory
          (hasky-cabal--find-dir-of-file "^.+\.cabal$"))
         (cabal-file
          (car (and project-directory
                    (f-glob "*.cabal" project-directory)))))
    (when cabal-file
      (if (or (not hasky-cabal--last-directory)
              (not (f-same? hasky-cabal--last-directory
                            project-directory)))
          (progn
            ;; We are in different directory (or it's the first
            ;; invocation). This means we should unconditionally parse
            ;; everything without checking of date of last modification.
            (hasky-cabal--parse-cabal-file cabal-file)
            (setq hasky-cabal--cabal-mod-time (hasky-cabal--mod-time cabal-file))
            ;; Set last directory for future checks.
            (setq hasky-cabal--last-directory project-directory)
            t) ;; Return T on success.
        ;; We are in an already visited directory, so we don't need to reset
        ;; `hasky-cabal--last-directory' this time. We need to
        ;; reread/re-parse *.cabal file if it has been modified though.
        (when (time-less-p hasky-cabal--cabal-mod-time
                           (hasky-cabal--mod-time cabal-file))
          (hasky-cabal--parse-cabal-file cabal-file)
          (setq hasky-cabal--cabal-mod-time (hasky-cabal--mod-time cabal-file)))
        t))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Low-level construction of individual commands

(defun hasky-cabal--format-command (command &rest args)
  "Generate textual representation of a command.

COMMAND is the name of command and ARGS are arguments (strings).
Result is expected to be used as argument of `compile'."
  (mapconcat
   #'identity
   (append
    (list (shell-quote-argument (hasky-cabal--executable))
          command)
    (mapcar #'shell-quote-argument
            (remove nil args)))
   " "))

(defun hasky-cabal--exec-command (package dir command &rest args)
  "Call cabal for PACKAGE as if from DIR performing COMMAND with arguments ARGS.

Arguments are quoted if necessary and NIL arguments are ignored.
This uses `compile' internally."
  (let ((default-directory dir)
        (compilation-buffer-name-function
         (lambda (_major-mode)
           (format "*%s-%s*"
                   (downcase
                    (replace-regexp-in-string
                     "[[:space:]]"
                     "-"
                     (or package "hasky")))
                   "cabal"))))
    (compile (apply #'hasky-cabal--format-command command args))
    nil))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Variables

(defun hasky-cabal--cycle-bool-variable (symbol)
  "Cycle value of variable named SYMBOL."
  (custom-set-variables
   (list symbol (not (symbol-value symbol)))))

(defun hasky-cabal--format-bool-variable (symbol label)
  "Format a Boolean variable named SYMBOL, label it as LABEL."
  (let ((val (symbol-value symbol)))
    (concat
     (format "%s " label)
     (propertize
      (if val "enabled" "disabled")
      'face
      (if val
          'magit-popup-option-value
        'magit-popup-disabled-argument)))))

(defun hasky-cabal--acp (fun &rest args)
  "Apply FUN to ARGS partially and return a command."
  (lambda (&rest args2)
    (interactive)
    (apply fun (append args args2))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Popups

(magit-define-popup hasky-cabal-build-popup
  "Show popup for the \"cabal new-build\" command."
  'hasky-cabal
  :variables `((?a "auto-target"
                   ,(hasky-cabal--acp
                     #'hasky-cabal--cycle-bool-variable
                     'hasky-cabal-auto-target)
                   ,(hasky-cabal--acp
                     #'hasky-cabal--format-bool-variable
                     'hasky-cabal-auto-target
                     "Auto target")))
  :switches '((?d "Dry run"           "--dry-run")
              (?p "Enable profiling"  "--enable-profiling")
              (?s "Enable tests"      "--enable-tests")
              (?b "Enable benchmarks" "--enable-benchmarks"))
  :options  '((?f "Flags"             "--flags=")
              (?c "Constraint"        "--constraint="))
  :actions  '((?b "Build"             hasky-cabal-build)
              (?e "Bench"             hasky-cabal-bench)
              (?t "Test"              hasky-cabal-test))
  :default-action 'hasky-cabal-build)

(defun hasky-cabal-build (target &optional args)
  "Execute \"cabal new-build\" command for TARGET with ARGS."
  (interactive
   (list (hasky-cabal--select-target "Build target: ")
         (hasky-cabal-build-arguments)))
  (apply
   #'hasky-cabal--exec-command
   hasky-cabal--project-name
   hasky-cabal--last-directory
   "new-build"
   target
   args))

(defun hasky-cabal-bench (target &optional args)
  "Execute \"cabal new-build\" command for TARGET with ARGS."
  (interactive
   (list (hasky-cabal--select-target "Bench target: ")
         (hasky-cabal-build-arguments)))
  (apply
   #'hasky-cabal--exec-command
   hasky-cabal--project-name
   hasky-cabal--last-directory
   "new-bench"
   target
   args))

(defun hasky-cabal-test (target &optional args)
  "Execute \"cabal new-build\" command for TARGET with ARGS."
  (interactive
   (list (hasky-cabal--select-target "Test target: ")
         (hasky-cabal-build-arguments)))
  (apply
   #'hasky-cabal--exec-command
   hasky-cabal--project-name
   hasky-cabal--last-directory
   "new-test"
   target
   args))

;;;; haddock popup

(magit-define-popup hasky-cabal-root-popup
  "Show root popup with all supported commands."
  'hasky-cabal
  :actions  '((lambda ()
                (concat
                 (propertize hasky-cabal--project-name
                             'face 'hasky-cabal-project-name)
                 " "
                 (propertize hasky-cabal--project-version
                             'face 'hasky-cabal-project-version)
                 "\n\n"
                 (propertize "Commands"
                             'face 'magit-popup-heading)))
              (?b "Build"   hasky-cabal-build-popup)
              ;; (?i "Init"    hasky-cabal-init-popup)
              ;; (?s "Setup"   hasky-cabal-setup-popup)
              (?u "Update"  hasky-cabal-update)
              ;; (?g "Upgrade" hasky-cabal-upgrade-popup)
              ;; (?p "Upload"  hasky-cabal-upload-popup)
              ;; (?d "SDist"   hasky-cabal-sdist-popup)
              ;; (?x "Exec"    hasky-cabal-exec)
              (?c "Clean"   hasky-cabal-clean)
              (?l "Edit Cabal file" hasky-cabal-edit-cabal))
  :default-action 'hasky-cabal-build-popup
  :max-action-columns 3)

(defun hasky-cabal-update ()
  "Execute \"cabal update\"."
  (interactive)
  (hasky-cabal--exec-command
   hasky-cabal--project-name
   hasky-cabal--last-directory
   "update"))

(defun hasky-cabal-clean ()
  "Execute a command that deletes the \"dist-newstyle\" directory."
  (interactive)
  (let ((default-directory hasky-cabal--last-directory))
    (compile "rm -rvf dist-newstyle"))) ;; FIXME temporary hack

(defun hasky-cabal-edit-cabal ()
  "Open Cabal file of current project for editing."
  (interactive)
  (let ((cabal-file
         (car (and hasky-cabal--last-directory
                   (f-glob "*.cabal" hasky-cabal--last-directory)))))
    (when cabal-file
      (find-file cabal-file))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; High-level interface

;;;###autoload
(defun hasky-cabal-execute ()
  "Show the root-level popup allowing to choose and run a Cabal command."
  (interactive)
  (if (hasky-cabal--executable)
      (if (hasky-cabal--prepare)
          (hasky-cabal-root-popup)
        (message "Cannot locate ‘.cabal’ file"))
    (error "%s" "Cannot locate Cabal executable on this system")))

(provide 'hasky-cabal)

;;; hasky-cabal.el ends here
