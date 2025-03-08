;; time-verification.clar
;; Time-based verification for inheritance contract

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_TIMELOCK (err u101))
(define-constant ERR_TIMELOCK_NOT_EXPIRED (err u102))
(define-constant ERR_NO_ACTIVE_TIMELOCK (err u103))

;; Data maps
(define-map timelocks
  { owner: principal }
  {
    start-height: uint,
    expiration-blocks: uint,
    activated: bool,
    last-heartbeat-height: uint,
    heartbeat-required: bool,
    executor: (optional principal)
  }
)

;; Read-only functions
(define-read-only (get-timelock (owner principal))
  (map-get? timelocks { owner: owner })
)

(define-read-only (is-timelock-expired (owner principal))
  (let (
    (timelock-opt (get-timelock owner))
  )
    (if (is-some timelock-opt)
      (let (
        (timelock (unwrap-panic timelock-opt))
        (current-height block-height)
        (start (get start-height timelock))
        (expiration (get expiration-blocks timelock))
        (last-heartbeat (get last-heartbeat-height timelock))
        (heartbeat-req (get heartbeat-required timelock))
      )
        (if heartbeat-req
          ;; If heartbeat is required, check elapsed time since last heartbeat
          (> (- current-height last-heartbeat) expiration)
          ;; Otherwise check elapsed time since start
          (> (- current-height start) expiration)
        )
      )
      false
    )
  )
)

;; Public functions
(define-public (create-timelock (expiration-blocks uint) (heartbeat-required bool) (executor (optional principal)))
  (begin
    (asserts! (> expiration-blocks u0) ERR_INVALID_TIMELOCK)
    (ok (map-set timelocks
      { owner: tx-sender }
      {
        start-height: block-height,
        expiration-blocks: expiration-blocks,
        activated: true,
        last-heartbeat-height: block-height,
        heartbeat-required: heartbeat-required,
        executor: executor
      }
    ))
  )
)

(define-public (send-heartbeat)
  (let (
    (timelock-opt (get-timelock tx-sender))
  )
    (asserts! (is-some timelock-opt) ERR_NO_ACTIVE_TIMELOCK)
    (let (
      (timelock (unwrap-panic timelock-opt))
    )
      (asserts! (get activated timelock) ERR_NO_ACTIVE_TIMELOCK)
      (ok (map-set timelocks
        { owner: tx-sender }
        (merge timelock { last-heartbeat-height: block-height })
      ))
    )
  )
)

(define-public (verify-timelock-expiration (owner principal))
  (let (
    (timelock-opt (get-timelock owner))
  )
    (asserts! (is-some timelock-opt) ERR_NO_ACTIVE_TIMELOCK)
    (let (
      (timelock (unwrap-panic timelock-opt))
      (authorized (or 
                    (is-eq tx-sender owner)
                    (is-eq (some tx-sender) (get executor timelock))
                  ))
    )
      (asserts! authorized ERR_UNAUTHORIZED)
      (asserts! (get activated timelock) ERR_NO_ACTIVE_TIMELOCK)
      (asserts! (is-timelock-expired owner) ERR_TIMELOCK_NOT_EXPIRED)
      (ok true)
    )
  )
)

(define-public (deactivate-timelock)
  (let (
    (timelock-opt (get-timelock tx-sender))
  )
    (asserts! (is-some timelock-opt) ERR_NO_ACTIVE_TIMELOCK)
    (let (
      (timelock (unwrap-panic timelock-opt))
    )
      (ok (map-set timelocks
        { owner: tx-sender }
        (merge timelock { activated: false })
      ))
    )
  )
)
