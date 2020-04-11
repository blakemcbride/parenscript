#!/usr/bin/env -S sbcl --script

;;; roughly in order of how long the tests take to run
(defvar implementations '("sbcl-bin" "clisp" "ccl-bin" "allegro" "abcl-bin"
                          "ecl"))

(let ((installed (with-output-to-string (out)
                   (sb-ext:run-program "ros" '("list" "installed")
                                       :search t :output out))))
  (dolist (implementation implementations)
    (unless (search implementation installed)
      (write-string "Installing ") (write-line implementation)
      (sb-ext:run-program "ros" (list "install" implementation)
                          :search t :output t)
      (terpri))))

(write-line "Starting tests")

(defvar test-code
  "(setq *debugger-hook*
         (lambda (condition x)
           (declare (ignore x))
           (let ((*standard-output* uiop:*stderr*))
             (fresh-line)
             (write-string \"Debugger entered with error \")
             (princ (type-of condition))
             (write-string \": \")
             (princ condition)
             (terpri)
             (uiop:quit 1))))
   (ql:quickload \"parenscript.tests\")
   (let* ((fiveam:*print-names*               nil)
          (fiveam:*test-dribble*              uiop:*stderr*)
          (test-results (fiveam:run
                          'parenscript.tests:parenscript-tests)))
     (unless (fiveam:results-status test-results)
       (fiveam:explain! test-results)
       (uiop:quit 1)))")

;;; make sure ASDF is loading the system from the current directory
(require :sb-posix)
(sb-posix:setenv "CL_SOURCE_REGISTRY"
                 (directory-namestring *load-truename*)
                 1)

(dolist (implementation implementations)
  (write-string "Running tests in ") (write-string implementation)
  (finish-output)

  (let* ((stderr (make-string-output-stream))
         (exit-code
          (sb-ext:process-exit-code
           (sb-ext:run-program
            "ros"
            (list "run" "-L" implementation "-e" test-code "-q")
            :search t :error stderr))))
    (if (/= 0 exit-code)
        (progn (write-line ": FAILURE")
               (write-string "Error running tests in " *error-output*)
               (write-line implementation *error-output*)
               (write-string (get-output-stream-string stderr)
                             *error-output*)
               (sb-ext:exit :code 1))
        (write-line ": SUCCESS"))))
