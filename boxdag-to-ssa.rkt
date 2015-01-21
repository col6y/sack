#lang racket

(provide full-ssaify)

(require "utilities.rkt")
(require "boxdag.rkt")

(define sample-duplicated-set
  (make-boxdag '(logical/or
                 (generic/subresult
                  2
                  (x86/cmp/dd
                   (x86/movfm/d (get-reg ebp))
                   (x86/mov/c 1)))
                 (generic/subresult
                  1
                  (x86/cmp/dd
                   (x86/movfm/d (get-reg ebp))
                   (x86/mov/c 1))))))
(define sample-complex-set
  
   '((preserve85608
      .
      #&(x86/push/d
         #&(x86/movfm/d #&(x86/add/dc #&(get-reg ebp) 12))))
     (preserve85609 . #&(x86/call a))
     (preserve85610 . #&(x86/pop))
     (preserve85600
      .
      #&(x86/push/d #&(boxdag/preserve-ref preserve85609)))
     (preserve85605 . #&(x86/push/c 30))
     (preserve85606 . #&(x86/call b))
     (preserve85607 . #&(x86/pop))
     (preserve85601
      .
      #&(x86/push/d #&(boxdag/preserve-ref preserve85606)))
     (preserve85602 . #&(x86/call hello))
     (preserve85603 . #&(x86/pop))
     (preserve85604 . #&(x86/pop))
     (() . #&(boxdag/preserve-ref preserve85602))))
(define sample-preserve-set
  '(() . (return (x86/add/dd
                  (x86/movfm/d (x86/add/dd (get-reg ebp) (x86/mov/c 8)))
                  (x86/movfm/d (x86/add/dd (get-reg ebp) (x86/mov/c 12)))))))
(define sample-single-node
  '(return (x86/add/dd
            (x86/movfm/d (x86/add/dd (get-reg ebp) (x86/mov/c 8)))
            (x86/movfm/d (x86/add/dd (get-reg ebp) (x86/mov/c 12))))))


(struct ssaified-reference (ref stmts) #:inspector #f)

(define (make-ssaified-reference pair)
  (ssaified-reference (car pair) (cdr pair)))
(define (get-ssa)
  (box (void)))
(define (is-simple-ref x)
  (member (car x) '(get-reg)))
(define (ssaify x (is-top-level #f)) ; returns ('ssa ssa-id) . ((ssa . code) (ssa . code) ...) OR x . empty
  (cond ((and (pair? x) (eq? (car x) 'boxdag/preserve-ref))
         (cons (second x) empty))
        ((and (pair? x) (not (is-simple-ref x)))
         (let ((gotten (ssaify-node x)))
           (cons (list 'ssa (car gotten)) (cdr gotten))))
        ((and (box? x) is-top-level)
         (ssaify (unbox x)))
        ((and (box? x) (ssaified-reference? (unbox x)))
         (cons (ssaified-reference-ref (unbox x)) empty))
        ((box? x)
         (set-box! x (make-ssaified-reference (ssaify (unbox x))))
         (cons (ssaified-reference-ref (unbox x)) (ssaified-reference-stmts (unbox x))))
        (else (cons x empty))))
(define (ssaify-all xes) ; returns (('ssa ssa-id) OR x ...) . ((ssa . code) (ssa . code) ...)
  (let ((processed (map ssaify xes)))
    (cons (map car processed) (append* (map cdr processed)))))
(define (ssaify-node x) ; returns ssa-id (ssa . code) (ssa . code) ...
  (let* ((name (car x))
         (processed (ssaify-all (cdr x)))
         (args (car processed))
         (stmts (cdr processed))
         (ssa (get-ssa)))
    (assert (symbol? name) "Expected a symbol head.")
    (cons ssa (suffix stmts
                      (cons ssa (cons name args))))))
(define (replace-all x replacements)
  (cond [(assoc x replacements) (cdr (assoc x replacements))]
        [(pair? x) (cons (replace-all (car x) replacements)
                         (replace-all (cdr x) replacements))]
        [(box? x) (set-box! x (replace-all (unbox x) replacements))
                  x]
        [else x]))
(define (ssaify-multi-element x)
  (let ((ssa-out (car x))
        (ssaified (ssaify (cdr x) #t)))
    (when (box? ssa-out)
        (set-box! ssa-out (car ssaified)))
    ssaified))
(define (ssaify-multi x) ; returns ssa-id (ssa . code) (ssa . code) ...
  (let ((targets (map car x)))
    (assert (= 1 (length (filter empty? targets))) "Should be exactly one result preserve!")
    (assert (empty? (last targets)) "The last preserve should be the result preserve!")
    (let ((replacements (map (lambda (target) (cons target (get-ssa)))
                             (filter (lambda (x) (not (empty? x))) targets))))
      (let ((processed (map ssaify-multi-element (replace-all x replacements))))
        (cons (car (last processed))
              (append* (map cdr processed)))))))

(define (assign-ssa pair)
  (assert (void? (unbox (cadr pair))) "Expected ssa to be unassigned.")
  (set-box! (cadr pair) (car pair)))
(define (assign-ssas x)
  (map assign-ssa (enumerate (cdr x)))
  (strip-boxes x))

; Note that full-ssaify will mangle the boxdag's contents.
(define (full-ssaify x)
  (assign-ssas (ssaify-multi x)))

;(full-ssaify (get-boxdag-contents sample-duplicated-set))
;(full-ssaify sample-complex-set)