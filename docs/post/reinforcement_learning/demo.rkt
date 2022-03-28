#lang racket

(require racket/gui/base)

(define HOOK-X 0)
(define HOOK-Y 0)
(define CONTAINER-X 3)
(define CONTAINER-Y 5)
(define HOOK-CLOSED? #f)  
(define SHOW-GAME-SCREEN? #t)
(define DRAW-COORDINATES? #t)
(define TIME 100)

;Game Graphics ADT

(define (game-graphics-adt show-game-screen?)

  (define window-width 700)
  (define window-height 700)
  
  (define (make-frame label width height)
    (new frame%
         [label label]
         [width width]
         [height height]))

  (define (make-canvas parent style)
    (new canvas%
         [parent parent]
         [style style]))

  (define (get-bitmap file)
    (let ((bitmap (make-bitmap 1 1 2.0)))
      (send bitmap load-file file)
      bitmap))

  (define background-bitmap (get-bitmap "images/background.png"))
  (define container-bitmap (get-bitmap "images/container.png"))
  (define container-hook-close-bitmap (get-bitmap "images/container-hook-close.png"))
  (define container-hook-open-bitmap (get-bitmap "images/container-hook-open.png"))
  (define hook-close-bitmap (get-bitmap "images/hook-close.png"))
  (define hook-open-bitmap (get-bitmap "images/hook-open.png"))
  (define cable-bitmap (get-bitmap "images/cable.png"))

  (define side-width (/ window-width 14))
  (define side-height (/ window-height 14))
  (define block-width (/ window-width 7))
  (define block-height (/ window-height 7))
  (define scale-x (/ window-width 700))
  (define scale-y (/ window-height 700))

  (define (scale-bitmap scale-x scale-y bitmap)
    (let* ((bitmap-width (send bitmap get-width))
           (bitmap-height (send bitmap get-height))
           (target-width (inexact->exact (ceiling (* bitmap-width scale-x))))
           (target-height (inexact->exact (ceiling (* bitmap-height scale-y))))
           (target-bitmap (make-bitmap target-width target-height 2.0))
           (target-dc (make-object bitmap-dc% target-bitmap)))
      (send target-dc set-scale scale-x scale-y)
      (send target-dc draw-bitmap bitmap 0 0)
      (send target-dc get-bitmap)))
  
  (define window (make-frame "Game Graphics" window-width window-height))
  
  (define drawing-canvas (make-canvas window (list 'no-autoclear)))
            
  (define (draw-background)
    (let ((dc (send drawing-canvas get-dc)))
      (send dc draw-bitmap (scale-bitmap scale-x scale-y background-bitmap) 0 0)))
  
  (define (draw-bitmap bitmap x y)    
    (let* ((fetched-bitmap (cond ((eq? bitmap 'container) container-bitmap)
                                 ((eq? bitmap 'container-hook-close) container-hook-close-bitmap)
                                 ((eq? bitmap 'container-hook-open) container-hook-open-bitmap)
                                 ((eq? bitmap 'hook-close) hook-close-bitmap)
                                 ((eq? bitmap 'hook-open) hook-open-bitmap)
                                 ((eq? bitmap 'cable) cable-bitmap)
                                 (else "invalid bitmap")))                               
           (scaled-bitmap (scale-bitmap scale-x scale-y fetched-bitmap))
           (dc (send drawing-canvas get-dc))
           (x-pixel (+ side-width (* x block-width)))
           (y-pixel (+ side-height (* y block-height))))
      (send dc draw-bitmap scaled-bitmap x-pixel y-pixel)))  

  (define (show-game-window boolean)
    (send window show boolean))

  (show-game-window show-game-screen?)
    
  (define (dispatch-game-graphics msg)
    (cond ((eq? msg 'draw-background) draw-background)
          ((eq? msg 'draw-bitmap) draw-bitmap)
          ((eq? msg 'show-game-window) show-game-window)))
  dispatch-game-graphics)

;Game Logic ADT

(define (game-logic-adt hook-x hook-y container-x container-y hook-closed?)
  
  (define (hook-x! new-x)
    (set! hook-x new-x))
  (define (hook-y! new-y)
    (set! hook-y new-y))
  (define (container-x! new-x)
    (set! container-x new-x))
  (define (container-y! new-y)
    (set! container-y new-y))

  (define (hook! new-boolean)
    (set! hook-closed? new-boolean))
  
  (define (hook-container-eq?)
    (and (= hook-x container-x)
             (= hook-y container-y)))

  (define (goal-state)
    (cond ((and (= container-x 5)
                (= container-y 1))
           4)
          ((and (hook-container-eq?)
                hook-closed?)
           3)
          ((or (and (hook-container-eq?)
                    (not hook-closed?))
               (and (= hook-y (- container-y 1))
                    (= hook-x container-x)
                    (not hook-closed?)))
           2)
          (else 1)))

  (define (distance x1 y1 x2 y2)
    (sqrt (+ (expt (- x1 x2) 2) (expt (- y1 y2) 2))))
  
  (define (got-closer? x-old y-old x-new y-new x-goal y-goal)
    (let ((distance-old (distance x-old y-old x-goal y-goal))
          (distance-new (distance x-new y-new x-goal y-goal)))
      (if (> distance-old distance-new)
          'green
          'orange)))

  (define (reward keyword old-goal-state old-hook-x old-hook-y)
    (let ((current-goal-state (goal-state)))
      (cond ((< current-goal-state old-goal-state)
             'orange)
            ((> current-goal-state old-goal-state)
             'green)
            ((= current-goal-state 1)
             (cond ((eq? keyword 'open)
                    'green)
                   ((eq? keyword 'close)
                    'orange)
                   (else
                    (got-closer? old-hook-x old-hook-y hook-x hook-y
                                 container-x (- container-y 1)))))
            ((= current-goal-state 2)
             (if (eq? keyword 'down)
                 'green
                 'orange))
            ((= current-goal-state 3)
             (got-closer? old-hook-x old-hook-y hook-x hook-y 5 1))
            ((= current-goal-state 4)
             'final-state-reached))))

  (define (left-allowed?)
    (and (> hook-x 0)
         (not (and (= hook-x (+ container-x 1))
                   (= hook-y 5)))
         (not (and (hook-container-eq?)
                   (not hook-closed?)))))

  (define (right-allowed?)
    (and (or (and (< hook-x 5)
                  (< hook-y 2))
             (and (< hook-x 4)
                  (> hook-y 1)))
         (not (and (= hook-x (- container-x 1))
                   (or (= hook-y 5)
                       (and (= hook-y 1)
                            (= container-y 1)))))
         (not (and (hook-container-eq?)
                   (not hook-closed?)))))

  (define (up-allowed?)
    (> hook-y 0))

  (define (down-allowed?)
    (and (or (and (< hook-y 5)
                  (< hook-x 5))
             (and (< hook-y 1)
                  (> hook-x 4)))
         (not (and (= hook-y (- container-y 1))
                   (= hook-x container-x)
                   hook-closed?))))
    
  (define (action! keyword)
    (let ((old-hook-x hook-x)
          (old-hook-y hook-y)
          (old-goal-state (goal-state)))
      (cond ((eq? keyword 'left)
             (if (left-allowed?)
                 (begin
                   (if (hook-container-eq?)
                       (begin
                         (hook-x! (- hook-x 1))
                         (container-x! (- container-x 1)))
                       (hook-x! (- hook-x 1)))
                   (reward keyword old-goal-state old-hook-x old-hook-y))
                 'red))
            ((eq? keyword 'right)
             (if (right-allowed?)
                 (begin
                   (if (hook-container-eq?)
                       (begin
                         (hook-x! (+ hook-x 1))
                         (container-x! (+ container-x 1)))
                       (hook-x! (+ hook-x 1)))
                   (reward keyword old-goal-state old-hook-x old-hook-y))
                 'red))
            ((eq? keyword 'up)
             (if (up-allowed?)
                 (begin
                   (if (and (hook-container-eq?)
                            hook-closed?)
                       (begin
                         (hook-y! (- hook-y 1))
                         (container-y! (- container-y 1)))
                       (hook-y! (- hook-y 1)))
                   (reward keyword old-goal-state old-hook-x old-hook-y))
                 'red))
            ((eq? keyword 'down)
             (if (down-allowed?)
                 (begin
                   (if (hook-container-eq?)
                       (begin
                         (hook-y! (+ hook-y 1))
                         (container-y! (+ container-y 1)))
                       (hook-y! (+ hook-y 1)))
                   (reward keyword old-goal-state old-hook-x old-hook-y))
                 'red))
            ((eq? keyword 'open)
             (if hook-closed?
                 (if (or (and (= container-x 5) (= container-y 0))
                         (and (< container-y 5) (< container-x 5)))
                     'red
                     (begin
                       (hook! #f)
                       (reward keyword old-goal-state old-hook-x old-hook-y)))
                 'red))
            ((eq? keyword 'close)
             (if hook-closed?
                 'red
                 (begin
                   (hook! #t)
                   (reward keyword old-goal-state old-hook-x old-hook-y)))))))

  (define (draw-list)
    (let ((result '()))
      (if (hook-container-eq?)
          (if hook-closed?
              (set! result (cons (list 'container-hook-close hook-x hook-y) result))
              (set! result (cons (list 'container-hook-open hook-x hook-y) result)))
          (begin
            (if hook-closed?
                (set! result (cons (list 'hook-close hook-x hook-y) result))
                (set! result (cons (list 'hook-open hook-x hook-y) result)))
            (set! result (cons (list 'container container-x container-y) result))))
      (let cable-loop ((cable-y 0))
        (if (< cable-y hook-y)
            (begin
              (set! result (cons (list 'cable hook-x cable-y) result))
              (cable-loop (+ cable-y 1)))
            result))))           
                   
  (define (dispatch-game-logic msg)
    (cond ((eq? msg 'hook-x) hook-x)
          ((eq? msg 'hook-y) hook-y)
          ((eq? msg 'container-x) container-x)
          ((eq? msg 'container-y) container-y)
          ((eq? msg 'hook-x!) hook-x!)
          ((eq? msg 'hook-y!) hook-y!)
          ((eq? msg 'container-x!) container-x!)
          ((eq? msg 'container-y!) container-y!)
          ((eq? msg 'hook-closed?) hook-closed?)
          ((eq? msg 'hook!) hook!)
          ((eq? msg 'action!) action!)
          ((eq? msg 'draw-list) draw-list)))
  dispatch-game-logic)

;Controller ADT

(define (controller-adt game-graphics game-logic draw-coordinates? time show-game-screen?)

  (define (make-frame label width height)
    (new frame%
         [label label]
         [width width]
         [height height]))

  (define (make-horizontal-panel parent style alignment)
    (new horizontal-panel%
         [parent parent]
         [style style]
         [alignment alignment]))

  (define (make-vertical-panel parent style alignment)
    (new vertical-panel%
         [parent parent]
         [style style]
         [alignment alignment]))

  (define (make-canvas parent style)
    (new canvas%
         [parent parent]
         [style style]))

  (define (make-button label parent callback)
    (new button%
         [label label]
         [parent parent]
         [callback callback]))

  (define window (make-frame "Controller" 300 400))

  (define reward-panel (make-horizontal-panel window
                                              (list 'border)
                                              (list 'center 'top)))

  (define reward-canvas (make-canvas reward-panel (list 'no-autoclear)))

  (define reward-dc (send reward-canvas get-dc))

  (define red-brush (new brush% [color "red"]))
  (define orange-brush (new brush% [color "orange"]))
  (define green-brush (new brush% [color "green"]))
  (define white-brush (new brush% [color "white"]))

  (define red-pen (new pen% [color "red"]))
  (define orange-pen (new pen% [color "orange"]))
  (define green-pen (new pen% [color "green"]))

  (define (draw-circle color)
    (cond ((eq? color 'red)
           (send reward-dc set-brush red-brush)
           (send reward-dc set-pen red-pen)
           (send reward-dc draw-ellipse 2 4 50 50))
          ((eq? color 'orange)
           (send reward-dc set-brush orange-brush)
           (send reward-dc set-pen orange-pen)
           (send reward-dc draw-ellipse 117 4 50 50))
          ((eq? color 'green)
           (send reward-dc set-brush green-brush)
           (send reward-dc set-pen green-pen)
           (send reward-dc draw-ellipse 232 4 50 50))
          ((eq? color 'white)
           (send reward-dc set-brush white-brush)
           (send reward-dc set-pen red-pen)
           (send reward-dc draw-ellipse 2 4 50 50)
           (send reward-dc set-pen orange-pen)
           (send reward-dc draw-ellipse 117 4 50 50)
           (send reward-dc set-pen green-pen)
           (send reward-dc draw-ellipse 232 4 50 50))))

  (define game-over? #f)
  
  (define (game-over keyword)
    (set! game-over? #t)
    (send reward-dc erase)
    (send reward-dc set-font (make-font #:size 30))
    (if (eq? keyword 'win)
        (send reward-dc draw-text "YOU WON!" 45 2)
        (send reward-dc draw-text "YOU LOST!" 45 2))
    (create-log-file keyword))

  (define button-panel (make-vertical-panel window
                                            (list 'border)
                                            (list 'center 'center)))

  (define reward-vector (make-vector 3 0))

  (define (reward-vector++ index)
    (vector-set! reward-vector index (+ (vector-ref reward-vector index)1)))
  
  (define (reward-vector-ref index)
    (vector-ref reward-vector index))

  (define (log-reward reward)
    (cond ((eq? reward 'red)
           (reward-vector++ 0))
          ((eq? reward 'orange)
           (reward-vector++ 1))
          (else
           (reward-vector++ 2))))

  (define (random-file-name)
    (define file-name ".txt")
    (let random-file-name-loop ((n 30))
      (when (> n 0)
        (set! file-name (string-append (number->string (random 10)) file-name))
        (random-file-name-loop (- n 1))))
    file-name)

  (define (create-log-file keyword)
    (define file (open-output-file (random-file-name)))
    (display "Game window shown? " file)
    (display show-game-screen? file)
    (display "\nRed: " file)
    (display (reward-vector-ref 0) file)
    (display "\nOrange: " file)
    (display (reward-vector-ref 1) file)
    (display "\nGreen: " file)
    (display (reward-vector-ref 2) file)
    (display "\nTime: " file)
    (display (- time seconds) file)
    (display "\nGame: " file)
    (display keyword file)
    (display "\nActions: " file)
    (display (reverse action-list) file)
    (close-output-port file))

  (define initial-hook-x (game-logic 'hook-x))
  (define initial-hook-y (game-logic 'hook-y))
  (define initial-container-x (game-logic 'container-x))
  (define initial-container-y (game-logic 'container-y))
  (define initial-hook-closed? (game-logic 'hook-closed?))

  (define action-list '())
         
  (define (draw-loop)
    ((game-graphics 'draw-background))
    (let draw-loop ((draw-list ((game-logic 'draw-list))))
      (if (empty? draw-list)
          'done
          (let* ((current (car draw-list))
                 (bitmap (car current))
                 (x (cadr current))
                 (y (caddr current)))
            ((game-graphics 'draw-bitmap) bitmap x y)
            (draw-loop (cdr draw-list))))))
  
  (define (button keyword label)
    (make-button label button-panel
                 (lambda (button event)
                   (when (not game-over?)
                     (set! action-list (cons keyword action-list))
                     (let ((reward ((game-logic 'action!) keyword)))
                       (when (= seconds (+ time 1))
                         (set! seconds (- seconds 1))
                         (send timer start 1000))
                       (log-reward reward)
                       (draw-loop)
                       (when draw-coordinates?
                         (draw-coordinates))
                       (draw-circle reward)
                       (sleep/yield 0.3)
                       (draw-circle 'white)
                       (cond ((eq? reward 'final-state-reached)
                              (send timer stop)
                              (game-over 'win))))))))

  (define left-button (button 'left "1"))
  (define right-button (button 'right "2"))
  (define up-button (button 'up "3"))
  (define down-button (button 'down "4"))
  (define open-button (button 'open "5"))
  (define close-button (button 'close "6"))

  (define extra-button-panel (make-horizontal-panel window
                                                    (list 'border)
                                                    (list 'center 'top)))

  (define give-up-button
    (make-button "Give up" extra-button-panel
                 (lambda (button event)
                   (when (not game-over?)
                     (send timer stop)
                     (game-over 'lose)))))

  (define view-game-button
    (make-button "View game" extra-button-panel
                 (lambda (button event)
                   (when game-over?
                     ((game-logic 'hook-x!) initial-hook-x)
                     ((game-logic 'hook-y!) initial-hook-y)
                     ((game-logic 'container-x!) initial-container-x)
                     ((game-logic 'container-y!) initial-container-y)
                     ((game-logic 'hook!) initial-hook-closed?)
                     ((game-graphics 'show-game-window) #t)
                     (sleep/yield 0.1)
                     (draw-loop)
                     (let view-game-loop ((actions (reverse action-list)))
                       (when (not (empty? actions))
                         ((game-logic 'action!) (car actions))
                         (draw-loop)
                         (sleep/yield 0.3)
                         (view-game-loop (cdr actions))))))))

  (define coordinate-canvas (make-canvas button-panel (list 'no-autoclear)))

  (define coordinate-dc (send coordinate-canvas get-dc))

  (define (draw-coordinates)
    (send coordinate-dc erase)
    (send coordinate-dc draw-text (number->string (game-logic 'hook-x)) 100 5)
    (send coordinate-dc draw-text (number->string (game-logic 'hook-y)) 137 5)
    (send coordinate-dc draw-text (if (game-logic 'hook-closed?) "1" "0") 174 5))

  (define timer-canvas (make-canvas button-panel (list 'no-autoclear)))

  (define timer-dc (send timer-canvas get-dc))
  
  (define seconds (+ time 1))
  
  (define timer
    (new timer% [notify-callback
                 (lambda ()
                   (send timer-dc erase)
                   (send timer-dc draw-text (number->string seconds) 4 5)
                   (when (= seconds 0)
                     (send timer stop)
                     (game-over 'lose))
                   (set! seconds (- seconds 1)))]))
  
  (send window show #t)
  
  (sleep/yield 0.1)
  (draw-loop)
  (when draw-coordinates?
    (draw-coordinates))
  (draw-circle 'white))
  
;Creating ADT's

(define game-graphics (game-graphics-adt SHOW-GAME-SCREEN?))
(define game-logic (game-logic-adt HOOK-X HOOK-Y CONTAINER-X CONTAINER-Y HOOK-CLOSED?))
(define controller (controller-adt game-graphics game-logic DRAW-COORDINATES? TIME SHOW-GAME-SCREEN?))
