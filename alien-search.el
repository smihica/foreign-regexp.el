;; alien-search.el --- search and replace with a help from alien programs.

;; Copyright (C) 2010 K-talo Miyazaki, all rights reserved.

;; Author: K-talo Miyazaki <Keitaro dot Miyazaki at gmail dot com>
;; Created: Sun Nov 28 23:50:45 2010 JST
;; Keywords: convenience emulations matching tools unix wp
;; Revision: $Id$
;; URL: 
;; GitHub: 

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; NOTE
;;
;; This library is just tested on Emacs 23.2.1 on Ubuntu 10.04
;; and Mac OS X 10.6.3, and won't be run with any version of XEmacs.

;;; Commentary:
;;
;; Overview
;; ========
;;
;;     *** CAUTION: THIS LIBRARY IS VERY EXPERIMENTAL!!! ***
;;
;; This library is an extension of `shell-command'.
;;
;; What this library does are:
;;
;;   1. Search a pattern from text in current buffer with external
;;      program(*) in manner of their regular expression.
;;      
;;      Also replaces text by a pattern and replacement strings
;;      when required.
;;
;;         (*) Currently, only perl is supported.
;;
;;   2. Browse the result of search operation produced by external program
;;      (...and apply the result of replacement operations if required)
;;      in Emacs user interface like `occur', `query-replace' and `isearch'.
;;
;; As a consequence, you can search and replace with regular expression
;; of the perl (and with that of another command in the future) in Emacs.
;;
;;
;; FYI: If you are interested in building regular expression by `re-builder'
;;      with perl syntax, try `re-builder-x.el' which has been distributed
;;      as a part of perl module package Emacs::PDE by Ye Wenbin at:
;;
;;          <http://cpansearch.perl.org/src/YEWENBIN/Emacs-PDE-0.2.16/>
;;
;;      and also see documentation of `re-builder-x.el' at:
;;
;;          <http://cpansearch.perl.org/src/YEWENBIN/Emacs-PDE-0.2.16/lisp/doc/pde.html#re_002dbuilder_002dx>
;;
;;
;; INSTALLING
;; ==========
;; To install this library, save this file to a directory in your
;; `load-path' (you can view the current `load-path' using "C-h v
;; load-path RET" within Emacs), then add the following line to your
;; .emacs startup file:
;;
;;    (require 'alien-search)
;;
;;
;; USING
;; =====
;; 
;;  M-x alien-search/query-replace RET PATTERN RET REPLACEMENT RET
;;  M-x alien-search/occur RET PATTERN RET
;;  M-x alien-search/isearch-forward RET PATTERN
;;  M-x alien-search/isearch-forward RET RET PATTERN RET
;;
;; 
;; WISH LIST
;; =========
;; - Toggle case (in)?sensitive search?
;;   or support `case-fold-search'?
;; - Set extra options to external commands?
;; - Better handling of exceptions from external commands,
;;   especially syntax error regarding to regular expression
;;   in isearch session.
;; - Better response.
;; - Write tests.

;;; Change Log:

;;; Code:

(eval-when-compile (require 'cl))


;;; ===========================================================================
;;;
;;;  Common variable and functions to alien-search operation.
;;;
;;; ===========================================================================

(defcustom alien-search/tmp-dir "/tmp/"
  "Directory in which temporally files should be written."
  :type 'string
  :group 'alien-search)

(defcustom alien-search/tmp-file-prefix "alien-search-"
  "Prefix name of temporally files."
  :type 'string
  :group 'alien-search)

(defvar alien-search/history  nil
  "History list for some commands that runs alien-search.")


;; ----------------------------------------------------------------------------
;;
;;  Functions
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/search-by-external-cmd cmd pattern &optional replacement 
;;                                       display-msg)                  => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/search-by-external-cmd (cmd pattern &optional replacement display-msg)
  "Scan current buffer with external command to detect matching
texts by PATTERN.

NOTES FOR DEVELOPERS: Variables in REPLACEMENT should be interpolated
                      on each match by external command."
  (let* ((base               (expand-file-name
                              alien-search/tmp-file-prefix
                              alien-search/tmp-dir))
         (fn-out-body        (make-temp-name base))
         (fn-out-pattern     (make-temp-name base))
         (fn-out-replacement (make-temp-name base))
         (fn-in-result       (make-temp-name base))
         (cmd-basename       (file-name-nondirectory cmd))
         (proc-output-buf    (get-buffer-create " *alien-search*"))
         (cur-buf            (current-buffer))
         (orig-file-modes    (default-file-modes))
         result)
    (unwind-protect
        (progn
          (set-default-file-modes #o0600)
          
          ;; Save informations, which have to be passed to 
          ;; external command, to temporally files.
          (with-temp-file fn-out-body
            (set-buffer-file-coding-system 'utf-8-unix)
            (insert (with-current-buffer cur-buf
                      (buffer-substring (point-min) (point-max)))))
          (with-temp-file fn-out-pattern
            (set-buffer-file-coding-system 'utf-8-unix)
            (insert pattern))
          (when replacement
            (with-temp-file fn-out-replacement
              (set-buffer-file-coding-system 'utf-8-unix)
              (insert replacement)))
          
          
          (when display-msg
            (message "[alien-search] Running..."))
          
          ;; Do search by external command.
          (let ((status (apply #'call-process
                               `(,cmd
                                 nil ,(buffer-name proc-output-buf) nil
                                 ,fn-out-body
                                 ,fn-in-result
                                 ,fn-out-pattern
                                 ,@(if replacement (list fn-out-replacement) nil)))))
            (when (not (and (numberp status)
                            (zerop status)))
              (error "[alien-search] %s exited with status \"%s\".\n%s"
                     cmd-basename
                     status
                     (with-current-buffer proc-output-buf
                       (buffer-substring (point-min) (point-max))))))
          
          (when display-msg
            (message "[alien-search] Running...done"))
          
          (with-current-buffer proc-output-buf
            (when (/= (point-min) (point-max))
              (message "[alien-search] messages from %s:\n%s"
                       cmd-basename
                       (buffer-substring (point-min) (point-max)))))
          
          ;; Parse result from external command.
          (let ((coding-system-for-read 'utf-8-unix))
            ;; Loaded data will be stored to the local variable `result'.
            (load (expand-file-name fn-in-result) nil t t))
          result)
      
      ;; Cleanup.
      (set-default-file-modes orig-file-modes)
      (and (file-exists-p fn-out-pattern    ) (delete-file fn-out-pattern    ))
      (and (file-exists-p fn-out-replacement) (delete-file fn-out-replacement))
      (and (file-exists-p fn-out-body       ) (delete-file fn-out-body       ))
      (and (file-exists-p fn-in-result      ) (delete-file fn-in-result      ))
      (kill-buffer proc-output-buf))))


;;; ===========================================================================
;;;
;;;  `query-replace' with a help from alien commands.
;;;
;;; ===========================================================================

(defcustom alien-search/replace/external-cmd "~/bin/query-replace-perl-aux.pl"
  "The command to use to execute actual search operation.

Four arguments describe below will be passed to the script.

 1st: Path of a file which contains the text to be searched.

 2nd: Path of a file to which the script should write the result
      of current search operation.

      The form of the result should have a form like:

        (setq result
              '((1st-MATCH-START 1st-MATCH-END \"REPLACEMENT-FOR-1st-MATCH\")
                (2nd-MATCH-START 2nd-MATCH-END \"REPLACEMENT-FOR-2nd-MATCH\")
                ...))

      Note that each start and end position in the form should be
      an offset from beginning of the text which has been searched.
      (This means each number should be started from 0, not from 1)

 3rd: Path of a file in which the pattern we want to search is written.
      The script have a responsibility to search this pattern
      from the file specified by 1st argument, then write start and
      end positions of each match to the file specified by 2nd argument.

 4th: Path of a file in which the replacement expression is written.
      The script have a responsibility to interpolate variables
      in the expression on each match, then write them to the file
      specified by 2nd argument."
  :type 'string
  :group 'alien-search)

(defvar alien-search/replace/defaults nil)


;; ----------------------------------------------------------------------------
;;
;;  Commands
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/query-replace pattern replacement
;;                              &optional delimited start end) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/query-replace (pattern replacement &optional delimited start end)
  "Do `query-replace' with a help from alien command.

See `isearch-forward-regexp' and `isearch-backward-regexp' for
more information."
  (interactive
   (let ((common
          (let ((query-replace-from-history-variable 'alien-search/history)
                (query-replace-to-history-variable   'alien-search/history)
                (query-replace-defaults              alien-search/replace/defaults))
            (prog1 (query-replace-read-args
                    (concat "Query replace perl"
                            (if (and transient-mark-mode mark-active) " in region" ""))
                    t)
              (setq alien-search/replace/defaults query-replace-defaults)))))
     (list (nth 0 common) (nth 1 common) (nth 2 common)
           ;; These are done separately here
           ;; so that command-history will record these expressions
           ;; rather than the values they had this time.
           (if (and transient-mark-mode mark-active)
               (region-beginning))
           (if (and transient-mark-mode mark-active)
               (region-end)))))
  (alien-search/replace/perform-replace
   pattern replacement t nil nil nil nil start end))


;; ----------------------------------------------------------------------------
;;
;;  Functions
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/search-by-external-cmd pattern replacement) => LIST
;; ----------------------------------------------------------------------------
(defun alien-search/replace/search-by-external-cmd (pattern replacement min max)
  "Scan current buffer with external command to detect matching
texts by PATTERN.

Overlays will be made on each matched text, and they will be
saved to the variable `alien-search/replace/ovs-on-match/data'.

Variables in REPLACEMENT will be interpolated
on each match, and will be saved to the property
alien-search/replace/replacement of each overlay.

Returns position of the neighborhood overlay of a pointer in
the list `alien-search/replace/ovs-on-match/data'."
  (let* ((cmd    alien-search/replace/external-cmd)
         (offset (point-min))
         (result (alien-search/search-by-external-cmd cmd
                                                      pattern
                                                      replacement)))
    (alien-search/replace/parse-search-result result offset min max)
    
    ;; Detect index of neighborhood overlay of a pointer.
    (position (car (member-if
                    #'(lambda (ov)
                        (<= (point) (overlay-start ov)))
                    alien-search/replace/ovs-on-match/data))
              alien-search/replace/ovs-on-match/data)))

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/parse-search-result result offset) => OVERLAYS
;; ----------------------------------------------------------------------------
(defun alien-search/replace/parse-search-result (result offset min max)
  "Subroutine of `alien-search/replace/search-by-external-cmd'."
  (alien-search/replace/ovs-on-match/dispose)
  ;; RESULT has structure like:
  ;;   ((MATCH_START MATCH_END "REPLACEMENT")
  ;;    ...)
  ;;
  ;; NOTE: Special variables in "REPLACEMENT"
  ;;       should be expanded by alien command.
  (save-excursion
    (let ((data    nil)
          (cur-buf (current-buffer)))
      (message "[alien-search] Parsing search results from perl...")
      (dolist (lst result)
        (let* ((beg         (+ (nth 0 lst) offset))
               (end         (+ (nth 1 lst) offset))
               (replacement (nth 2 lst)))
          (when (and (not (and min (< beg min)))
                     (not (and max (< max end))))
            (alien-search/replace/ovs-on-match/add beg end cur-buf replacement))))
      (message "[alien-search] Parsing search results from perl...done"))))

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/perform-replace (from-string replacement
;;                                     query-flag ignore ignore
;;                                     &optional ignore map start end) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/replace/perform-replace (from-string replacement
                                                         query-flag ignore ignore
                                                         &optional ignore map start end)
  "Replacement of `perform-replace' for alien search.

Note that \"\\?\" in string is not supported like
original `perform-replace' does.

Also list in REPLACEMENT and REPEAT-COUNT are not supported."
  ;; Based on `perform-replace'.

  ;; XXX: The overlays `ovs-on-match', that looks like lazy-highlight,
  ;;      should be updated by `alien-search/replace/search-by-external-cmd'
  ;;      whenever the function `replace-match' is called, but it is little
  ;;      bit annoying so we don't update them so much often here.
  (or map (setq map query-replace-map))
  (and query-flag minibuffer-auto-raise
       (raise-frame (window-frame (minibuffer-window))))
  (let* ((search-string from-string)
         (real-match-data nil)       ; The match data for the current match.
         (next-replacement nil)
         (keep-going t)
         (stack nil)
         (replace-count 0)
         (recenter-last-op nil)	; Start cycling order with initial position.
         
         (min nil)
         ;; If non-nil, it is marker saying where in the buffer to stop.
         (max nil)
         ;; Data for the next match.  If a cons, it has the same format as
         ;; (match-data); otherwise it is t if a match is possible at point.
         (match-again t)
         (message
          (if query-flag
              (apply 'propertize
                     (substitute-command-keys
                      "Query replacing %s with %s: (\\<query-replace-map>\\[help] for mini buffer help) ")
                     minibuffer-prompt-properties)))
         (idx nil)
         (regexp-flag t))

    (cond
     ((stringp replacement)
      (setq real-replacement replacement
            replacement     nil))
     (t
      (error "[alien-search] REPLACEMENT must be a string.")))

    ;; If region is active, in Transient Mark mode, operate on region.
    (when start
      (setq max (copy-marker (max start end)))
      (goto-char (setq min (min start end)))
      (deactivate-mark))

    ;; Do search by external command and detect index of
    ;; neighborhood overlay of a pointer.
    (setq idx (alien-search/replace/search-by-external-cmd from-string
                                                           real-replacement
                                                           min max))

    (push-mark)
    (undo-boundary)
    (unwind-protect
        (flet ((update-real-match-data (idx)
                                       (setq real-match-data
                                             (let ((ov (alien-search/replace/ovs-on-match/get-nth idx)))
                                               (when ov
                                                 (list (overlay-start ov)
                                                       (overlay-end   ov)))))
                                       (set-match-data real-match-data)
                                       real-match-data)
               (update-next-replacement (idx)
                                        (setq next-replacement
                                              (overlay-get (alien-search/replace/ovs-on-match/get-nth idx)
                                                           'alien-search/replace/replacement))))
          ;; Loop finding occurrences that perhaps should be replaced.
          (while (and idx
                      keep-going
                      (not (or (eobp) (and max (<= max (point)))))
                      (update-real-match-data idx)
                      (not (and max (< max (match-end 0)))))

            ;; Optionally ignore matches that have a read-only property.
            (unless (and query-replace-skip-read-only
                         (text-property-not-all
                          (nth 0 real-match-data) (nth 1 real-match-data)
                          'read-only nil))

              ;; Calculate the replacement string, if necessary.
              (set-match-data real-match-data)
              (update-next-replacement idx)
              
              (if (not query-flag)
                  (progn
                    (alien-search/replace/highlight/dispose)
                    (replace-match next-replacement t t)
                    (setq replace-count (1+ replace-count)))
                (undo-boundary)
                (let (done replaced key def)
                  ;; Loop reading commands until one of them sets done,
                  ;; which means it has finished handling this
                  ;; occurrence.  Any command that sets `done' should
                  ;; leave behind proper match data for the stack.
                  ;; Commands not setting `done' need to adjust
                  ;; `real-match-data'.
                  (while (not done)
                    (set-match-data real-match-data)
                    (alien-search/replace/highlight/put
                     (match-beginning 0) (match-end 0))
                    (goto-char (match-end 0))
                    ;; Bind message-log-max so we don't fill up the message log
                    ;; with a bunch of identical messages.
                    (let ((message-log-max nil)
                          (replacement-presentation next-replacement))
                      (message message
                               (query-replace-descr from-string)
                               (query-replace-descr replacement-presentation)))
                    (setq key (read-event))
                    ;; Necessary in case something happens during read-event
                    ;; that clobbers the match data.
                    (set-match-data real-match-data)
                    (setq key (vector key))
                    (setq def (lookup-key map key))
                    ;; Restore the match data while we process the command.
                    (cond ((eq def 'help)
                           (with-output-to-temp-buffer "*Help*"
                             (princ
                              (concat "Query replacing "
                                      (if regexp-flag "regexp " "")
                                      from-string " with "
                                      next-replacement ".\n\n"
                                      (substitute-command-keys
                                       query-replace-help)))
                             (with-current-buffer standard-output
                               (help-mode))))
                          ((eq def 'exit)
                           (setq keep-going nil)
                           (setq done t))
                          ((eq def 'exit-current)
                           (setq multi-buffer t keep-going nil done t))
                          ((eq def 'backup)
                           ;; XXX: The behavior is different from original
                           ;;      `perform-replace' because we don't update
                           ;;      `ovs-on-match' after `replace-match' operation
                           ;;      because of performance issue.
                           (if stack
                               (let ((elt (pop stack)))
                                 (goto-char (nth 0 elt))
                                 (setq idx (1- idx))
                                 (update-next-replacement idx)
                                 (update-real-match-data idx)
                                 (setq replaced (nth 1 elt)
                                       real-match-data
                                       (replace-match-data
                                        t real-match-data
                                        (nth 2 elt))))
                             (message "No previous match")
                             (ding 'no-terminate)
                             (sit-for 1)))
                          ((eq def 'act)
                           (or replaced
                               (replace-match next-replacement t t)
                               (setq replace-count (1+ replace-count)))
                           (setq done t replaced t))
                          ((eq def 'act-and-exit)
                           (or replaced
                               (replace-match next-replacement t t)
                               (setq replace-count (1+ replace-count)))
                           (setq keep-going nil)
                           (setq done t replaced t))
                          ((eq def 'act-and-show)
                           (when (not replaced)
                             (replace-match next-replacement t t)
                             (setq replace-count (1+ replace-count)
                                   real-match-data (replace-match-data
                                                    t real-match-data)
                                   replaced t)))
                          ((or (eq def 'automatic) (eq def 'automatic-all))
                           (when (not replaced)
                             (replace-match next-replacement t t)
                             (setq replace-count (1+ replace-count)))
                           (setq done t query-flag nil replaced t))
                          ((eq def 'skip)
                           (setq done t))
                          ((eq def 'recenter)
                           ;; `this-command' has the value `query-replace',
                           ;; so we need to bind it to `recenter-top-bottom'
                           ;; to allow it to detect a sequence of `C-l'.
                           (let ((this-command 'recenter-top-bottom)
                                 (last-command 'recenter-top-bottom))
                             (recenter-top-bottom)))

                          ;; Recursive-edit.
                          ((eq def 'edit)
                           (let ((opos (save-excursion
                                         (progn
                                           (goto-char (match-beginning 0))
                                           (point-marker)))))
                             (setq real-match-data (replace-match-data
                                                    nil real-match-data
                                                    real-match-data))
                             (goto-char (match-beginning 0))
                             (save-excursion
                               (save-window-excursion
                                 (recursive-edit)))
                             (goto-char opos)
                             (set-marker opos nil))
                           (setq idx (alien-search/replace/search-by-external-cmd
                                      from-string
                                      next-replacement
                                      min max))
                           (update-next-replacement idx)
                           (update-real-match-data idx))
                          
                          ;; Edit replacement.
                          ((eq def 'edit-replacement)
                           (let ((opos (save-excursion
                                         (progn
                                           (goto-char (if replaced
                                                          (match-end 0) ;;After backup?
                                                        (match-beginning 0)))
                                           (point-marker)))))
                             (setq real-match-data (replace-match-data
                                                    nil real-match-data
                                                    real-match-data))
                             (setq real-replacement
                                   (read-string "Edit replacement string: "
                                                real-replacement))
                             (goto-char opos)
                             (set-marker opos nil))
                           (setq idx (alien-search/replace/search-by-external-cmd
                                      from-string
                                      real-replacement
                                      min max))
                           (update-next-replacement idx)
                           (update-real-match-data idx)
                           
                           (if replaced
                               (setq idx (and idx (1- idx)))
                             (replace-match next-replacement t t)
                             (setq replace-count (1+ replace-count)))
                           (setq done t replaced t))

                          ;; Delete matched string then recursive-edit.
                          ((eq def 'delete-and-edit)
                           (let ((opos (save-excursion
                                         (progn
                                           (goto-char (match-end 0))
                                           (point-marker)))))
                             (set-marker-insertion-type opos t)
                             
                             (replace-match "" t t)
                             (setq real-match-data (replace-match-data
                                                    nil real-match-data))
                             (alien-search/replace/ovs-on-match/dispose)
                             (alien-search/replace/highlight/dispose)
                             
                             (save-excursion (recursive-edit))

                             (goto-char opos)
                             (set-marker opos nil))
                           (setq idx (alien-search/replace/search-by-external-cmd
                                      from-string
                                      real-replacement
                                      min max))
                           (if (numberp idx)
                               (setq idx (1- idx)) ;;Do not forward current match.
                             (setq idx (alien-search/replace/ovs-on-match/get-count))) ;;Done.
                           
                           (setq replaced t))

                          ;; Note: we do not need to treat `exit-prefix'
                          ;; specially here, since we reread
                          ;; any unrecognized character.
                          (t
                           (setq this-command 'mode-exited)
                           (setq keep-going nil)
                           (setq unread-command-events
                                 (append (listify-key-sequence key)
                                         unread-command-events))
                           (setq done t)))

                    (unless (eq def 'recenter)
                      ;; Reset recenter cycling order to initial position.
                      (setq recenter-last-op nil)))
                  ;; Record previous position for ^ when we move on.
                  ;; Change markers to numbers in the match data
                  ;; since lots of markers slow down editing.
                  (push (list (point) replaced
                              ;;  If the replacement has already happened, all we need is the
                              ;;  current match start and end.  We could get this with a trivial
                              ;;  match like
                              ;;  (save-excursion (goto-char (match-beginning 0))
                              ;;		     (search-forward (match-string 0))
                              ;;                  (match-data t))
                              ;;  if we really wanted to avoid manually constructing match data.
                              ;;  Adding current-buffer is necessary so that match-data calls can
                              ;;  return markers which are appropriate for editing.
                              (if replaced
                                  (list
                                   (match-beginning 0)
                                   (match-end 0)
                                   (current-buffer))
                                (match-data t)))
                        stack))))
            (setq idx (1+ idx))))
      (alien-search/replace/ovs-on-match/dispose)
      (alien-search/replace/highlight/dispose))
    (or unread-command-events
        (message "Replaced %d occurrence%s"
                 replace-count
                 (if (= replace-count 1) "" "s")))))


;;; ===========================================================================
;;;
;;;  Overlay on current match.
;;;
;;; ===========================================================================

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/highlight/put beg end) => VOID
;; ----------------------------------------------------------------------------
(defvar alien-search/replace/highlight-overlay nil)
(make-variable-buffer-local 'alien-search/replace/highlight-overlay)
(defun alien-search/replace/highlight/put (beg end)
  "Subroutine of `alien-search/replace/perform-replace'.

Put overlay on current match."
  (if alien-search/replace/highlight-overlay
      (move-overlay alien-search/replace/highlight-overlay beg end)
    (let ((ov (make-overlay beg end (current-buffer) t)))
      (overlay-put ov 'priority 1001) ;higher than lazy overlays
      (when query-replace-highlight
        (overlay-put ov 'face 'query-replace))
      (setq alien-search/replace/highlight-overlay ov))))

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/highlight/dispose) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/replace/highlight/dispose ()
  "Subroutine of `alien-search/replace/perform-replace'."
  (when alien-search/replace/highlight-overlay
    (delete-overlay alien-search/replace/highlight-overlay)
    (setq alien-search/replace/highlight-overlay nil)))


;;; ===========================================================================
;;;
;;;  Overlays on all of matches by external command.
;;;
;;; ===========================================================================

(defvar alien-search/replace/ovs-on-match/data nil)
(make-variable-buffer-local 'alien-search/replace/ovs-on-match/data)


;; ----------------------------------------------------------------------------
;;  (alien-search/replace/ovs-on-match/add beg end buf replacement) => LIST
;; ----------------------------------------------------------------------------
(defun alien-search/replace/ovs-on-match/add (beg end buf replacement)
  "Make overlay on match text and save it in
`alien-search/replace/ovs-on-match/data'.

Each overlay has a replacement text as property
alien-search/replace/replacement."
  (let ((ov (make-overlay beg end buf nil nil)))
    (when query-replace-lazy-highlight
      (overlay-put ov 'face lazy-highlight-face))
    (overlay-put ov 'alien-search/replace/replacement replacement)
    (overlay-put ov 'priority 1000)
    (setq alien-search/replace/ovs-on-match/data
          (nconc alien-search/replace/ovs-on-match/data (cons ov nil)))))

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/ovs-on-match/dispose) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/replace/ovs-on-match/dispose ()
  "Delete overlays on matched strings created by command
`alien-search/replace'."
  (dolist (ov alien-search/replace/ovs-on-match/data)
    (overlay-put ov 'alien-search/replace/replacement nil)
    (overlay-put ov 'priority nil)
    (delete-overlay ov))
  (setq alien-search/replace/ovs-on-match/data nil))

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/ovs-on-match/get-nth nth) => OVERLAY
;; ----------------------------------------------------------------------------
(defun alien-search/replace/ovs-on-match/get-nth (nth)
  (nth nth alien-search/replace/ovs-on-match/data))

;; ----------------------------------------------------------------------------
;;  (alien-search/replace/ovs-on-match/get-count) => NUM
;; ----------------------------------------------------------------------------
(defun alien-search/replace/ovs-on-match/get-count ()
  (length alien-search/replace/ovs-on-match/data))


;;; ===========================================================================
;;;
;;;  `occur' with a help from alien commands.
;;;
;;; ===========================================================================

(defcustom alien-search/occur/external-cmd "~/bin/occur-perl-aux.pl"
  "The command to use to execute actual search operation.

Three arguments describe below will be passed to the script.

 1st: Path of a file which contains the text to be searched.

 2nd: Path of a file to which the script should write the result
      of current search operation.

      The form of the result should have a form like:

        (setq result
              '(
                ;; Match positions in 1st line
                ((1st-MATCH-START 1st-MATCH-END)
                 (2nd-MATCH-START 2nd-MATCH-END)
                 ...)
                ;; When a line has no match, do not put anything.
                ...
                ;; Match positions in n-th line
                ((x-th-MATCH-START x-th-MATCH-END)
                 (y-th-MATCH-START y-th-MATCH-END)
                 ...)))

      Note that each start and end position in the form should be
      an offset from beginning of the text which has been searched.
      (This means each number should be started from 0, not from 1)

 3rd: Path of a file in which the pattern we want to search is written.
      The script have a responsibility to search this pattern
      from the file specified by 1st argument, then write start and
      end positions of each match to the file specified by 2nd argument."
  :type  'string
  :group 'alien-search)

;; ----------------------------------------------------------------------------
;;
;;  Commands
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/occur regexp &optional nlines) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/occur (regexp &optional nlines)
  (interactive (let ((regexp-history alien-search/history))
                 (prog1
                     (occur-read-primary-args)
                   (setq alien-search/history regexp-history))))
  (let ((orig-occur-engine-fn (symbol-function 'occur-engine)))
    (setf (symbol-function 'occur-engine)
          (symbol-function 'alien-search/occur/occur-engine))
    (unwind-protect
        (occur regexp nlines)
      (setf (symbol-function 'occur-engine)
            orig-occur-engine-fn))))


;; ----------------------------------------------------------------------------
;;
;;  Functions
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/occur/occur-engine regexp buffers out-buf nlines
;;                                   case-fold-search title-face
;;                                   prefix-face match-face keep-props) => NUM
;; ----------------------------------------------------------------------------
(defun alien-search/occur/occur-engine (regexp buffers out-buf nlines
                                               case-fold-search title-face
                                               prefix-face match-face keep-props)
  "Alternate function of original `occur-engine'."
  ;; Based on `occur-engine'.
  (with-current-buffer out-buf
    (let ((globalcount 0)
          (coding nil))
      ;; Map over all the buffers
      (dolist (buf buffers)
        (when (buffer-live-p buf)
          (let ((cmd alien-search/occur/external-cmd)
                (matches 0)	;; count of matched lines
                (curstring "")
                (inhibit-field-text-motion t)
                (headerpt (with-current-buffer out-buf (point)))
                (*search-result-alst* nil)
                (matches-in-line nil))
            (with-current-buffer buf
              (setq result (alien-search/search-by-external-cmd cmd regexp))
              (or coding
                  ;; Set CODING only if the current buffer locally
                  ;; binds buffer-file-coding-system.
                  (not (local-variable-p 'buffer-file-coding-system))
                  (setq coding buffer-file-coding-system))
              (save-excursion
                (goto-char (point-min)) ;; begin searching in the buffer
                (while (setq matches-in-line (prog1 (car result)
                                               (setq result (cdr result))))
                  (let* ((matchbeg (1+ (caar matches-in-line))) ;;1+ = [Offset => Count]
                         (lines    (progn (goto-char matchbeg)
                                          (line-number-at-pos)))
                         (marker   (point-marker))
                         (begpt    (progn (beginning-of-line)
                                          (point)))
                         (endpt    (progn (end-of-line)
                                          (point)))
                         match-pair)
                    (setq matches (1+ matches)) ;; increment match count
                    
                    (if (and keep-props
                             (if (boundp 'jit-lock-mode) jit-lock-mode)
                             (text-property-not-all begpt endpt 'fontified t))
                        (if (fboundp 'jit-lock-fontify-now)
                            (jit-lock-fontify-now begpt endpt)))
                    (if (and keep-props (not (eq occur-excluded-properties t)))
                        (progn
                          (setq curstring (buffer-substring begpt endpt))
                          (remove-list-of-text-properties
                           0 (length curstring) occur-excluded-properties curstring))
                      (setq curstring (buffer-substring-no-properties begpt endpt)))
                    ;; Highlight the matches
                    (while (setq match-pair (prog1 (car matches-in-line)
                                              (setq matches-in-line
                                                    (cdr matches-in-line))))
                      (add-text-properties
                       (- (1+ (nth 0 match-pair)) begpt) ;;1+ = [Offset => Count]
                       (- (1+ (nth 1 match-pair)) begpt) ;;1+ = [Offset => Count]
                       (append
                        `(occur-match t)
                        (when match-face
                          ;; Use `face' rather than `font-lock-face' here
                          ;; so as to override faces copied from the buffer.
                          `(face ,match-face)))
                       curstring))
                    ;; Generate the string to insert for this match
                    (let* ((out-line
                            (concat
                             ;; Using 7 digits aligns tabs properly.
                             (apply #'propertize (format "%7d:" lines)
                                    (append
                                     (when prefix-face
                                       `(font-lock-face prefix-face))
                                     `(occur-prefix t mouse-face (highlight)
                                                    occur-target ,marker follow-link t
                                                    help-echo "mouse-2: go to this occurrence")))
                             ;; We don't put `mouse-face' on the newline,
                             ;; because that loses.  And don't put it
                             ;; on context lines to reduce flicker.
                             (propertize curstring 'mouse-face (list 'highlight)
                                         'occur-target marker
                                         'follow-link t
                                         'help-echo
                                         "mouse-2: go to this occurrence")
                             ;; Add marker at eol, but no mouse props.
                             (propertize "\n" 'occur-target marker)))
                           (data
                            (if (= nlines 0)
                                ;; The simple display style
                                out-line
                              ;; The complex multi-line display style.
                              (occur-context-lines out-line nlines keep-props)
                              )))
                      ;; Actually insert the match display data
                      (with-current-buffer out-buf
                        (let ((beg (point))
                              (end (progn (insert data) (point))))
                          (unless (= nlines 0)
                            (insert "-------\n")))))))))
            (when (not (zerop matches)) ;; is the count zero?
              (setq globalcount (+ globalcount matches))
              (with-current-buffer out-buf
                (goto-char headerpt)
                (let ((beg (point))
                      end)
                  (insert (format "%d match%s for \"%s\" in buffer: %s\n"
                                  matches (if (= matches 1) "" "es")
                                  regexp (buffer-name buf)))
                  (setq end (point))
                  (add-text-properties beg end
                                       (append
                                        (when title-face
                                          `(font-lock-face ,title-face))
                                        `(occur-title ,buf))))
                (goto-char (point-min)))))))
      (if coding
          ;; CODING is buffer-file-coding-system of the first buffer
          ;; that locally binds it.  Let's use it also for the output
          ;; buffer.
          (set-buffer-file-coding-system coding))
      ;; Return the number of matches
      globalcount)))


  
;;; ===========================================================================
;;;
;;;  `isearch' with a help from alien commands.
;;;
;;; ===========================================================================

(defcustom alien-search/isearch/external-cmd "~/bin/isearch-perl-aux.pl"
  "The command to use to execute actual search operation.

Three arguments describe below will be passed to the script.

 1st: Path of a file which contains the text to be searched.

 2nd: Path of a file to which the script should write the result
      of current search operation.

      The form of the result should have a form like:

        (setq result
              '((1st-MATCH-START 1st-MATCH-END)
                (2nd-MATCH-START 2nd-MATCH-END)
                 ...))

      Note that each start and end position in the form should be
      an offset from beginning of the text which has been searched.
      (This means each number should be started from 0, not from 1)

 3rd: Path of a file in which the pattern we want to search is written.
      The script have a responsibility to search this pattern
      from the file specified by 1st argument, then write start and
      end positions of each match to the file specified by 2nd argument."
  :type  'string
  :group 'alien-search)

(defvar alien-search/isearch/.cached-data nil
  "Private variable.")
(defvar alien-search/isearch/.last-regexp nil
  "Private variable.")


;; ----------------------------------------------------------------------------
;;
;;  Commands
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/isearch &optional not-regexp no-recursive-edit) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/isearch (&optional not-regexp no-recursive-edit)
  "Do isearch with a help from alien command.

See `isearch-forward-regexp' and `isearch-backward-regexp' for
more information."
  (interactive "P\np")
  (setq alien-search/isearch/.cached-data nil)
  (setq alien-search/isearch/.last-regexp nil)
  
  ;; Setup `isearch-search-fun-function'.
  (when (not (boundp 'alien-search/isearch/orig-isearch-search-fun-function))
    (setq alien-search/isearch/orig-isearch-search-fun-function
          isearch-search-fun-function))
  (setq isearch-search-fun-function #'alien-search/isearch/isearch-search-fun-function)
  (add-hook 'isearch-mode-end-hook
            'alien-search/isearch/.isearch-mode-end-hook-fn)
  
  (isearch-mode t (null not-regexp) nil (not no-recursive-edit)))


;; ----------------------------------------------------------------------------
;;
;;  Functions
;;
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;;  (alien-search/isearch/.isearch-mode-end-hook-fn ) => VOID
;; ----------------------------------------------------------------------------
(defun alien-search/isearch/.isearch-mode-end-hook-fn ()
  "Clean up environment when isearch by alien-search is finished."
  (when (not isearch-nonincremental)
    ;;(message "remove-hook!%s" (backtrace))
    (when (boundp 'alien-search/isearch/orig-isearch-search-fun-function)
      (setq isearch-search-fun-function
            alien-search/isearch/orig-isearch-search-fun-function)
      (makunbound 'alien-search/isearch/orig-isearch-search-fun-function))
    (remove-hook 'isearch-mode-end-hook
                 'alien-search/isearch/.isearch-mode-end-hook-fn)))

;; ----------------------------------------------------------------------------
;;  (alien-search/isearch/isearch-search-fun-function) => FUNCTION
;; ----------------------------------------------------------------------------
(defun alien-search/isearch/isearch-search-fun-function ()
  "The value used as value of `isearch-search-fun' while
isearch by alien-search is on.

This function returns the search function
`alien-search/isearch/search-fun' for isearch to use."
  #'alien-search/isearch/search-fun)

;; ----------------------------------------------------------------------------
;;  (alien-search/isearch/search-fun regexp &optional bound noerror count)
;;                                                                    => POINT
;; ----------------------------------------------------------------------------
(defun alien-search/isearch/search-fun (regexp &optional bound noerror count)
  "Search for the first occurrence of REGEXP in alien manner.
If found, move point to the end of the occurrence,
update the match data, and return point.

This function will be used as alternate function of `re-search-forward'
and `re-search-backward' while isearch by alien-search is on."
  (when (or (not (equal alien-search/isearch/.last-regexp
                        regexp))
            (not alien-search/isearch/.cached-data))
    (setq alien-search/isearch/.cached-data
          (alien-search/search-by-external-cmd alien-search/isearch/external-cmd
                                               regexp))
    (setq alien-search/isearch/.last-regexp
          regexp))
  (let ((forward-p isearch-forward)
        (pt (point)))
    (if forward-p
        ;; Search forward
        (let* ((data alien-search/isearch/.cached-data)
               (be-lst (car (member-if
                             #'(lambda (be-lst)
                                 (<= pt (1+ (nth 0 be-lst)))) ;;1+ = [Offset => Count]
                             data)))
               (beg (and be-lst (1+ (nth 0 be-lst)))) ;;1+ = [Offset => Count]
               (end (and be-lst (1+ (nth 1 be-lst))))) ;;1+ = [Offset => Count]
          (when (and be-lst
                     (if bound
                         (<= end bound)
                       t))
            (set-match-data (list beg end))
            (goto-char end)
            end))
      ;; Search backward
      (let* ((data (reverse alien-search/isearch/.cached-data))
             (be-lst (car (member-if
                           #'(lambda (be-lst)
                               (<= (1+ (nth 1 be-lst)) pt)) ;;1+ = [Offset => Count]
                           data)))
             (beg (and be-lst (1+ (nth 0 be-lst)))) ;;1+ = [Offset => Count]
             (end (and be-lst (1+ (nth 1 be-lst)))))
        (when (and be-lst
                   (if bound
                       (<= bound beg)
                     t))
          (set-match-data (list beg end))
          (goto-char beg)
          beg)))))

;;; alien-search.el ends here
