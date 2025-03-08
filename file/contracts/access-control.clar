;; access-control.clar
;; Access Control contract for Inheritance System

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_EXECUTOR (err u101))
(define-constant ERR_ALREADY_REGISTERED (err u102))
(define-constant ERR_NOT_REGISTERED (err u103))
(define-constant ERR_INVALID_PERMISSION (err u104))

;; Permission levels
(define-constant PERMISSION_NONE u0)
(define-constant PERMISSION_EXECUTOR u1)
(define-constant PERMISSION_ADMIN u2)
(define-constant PERMISSION_OWNER u3)

;; Data maps
(define-map executors
  { address: principal }
  { 
    authorized: bool,
    permission-level: uint,
    registered-height: uint,
    last-updated: uint
  }
)

(define-map contract-owner
  { contract-id: principal }
  { 
    owner: principal,
    last-updated: uint
  }
)

;; Maintain a history of administrative actions for auditing
(define-map admin-history
  { transaction-id: uint }
  {
    admin: principal,
    target: principal,
    action: (string-ascii 50),
    block-height: uint
  }
)

;; Set initial contract owner
(map-set contract-owner
  { contract-id: (as-contract tx-sender) }
  { 
    owner: tx-sender,
    last-updated: block-height
  }
)

;; Global counter for transaction IDs
(define-data-var tx-counter uint u0)

;; Read-only functions
(define-read-only (is-executor (address principal))
  (let (
    (executor-data (map-get? executors { address: address }))
  )
    (if (is-some executor-data)
      (and
        (get authorized (unwrap-panic executor-data))
        (>= (get permission-level (unwrap-panic executor-data)) PERMISSION_EXECUTOR)
      )
      false
    )
  )
)

(define-read-only (get-permission-level (address principal))
  (default-to 
    PERMISSION_NONE
    (get permission-level (map-get? executors { address: address }))
  )
)

(define-read-only (get-contract-owner)
  (get owner (map-get? contract-owner { contract-id: (as-contract tx-sender) }))
)

(define-read-only (is-admin (address principal))
  (>= (get-permission-level address) PERMISSION_ADMIN)
)

(define-read-only (is-owner (address principal))
  (is-eq (some address) (get-contract-owner))
)

;; Private functions
(define-private (generate-tx-id)
  (let (
    (current-counter (var-get tx-counter))
    (new-counter (+ current-counter u1))
  )
    (var-set tx-counter new-counter)
    new-counter
  )
)

(define-private (log-admin-action (admin principal) (target principal) (action (string-ascii 50)))
  (let (
    (tx-id (generate-tx-id))
  )
    (map-set admin-history
      { transaction-id: tx-id }
      {
        admin: admin,
        target: target,
        action: action,
        block-height: block-height
      }
    )
    tx-id
  )
)

;; Public functions
(define-public (register-user (address principal) (permission-level uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? executors { address: address })) ERR_ALREADY_REGISTERED)
    (asserts! (<= permission-level PERMISSION_ADMIN) ERR_INVALID_PERMISSION)
    
    ;; Log the administrative action
    (log-admin-action tx-sender address "register-user")
    
    (ok (map-set executors
      { address: address }
      { 
        authorized: true,
        permission-level: permission-level,
        registered-height: block-height,
        last-updated: block-height
      }
    ))
  )
)

(define-public (update-permission (address principal) (permission-level uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? executors { address: address })) ERR_NOT_REGISTERED)
    (asserts! (<= permission-level PERMISSION_ADMIN) ERR_INVALID_PERMISSION)
    
    ;; Log the administrative action
    (log-admin-action tx-sender address "update-permission")
    
    (let (
      (executor-data (unwrap-panic (map-get? executors { address: address })))
    )
      (ok (map-set executors
        { address: address }
        (merge executor-data { 
          permission-level: permission-level,
          last-updated: block-height
        })
      ))
    )
  )
)

(define-public (deactivate-user (address principal))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? executors { address: address })) ERR_NOT_REGISTERED)
    
    ;; Log the administrative action
    (log-admin-action tx-sender address "deactivate-user")
    
    (let (
      (executor-data (unwrap-panic (map-get? executors { address: address })))
    )
      (ok (map-set executors
        { address: address }
        (merge executor-data { 
          authorized: false,
          last-updated: block-height
        })
      ))
    )
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq (some tx-sender) (get-contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Log the administrative action
    (log-admin-action tx-sender new-owner "transfer-ownership")
    
    (ok (map-set contract-owner
      { contract-id: (as-contract tx-sender) }
      { 
        owner: new-owner,
        last-updated: block-height
      }
    ))
  )
)
