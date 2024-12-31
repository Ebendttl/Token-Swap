;; Token Swap Contract
;; Enables users to swap between two different types of tokens with dynamic pricing
;; Includes liquidity provision, fee collection, and emergency controls

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-pool-empty (err u103))

;; Data Variables
(define-data-var token-a-balance uint u0)
(define-data-var token-b-balance uint u0)
(define-data-var exchange-rate uint u100) ;; Base rate 1:1 = 100
(define-data-var fee-percentage uint u3)  ;; 0.3% fee
(define-data-var paused bool false)

;; Maps
(define-map liquidity-providers principal
    {
        token-a-provided: uint,
        token-b-provided: uint,
        share-percentage: uint
    })

;; Read-only functions
(define-read-only (get-balances)
    {
        token-a: (var-get token-a-balance),
        token-b: (var-get token-b-balance)
    })

(define-read-only (get-exchange-rate)
    (var-get exchange-rate))

(define-read-only (get-provider-info (provider principal))
    (default-to
        {
            token-a-provided: u0,
            token-b-provided: u0,
            share-percentage: u0
        }
        (map-get? liquidity-providers provider)))

;; Calculate swap amount including fees
(define-private (calculate-swap-amount (input-amount uint))
    (let (
        (fee (* input-amount (var-get fee-percentage)))
        (base-amount (* input-amount (var-get exchange-rate)))
    )
    (/ (- base-amount fee) u100)))

;; Swap token A for token B
(define-public (swap-a-to-b (amount uint))
    (begin
        (asserts! (not (var-get paused)) (err u104))
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= amount (var-get token-a-balance)) err-insufficient-balance)
        
        (let ((output-amount (calculate-swap-amount amount)))
            (asserts! (<= output-amount (var-get token-b-balance)) err-pool-empty)
            
            ;; Update balances
            (var-set token-a-balance (+ (var-get token-a-balance) amount))
            (var-set token-b-balance (- (var-get token-b-balance) output-amount))
            
            (ok output-amount))))

;; Admin functions
(define-public (update-exchange-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set exchange-rate new-rate)
        (ok true)))

(define-public (update-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u100) (err u105))
        (var-set fee-percentage new-fee)
        (ok true)))

(define-public (toggle-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set paused (not (var-get paused)))
        (ok true)))

;; Add liquidity
(define-public (add-liquidity (token-a-amount uint) (token-b-amount uint))
    (begin
        (asserts! (not (var-get paused)) (err u104))
        (asserts! (and (> token-a-amount u0) (> token-b-amount u0)) err-invalid-amount)
        
        (let (
            (current-share (default-to u0 (get share-percentage (map-get? liquidity-providers tx-sender))))
            (total-liquidity (+ (var-get token-a-balance) (var-get token-b-balance)))
            (new-share-percentage (/ (* token-a-amount u100) total-liquidity))
        )
            ;; Update provider info
            (map-set liquidity-providers tx-sender
                {
                    token-a-provided: token-a-amount,
                    token-b-provided: token-b-amount,
                    share-percentage: (+ current-share new-share-percentage)
                })
            
            ;; Update pool balances
            (var-set token-a-balance (+ (var-get token-a-balance) token-a-amount))
            (var-set token-b-balance (+ (var-get token-b-balance) token-b-amount))
            
            (ok true))))
