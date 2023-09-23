;;;; -*- encoding:utf-8 -*-

;;; Copyright 2005 Manuel Odendahl
;;; Copyright 2005-2006 Edward Marco Baringer
;;; Copyright 2007-2012 Vladimir Sedach
;;; Copyright 2008 Travis Cross
;;; Copyright 2009-2013 Daniel Gackle
;;; Copyright 2010 Scott Bell
;;; Copyright 2014 Boris Smilga

;;; SPDX-License-Identifier: BSD-3-Clause

;;; Redistribution and use in source and binary forms, with or
;;; without modification, are permitted provided that the following
;;; conditions are met:

;;; 1. Redistributions of source code must retain the above copyright
;;; notice, this list of conditions and the following disclaimer.

;;; 2. Redistributions in binary form must reproduce the above
;;; copyright notice, this list of conditions and the following
;;; disclaimer in the documentation and/or other materials provided
;;; with the distribution.

;;; 3. Neither the name of the copyright holder nor the names of its
;;; contributors may be used to endorse or promote products derived
;;; from this software without specific prior written permission.

;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
;;; CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
;;; INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
;;; MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
;;; DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
;;; BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
;;; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;; TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
;;; ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
;;; OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
;;; OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package #:parenscript)
(named-readtables:in-readtable :parenscript)

(defvar *ps-print-pretty* t)
(defvar *indent-num-spaces* 4)
(defvar *js-string-delimiter* #\'
  "Specifies which character should be used for delimiting strings.

This variable is used when you want to embed the resulting JavaScript
in an html attribute delimited by #\\\" as opposed to #\\', or
vice-versa.")

(defvar *indent-level*)
(defvar *column*)

(defvar *psw-stream*)

(defun parenscript-print (form immediate?)
  (declare (special immediate?))
  (let ((*indent-level* 0)
        (*column* 0)
        (*psw-stream* (if immediate?
                          *psw-stream*
                          (make-string-output-stream)))
        (%psw-accumulator ()))
    (declare (special %psw-accumulator))
    (with-standard-io-syntax
      (if (and (listp form) (eq 'ps-js:block (car form))) ; ignore top-level block
          (loop for (statement . remaining) on (cdr form) do
                (ps-print statement) (psw #\;) (when remaining (psw #\Newline)))
          (ps-print form)))
    (unless immediate?
      (reverse (cons (get-output-stream-string *psw-stream*)
                     %psw-accumulator)))))

(defun psw (&rest objs)
  (dolist (obj objs)
    (declare (special %psw-accumulator immediate?))
    (typecase obj
      (string
       (incf *column* (length obj))
       (write-string obj *psw-stream*))
      (character
       (if (eql obj #\Newline)
           (setf *column* 0)
           (incf *column*))
       (write-char obj *psw-stream*))
      (otherwise
       (if immediate?
           (let ((str (eval obj)))
             (incf *column* (length str))
             (write-string str *psw-stream*))
           (setf %psw-accumulator
                 (list* obj
                        (get-output-stream-string *psw-stream*)
                        %psw-accumulator)))))))

(defgeneric ps-print (form))
(defgeneric ps-print% (js-primitive args))

(defmacro defprinter (js-primitive args &body body)
  (if (listp js-primitive)
      (cons 'progn (mapcar (lambda (p)
                             `(defprinter ,p ,args ,@body))
                           js-primitive))
      (let ((pargs (gensym)))
        `(defmethod ps-print% ((op (eql ',js-primitive)) ,pargs)
           (declare (ignorable op))
           (destructuring-bind ,args
               ,pargs
             ,@(loop for x in body collect
                    (if (or (characterp x)
                            (stringp x))
                        (list 'psw x)
                        x)))))))

(defmethod ps-print ((x null))
  (psw "null"))

(defmethod ps-print ((x (eql t)))
  (psw "true"))

(defmethod ps-print ((x (eql 'ps-js:false)))
  (psw "false"))

(defmethod ps-print ((s symbol))
  (if (keywordp s)
      (ps-print (string-downcase s))
      (psw (symbol-to-js-string s))))

(defmethod ps-print ((compiled-form cons))
  (ps-print% (car compiled-form) (cdr compiled-form)))

(defun newline-and-indent (&optional indent-spaces)
  (if *ps-print-pretty*
      (progn (psw #\Newline)
             (loop repeat (if indent-spaces
                              indent-spaces
                              (* *indent-level* *indent-num-spaces*))
                   do (psw #\Space)))
      (psw #\Space)))

(defun print-comment (comment-str)
  (when *ps-print-pretty*
    (let ((lines (cl-ppcre:split #\Newline comment-str)))
      (if (cdr lines)
          (progn (psw "/**") (newline-and-indent)
                 (dolist (x lines) (psw " * " x) (newline-and-indent))
                 (psw " */"))
          (psw "/** " comment-str " */"))
      (newline-and-indent))))

(defparameter *js-lisp-escaped-chars*
  (list #\'            #\'
        #\"            #\"
        #\\            #\\
        #\Backspace    #\b
        (code-char 12) #\f
        #\Newline      #\n
        #\Return       #\r
        #\Tab          #\t))

(defmethod ps-print ((char character))
  (ps-print (string char)))

(defmethod ps-print ((string string))
  (psw *js-string-delimiter*)
  (loop for char across string do
       (acond ((getf *js-lisp-escaped-chars* char)
               (psw #\\ it))
              ((or (<= (char-code char) #x1F)
                   (<= #x80 (char-code char) #x9F)
                   (member (char-code char) '(#xA0 #xAD #x200B #x200C)))
               (format *psw-stream* "\\u~:@(~4,'0x~)" (char-code char)))
              (t
               (psw char))))
  (psw *js-string-delimiter*))

(defmethod ps-print ((number number))
  (format *psw-stream* (if (integerp number) "~D" "~F") number))

(let ((precedence-table (make-hash-table :test 'eq)))
  (loop for level in '((ps-js:getprop ps-js:aref ps-js:funcall)
                       (ps-js:new)
                       (ps-js:lambda) ;; you won't find this in JS books
                       (ps-js:++ ps-js:-- ps-js:post++ ps-js:post--)
                       (ps-js:! ps-js:~ ps-js:negate ps-js:unary-plus ps-js:typeof ps-js:delete)
                       (ps-js:* ps-js:/ ps-js:%)
                       (ps-js:- ps-js:+)
                       (ps-js:<< ps-js:>> ps-js:>>>)
                       (ps-js:< ps-js:> ps-js:<= ps-js:>= ps-js:instanceof ps-js:in)
                       (ps-js:== ps-js:!= ps-js:=== ps-js:!==)
                       (ps-js:&)
                       (ps-js:^)
                       (ps-js:\|)
                       (ps-js:&&)
                       (ps-js:\|\|)
                       (ps-js:?)
                       (ps-js:= ps-js:*= ps-js:/= ps-js:%= ps-js:+= ps-js:-= ps-js:<<= ps-js:>>= ps-js:>>>= ps-js:&= ps-js:^= ps-js:\|=)
                       (ps-js:return ps-js:throw)
                       (ps-js:|,|))
     for i from 0
     do (mapc (lambda (symbol)
                (setf (gethash symbol precedence-table) i))
              level))
  (defun precedence (op)
    (gethash op precedence-table -1)))

(defun associative? (op)
  (member op '(ps-js:* ps-js:& ps-js:&& ps-js:\| ps-js:\|\|
               ps-js:funcall ps-js:aref ps-js:getprop))) ;; these aren't really associative, but RPN

(defun parenthesize-print (x)
  (psw #\() (ps-print x) (psw #\)))

(defun print-op-argument (op argument)
  (let ((arg-op (when (listp argument) (car argument))))
    (if (or (< (precedence op) (precedence arg-op))
            (and (= (precedence op) (precedence arg-op))
                 (or (not (associative? op)) (not (associative? arg-op)))))
        (parenthesize-print argument)
        (ps-print argument))))

(defun print-op (op)
  (psw (string-downcase op)))

(defprinter (ps-js:! ps-js:~ ps-js:++ ps-js:--) (x)
  (print-op op) (print-op-argument op x))

(defprinter ps-js:negate (x)
  "-"(print-op-argument op x))

(defprinter ps-js:unary-plus (x)
  "+"(print-op-argument op x))

(defprinter (ps-js:delete ps-js:typeof ps-js:new ps-js:throw) (x)
  (print-op op)" "(print-op-argument op x))

(defprinter (ps-js:return) (&optional (x nil x?))
  (print-op op)
  (when x?
    (psw " ") (print-op-argument op x)))

(defprinter ps-js:post++ (x)
  (ps-print x)"++")

(defprinter ps-js:post-- (x)
  (ps-print x)"--")

(defprinter (ps-js:+ ps-js:- ps-js:* ps-js:/ ps-js:% ps-js:&& ps-js:\|\| ps-js:& ps-js:\| ps-js:-= ps-js:+= ps-js:*= ps-js:/= ps-js:%= ps-js:^ ps-js:<< ps-js:>> ps-js:&= ps-js:^= ps-js:\|= ps-js:= ps-js:in ps-js:> ps-js:>= ps-js:< ps-js:<= ps-js:== ps-js:!= ps-js:=== ps-js:!==)
    (&rest args)
  (loop for (arg . remaining) on args do
       (print-op-argument op arg)
       (when remaining (format *psw-stream* " ~(~A~) " op))))

(defprinter ps-js:aref (array &rest indices)
  (print-op-argument 'ps-js:aref array)
  (dolist (idx indices)
    (psw #\[) (ps-print idx) (psw #\])))

(defun print-comma-delimited-list (ps-forms)
  (loop for (form . remaining) on ps-forms do
        (print-op-argument 'ps-js:|,| form)
        (when remaining (psw ", "))))

(defprinter ps-js:array (&rest initial-contents)
  "["(print-comma-delimited-list initial-contents)"]")

(defprinter (ps-js:|,|) (&rest expressions)
  (print-comma-delimited-list expressions))

(defprinter ps-js:funcall (fun-designator &rest args)
  (print-op-argument op fun-designator)"("(print-comma-delimited-list args)")")

(defprinter ps-js:block (&rest statements)
  "{" (incf *indent-level*)
  (dolist (statement statements)
    (newline-and-indent) (ps-print statement) (psw #\;))
  (decf *indent-level*) (newline-and-indent)
  "}")

(defprinter ps-js:lambda (args body-block)
  (print-fun-def nil args body-block))

(defprinter ps-js:defun (name args docstring body-block)
  (when docstring (print-comment docstring))
  (print-fun-def name args body-block))

(defun print-fun-def (name args body)
  (destructuring-bind (keyword name) (if (consp name) name `(function ,name))
    (format *psw-stream* "~(~A~) ~:[~;~A~]("
            keyword name (symbol-to-js-string name))
    (loop for (arg . remaining) on args do
        (psw (symbol-to-js-string arg)) (when remaining (psw ", ")))
    (psw ") ")
    (ps-print body)))

(defprinter ps-js:object (&rest slot-defs)
  (psw "{ ")
  (let ((indent? (< 2 (length slot-defs)))
        (indent *column*))
    (loop for ((slot-name . slot-value) . remaining) on slot-defs do
         (if (consp slot-name)
             (apply #'print-fun-def slot-name slot-value)
             (progn
               (ps-print slot-name) (psw " : ")
               (if (and (consp slot-value)
                        (eq 'ps-js:|,| (car slot-value)))
                   (parenthesize-print slot-value)
                   (ps-print slot-value))))
         (when remaining
           (psw ",")
           (if indent?
               (newline-and-indent indent)
               (psw #\Space))))
    (if indent?
        (newline-and-indent (- indent 2))
        (psw #\Space)))
  (psw "}"))

(defprinter ps-js:getprop (obj slot)
  (print-op-argument op obj)"."(psw (symbol-to-js-string slot)))

(defprinter ps-js:if (test consequent &rest clauses)
  "if (" (ps-print test) ") "
  (ps-print consequent)
  (loop while clauses do
       (ecase (car clauses)
         (:else-if (psw " else if (") (ps-print (cadr clauses)) (psw ") ")
                   (ps-print (caddr clauses))
                   (setf clauses (cdddr clauses)))
         (:else (psw " else ")
                (ps-print (cadr clauses))
                (return)))))

(defprinter ps-js:? (test then else)
  (print-op-argument op test) " ? "
  (print-op-argument op then) " : "
  (print-op-argument op else))

(defprinter ps-js:var (var-name &optional (value (values) value?) docstring)
  (when docstring (print-comment docstring))
  "let "(psw (symbol-to-js-string var-name))
  (when value? (psw " = ") (print-op-argument 'ps-js:= value)))

(defprinter ps-js:label (label statement)
  (psw (symbol-to-js-string label))": "(ps-print statement))

(defprinter (ps-js:continue ps-js:break) (&optional label)
  (print-op op) (when label
                  (psw " " (symbol-to-js-string label))))

;;; iteration
(defprinter ps-js:for (vars tests steps body-block)
  "for ("
  (loop for ((var-name . var-init) . remaining) on vars
     for decl = "let " then "" do
       (psw decl (symbol-to-js-string var-name) " = ")
       (print-op-argument 'ps-js:= var-init)
       (when remaining (psw ", ")))
  "; "
  (loop for (test . remaining) on tests do
       (ps-print test) (when remaining (psw ", ")))
  "; "
  (loop for (step . remaining) on steps do
       (ps-print step) (when remaining (psw ", ")))
  ") "
  (ps-print body-block))

(defprinter ps-js:for-in (var object body-block)
  "for (let "(ps-print var)" in "(ps-print object)") "
  (ps-print body-block))

(defprinter (ps-js:with ps-js:while) (expression body-block)
  (print-op op)" ("(ps-print expression)") "
  (ps-print body-block))

(defprinter ps-js:switch (test &rest clauses)
  "switch ("(ps-print test)") {"
  (flet ((print-body (body)
           (incf *indent-level*)
           (loop for statement in body do
                 (newline-and-indent)
                 (ps-print statement)
                 (psw #\;))
           (decf *indent-level*)))
    (loop for (val . statements) in clauses do
         (newline-and-indent)
         (if (eq val 'ps-js:default)
             (progn (psw "default:")
                    (print-body statements))
             (progn (psw "case ") (ps-print val) (psw #\:)
                    (print-body statements)))))
  (newline-and-indent)
  "}")

(defprinter ps-js:try (body-block &key catch finally)
  "try "(ps-print body-block)
  (when catch
    (psw " catch ("(symbol-to-js-string (first catch))") ")
    (ps-print (second catch)))
  (when finally
    (psw " finally ") (ps-print finally)))

(defprinter ps-js:regex (regex)
  (let ((slash (unless (and (> (length regex) 0) (char= (char regex 0) #\/)) "/")))
    (psw (concatenate 'string slash regex slash))))

(defprinter ps-js:instanceof (value type)
  "("(print-op-argument op value)" instanceof "(print-op-argument op type)")")

(defprinter ps-js:escape (literal-js)
  ;; literal-js should be a form that evaluates to a string containing
  ;; valid JavaScript
  (psw literal-js))
