;; access-control.clar
;; Access Control contract for Inheritance System

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_EXECUTOR (err u101))

;; Data maps
(define-map executors
  { address: principal }
  { authorized: bool }
)

(define-map contract-owner
  { contract-id: principal }
  { owner: principal }
)

;; Set initial contract owner
(map-set contract-owner
  { contract-id: (as-contract tx-sender) }
  { owner: tx-sender }
)

;; Read-only functions
(define-read-only (is-executor (address principal))
  (default-to false (get authorized (map-get? executors { address: address })))
)

(define-read-only (get-contract-owner)
  (get owner (map-get? contract-owner { contract-id: (as-contract tx-sender) }))
)

;; Public functions
(define-public (add-executor (address principal))
  (begin
    (asserts! (is-eq tx-sender (unwrap-panic (get-contract-owner))) ERR_UNAUTHORIZED)
    (ok (map-set executors
      { address: address }
      { authorized: true }
    ))
  )
)

(define-public (remove-executor (address principal))
  (begin
    (asserts! (is-eq tx-sender (unwrap-panic (get-contract-owner))) ERR_UNAUTHORIZED)
    (ok (map-set executors
      { address: address }
      { authorized: false }
    ))
  )
)
