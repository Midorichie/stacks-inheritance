;; inheritance.clar
;; Smart Contract-Based Will Execution

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXECUTED (err u101))
(define-constant ERR_CONDITION_NOT_MET (err u102))
(define-constant ERR_INVALID_ASSET (err u103))
(define-constant ERR_MISSING_BENEFICIARY (err u104))
(define-constant ERR_INVALID_PARAMS (err u105))
(define-constant ERR_WILL_NOT_FOUND (err u106))
(define-constant ERR_TRANSFER_FAILED (err u107))
(define-constant ERR_ASSET_TYPE_NOT_SUPPORTED (err u108))

;; Condition types
(define-constant CONDITION_TIME u1)
(define-constant CONDITION_EXECUTOR_APPROVAL u2)
(define-constant CONDITION_MULTIPLE_APPROVAL u3)

;; Asset types
(define-constant ASSET_STX u1)
(define-constant ASSET_FT u2)
(define-constant ASSET_NFT u3)

;; Data structures
(define-map wills
  { owner: principal }
  {
    beneficiary: principal,
    assets: (list 10 { asset-type: uint, asset-id: (optional uint), token-contract: (optional principal), amount: uint }),
    conditions: (list 5 { condition-type: uint, condition-value: uint }),
    executors: (list 5 principal),
    approvals: (list 5 principal),
    executed: bool,
    creation-height: uint
  }
)

;; Store approval status separately for multi-sig requirements
(define-map will-approvals
  { will-owner: principal, approver: principal }
  { approved: bool, approval-height: uint }
)

;; Store will execution history
(define-map execution-history
  { owner: principal }
  {
    executor: principal,
    execution-height: uint,
    beneficiary: principal
  }
)

;; Read-only functions
(define-read-only (get-will (owner principal))
  (map-get? wills { owner: owner })
)

(define-read-only (get-approval-status (will-owner principal) (approver principal))
  (default-to 
    { approved: false, approval-height: u0 } 
    (map-get? will-approvals { will-owner: will-owner, approver: approver })
  )
)

(define-read-only (get-execution-history (owner principal))
  (map-get? execution-history { owner: owner })
)

(define-read-only (has-executor-role (will-owner principal) (potential-executor principal))
  (let (
    (will-opt (get-will will-owner))
  )
    (if (is-some will-opt)
      (let (
        (will (unwrap-panic will-opt))
        (executors (get executors will))
      )
        (is-some (index-of executors potential-executor))
      )
      false
    )
  )
)

(define-read-only (check-conditions-met (owner principal))
  (let (
    (will-opt (get-will owner))
  )
    (if (is-some will-opt)
      (let (
        (will (unwrap-panic will-opt))
        (conditions (get conditions will))
      )
        (fold check-condition conditions true)
      )
      (err ERR_WILL_NOT_FOUND)
    )
  )
)

(define-private (check-condition (condition {condition-type: uint, condition-value: uint}) (result bool))
  (if (not result)
    false
    (if (is-eq (get condition-type condition) CONDITION_TIME)
      ;; Time-based condition
      (let (
        (value (get condition-value condition))
        (current-height block-height)
        (will-opt (get-will tx-sender))
      )
        (if (is-some will-opt)
          (let (
            (will (unwrap-panic will-opt))
            (creation-height (get creation-height will))
          )
            (> (- current-height creation-height) value)
          )
          false
        )
      )
      ;; Other conditions
      (if (is-eq (get condition-type condition) CONDITION_EXECUTOR_APPROVAL)
        ;; Check if any executor has approved
        (let (
          (will-opt (get-will tx-sender))
        )
          (if (is-some will-opt)
            (let (
              (will (unwrap-panic will-opt))
              (executors (get executors will))
            )
              (fold check-executor-approval executors false)
            )
            false
          )
        )
        ;; Check multiple approval condition
        (if (is-eq (get condition-type condition) CONDITION_MULTIPLE_APPROVAL)
          (let (
            (will-opt (get-will tx-sender))
          )
            (if (is-some will-opt)
              (let (
                (will (unwrap-panic will-opt))
                (executors (get executors will))
                (required-count (get condition-value condition))
              )
                (>= (fold count-approvals executors u0) required-count)
              )
              false
            )
          )
          ;; Unknown condition type, return true for now
          true
        )
      )
    )
  )
)

(define-private (check-executor-approval (executor principal) (result bool))
  (if result
    true
    (get approved (get-approval-status tx-sender executor))
  )
)

(define-private (count-approvals (executor principal) (count uint))
  (if (get approved (get-approval-status tx-sender executor))
    (+ count u1)
    count
  )
)

;; Public functions
(define-public (create-will 
  (beneficiary principal) 
  (assets (list 10 { asset-type: uint, asset-id: (optional uint), token-contract: (optional principal), amount: uint })) 
  (conditions (list 5 { condition-type: uint, condition-value: uint }))
  (executors (list 5 principal))
)
  (begin
    ;; Validate inputs
    (asserts! (not (is-eq beneficiary 'SP000000000000000000002Q6VF78)) ERR_MISSING_BENEFICIARY)
    (asserts! (> (len assets) u0) ERR_INVALID_PARAMS)
    (asserts! (> (len conditions) u0) ERR_INVALID_PARAMS)
    
    ;; Create the will
    (ok (map-set wills
      { owner: tx-sender }
      {
        beneficiary: beneficiary,
        assets: assets,
        conditions: conditions,
        executors: executors,
        approvals: (list),
        executed: false,
        creation-height: block-height
      }
    ))
  )
)

(define-public (approve-will (owner principal))
  (let (
    (will-opt (get-will owner))
  )
    (asserts! (is-some will-opt) ERR_WILL_NOT_FOUND)
    (let (
      (will (unwrap-panic will-opt))
      (is-executor (has-executor-role owner tx-sender))
    )
      (asserts! (not (get executed will)) ERR_ALREADY_EXECUTED)
      (asserts! is-executor ERR_UNAUTHORIZED)
      
      (ok (map-set will-approvals
        { will-owner: owner, approver: tx-sender }
        { approved: true, approval-height: block-height }
      ))
    )
  )
)

(define-public (execute-will (owner principal))
  (let (
    (will-opt (get-will owner))
  )
    (asserts! (is-some will-opt) ERR_WILL_NOT_FOUND)
    (let (
      (will (unwrap-panic will-opt))
      (beneficiary (get beneficiary will))
      (assets (get assets will))
      (is-executor (has-executor-role owner tx-sender))
      (conditions-met (is-ok (check-conditions-met owner)))
    )
      ;; Validate execution requirements
      (asserts! (not (get executed will)) ERR_ALREADY_EXECUTED)
      (asserts! (or is-executor (is-eq tx-sender owner)) ERR_UNAUTHORIZED)
      (asserts! conditions-met ERR_CONDITION_NOT_MET)
      
      ;; Transfer assets
      (map transfer-asset (filter filter-valid-assets assets))
      
      ;; Record execution
      (map-set execution-history
        { owner: owner }
        {
          executor: tx-sender,
          execution-height: block-height,
          beneficiary: beneficiary
        }
      )
      
      ;; Mark will as executed
      (map-set wills
        { owner: owner }
        (merge will { executed: true })
      )
      
      (ok true)
    )
  )
)

(define-private (filter-valid-assets (asset {asset-type: uint, asset-id: (optional uint), token-contract: (optional principal), amount: uint}))
  (> (get amount asset) u0)
)

(define-private (transfer-asset (asset {asset-type: uint, asset-id: (optional uint), token-contract: (optional principal), amount: uint}))
  (let (
    (will-opt (get-will tx-sender))
  )
    (if (is-some will-opt)
      (let (
        (will (unwrap-panic will-opt))
        (beneficiary (get beneficiary will))
        (asset-type (get asset-type asset))
        (amount (get amount asset))
      )
        (if (is-eq asset-type ASSET_STX)
          ;; Transfer STX
          (stx-transfer? amount tx-sender beneficiary)
          (if (is-eq asset-type ASSET_FT)
            ;; Transfer fungible token
            (let (
              (token-contract-opt (get token-contract asset))
            )
              (if (is-some token-contract-opt)
                (let (
                  (token-contract (unwrap-panic token-contract-opt))
                )
                  (contract-call? token-contract transfer amount tx-sender beneficiary none)
                )
                ERR_INVALID_ASSET
              )
            )
            (if (is-eq asset-type ASSET_NFT)
              ;; Transfer non-fungible token
              (let (
                (token-contract-opt (get token-contract asset))
                (token-id-opt (get asset-id asset))
              )
                (if (and (is-some token-contract-opt) (is-some token-id-opt))
                  (let (
                    (token-contract (unwrap-panic token-contract-opt))
                    (token-id (unwrap-panic token-id-opt))
                  )
                    (contract-call? token-contract transfer token-id tx-sender beneficiary)
                  )
                  ERR_INVALID_ASSET
                )
              )
              ERR_ASSET_TYPE_NOT_SUPPORTED
            )
          )
        )
      )
      ERR_WILL_NOT_FOUND
    )
  )
)

(define-public (revoke-will)
  (let (
    (will-opt (get-will tx-sender))
  )
    (asserts! (is-some will-opt) ERR_WILL_NOT_FOUND)
    (let (
      (will (unwrap-panic will-opt))
    )
      (asserts! (not (get executed will)) ERR_ALREADY_EXECUTED)
      
      ;; Remove the will
      (map-delete wills { owner: tx-sender })
      (ok true)
    )
  )
)
