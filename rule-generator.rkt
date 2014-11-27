#lang racket

; Currently assuming register-based.

(provide make-instruction
         instruction-struct-name instruction-struct-arguments
         instruction-struct-string-gen instruction-struct-behavior
         instruction-struct-rules)

(require "utilities.rkt")
(require "common.rkt")
(require "boxdag-rules.rkt")

(struct instruction-struct
  (name arguments string-gen behavior rules) #:inspector #f)

; arguments: ((name predicate) ...)
(define (convert-behavior-expr arguments behavior)
  (if (symbol? behavior)
      (if (assoc behavior arguments)
          (let ((predicate (second (assoc behavior arguments))))
            (cond [(eq? predicate const?) (list 'const behavior 'u4)] ; TODO: don't hardcode type
                  [(eq? predicate symbol?) behavior]
                  [else (error "Uncertain how to handle raw argument:" behavior)]))
          (error "Uncertain how to handle raw non-argument symbol:" behavior))
      (case (car behavior)
        ('get-reg
         (assert (= (length behavior) 2) "get-reg expects one argument")
         (assert (symbol? (second behavior)) "get-reg expects a symbol argument")
         (second behavior))
        (else
         (cons (car behavior) (map (curry convert-behavior-expr arguments) (cdr behavior)))))))

(define (convert-behavior-line arguments behavior)
  (case (car behavior)
    ('set-reg
     (assert (= (length behavior) 3) "set-reg expects two arguments")
     (convert-behavior-expr arguments (third behavior)))
    ('discard
     (assert (= (length behavior) 2) "discard expects one argument")
     (convert-behavior-expr arguments (second behavior)))
    ('return
     (assert (= (length behavior) 2) "return expects one argument")
     (list 'return (convert-behavior-expr arguments (second behavior))))
    (else (error "Unexpected behavior type" (car behavior)))))

(define (check-used-in zone arg-pair)
  (let ((arg (car arg-pair)))
    (define (used-in-iter part)
      (or (eq? part arg)
          (and (pair? part)
               (or (used-in-iter (car part))
                   (used-in-iter (cdr part))))))
    (used-in-iter zone)))

(define (build-converted-rule name arguments enum-pair)
  (let ((conv-id (car enum-pair))
        (conv (cdr enum-pair)))
    (boxdag-rule
     (map (lambda (x)
            (assert (= (length x) 2) "Bad argument declaration")
            (cons (first x) (second x))) arguments)
     conv
     (if (null? conv-id)
         (cons name (map car arguments))
         (list 'generic/subresult conv-id (cons name (map car arguments)))))))


(define (convert-behavior name arguments behavior) ; doing: should return rules, not rule
  (if (eq? (car behavior) 'multiple)
      (let* ((convs (map (curry convert-behavior-line arguments) (cdr behavior)))
             (used-arguments (filter (curry check-used-in convs) arguments)))
        (map (curry build-converted-rule name used-arguments)
                  (enumerate convs)))
      (let* ((conv (convert-behavior-line arguments behavior))
             (used-arguments (filter (curry check-used-in conv) arguments)))
        (list (build-converted-rule name used-arguments (cons null conv))))))

(define (make-instruction name args string-gen behavior)
  (instruction-struct name args string-gen behavior
                      (convert-behavior name args behavior)))

;(convert-behavior 'x86/cmp/dd '((a any?) (b any?))
;                  '(multiple
;                    (set-reg carry-flag (unsigned< (get-reg a) (get-reg b)))
;                    (set-reg zero-flag (= (get-reg a) (get-reg b)))
;                    (set-reg sign-flag-xor-overflow-flag (< (get-reg a) (get-reg b)))))