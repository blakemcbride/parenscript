;;;; -*- encoding:utf-8 -*-
;;;; -*- lisp -*-

(ql:quickload :cl-ppcre)
(ql:quickload :anaphora)
(ql:quickload :named-readtables)

; muffle all compiler warnings
#+sbcl (declaim (sb-ext:muffle-conditions cl:warning))


(load "src/package")
(load "src/js-dom-symbol-exports")
(load "src/js-ir-package")
(load "src/utils")
(load "src/namespace")
(load "src/compiler")
(load "src/printer")
(load "src/compilation-interface")
(load "src/non-cl")
(load "src/special-operators")
(load "src/parse-lambda-list")
(load "src/function-definition")
(load "src/macros")
(load "src/deprecated-interface")
(load "src/lib/ps-html")
(load "src/lib/ps-loop")
(load "src/lib/ps-dom")
