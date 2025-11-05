;; Smart Tolling Platform
;; A blockchain-based dynamic toll calculation system that adjusts pricing
;; based on real-time traffic conditions, congestion levels, and environmental factors.

;; ====================
;; CONSTANTS
;; ====================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-VEHICLE-NOT-FOUND (err u404))
(define-constant ERR-ZONE-NOT-FOUND (err u405))
(define-constant ERR-INSUFFICIENT-BALANCE (err u406))
(define-constant ERR-INVALID-PARAMETERS (err u407))
(define-constant ERR-ZONE-EXISTS (err u408))
(define-constant ERR-VEHICLE-EXISTS (err u409))

;; Maximum congestion multiplier (5x base rate)
(define-constant MAX-CONGESTION-MULTIPLIER u500)

;; Environmental factor multipliers
(define-constant CLEAN-AIR-DISCOUNT u80)  ;; 20% discount for clean air
(define-constant POOR-AIR-PENALTY u130)   ;; 30% penalty for poor air

;; ====================
;; DATA STRUCTURES
;; ====================

;; Toll zone information
(define-map toll-zones
  { zone-id: uint }
  {
    name: (string-ascii 64),
    base-rate: uint,
    capacity: uint,
    current-traffic: uint,
    environmental-factor: uint,
    active: bool,
    total-revenue: uint,
    total-crossings: uint
  }
)

;; Vehicle registration and telematics
(define-map vehicles
  { vehicle-id: (string-ascii 32) }
  {
    owner: principal,
    balance: uint,
    vehicle-type: (string-ascii 16),
    emissions-class: uint,
    total-tolls-paid: uint,
    registration-block: uint,
    active: bool
  }
)

;; Traffic monitoring data
(define-map traffic-data
  { zone-id: uint, timestamp: uint }
  {
    vehicle-count: uint,
    average-speed: uint,
    congestion-level: uint,
    air-quality-index: uint
  }
)

;; Toll transactions for auditing
(define-map toll-transactions
  { transaction-id: uint }
  {
    vehicle-id: (string-ascii 32),
    zone-id: uint,
    amount-paid: uint,
    timestamp: uint,
    congestion-factor: uint,
    environmental-factor: uint
  }
)

;; ====================
;; SYSTEM VARIABLES
;; ====================

(define-data-var platform-initialized bool false)
(define-data-var next-zone-id uint u1)
(define-data-var next-transaction-id uint u1)
(define-data-var total-platform-revenue uint u0)
(define-data-var total-vehicles-registered uint u0)
(define-data-var admin-fee-percentage uint u5)  ;; 5% admin fee

;; ====================
;; ADMINISTRATIVE FUNCTIONS
;; ====================

;; Initialize the tolling platform
(define-public (initialize-platform)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get platform-initialized)) ERR-INVALID-PARAMETERS)
    (var-set platform-initialized true)
    (ok true)
  )
)

;; Register a new toll zone
(define-public (register-toll-zone 
  (name (string-ascii 64))
  (base-rate uint)
  (capacity uint)
)
  (let (
    (zone-id (var-get next-zone-id))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (var-get platform-initialized) ERR-INVALID-PARAMETERS)
    (asserts! (> base-rate u0) ERR-INVALID-PARAMETERS)
    (asserts! (> capacity u0) ERR-INVALID-PARAMETERS)
    
    (asserts! (is-none (map-get? toll-zones { zone-id: zone-id })) ERR-ZONE-EXISTS)
    
    (map-set toll-zones
      { zone-id: zone-id }
      {
        name: name,
        base-rate: base-rate,
        capacity: capacity,
        current-traffic: u0,
        environmental-factor: u100,
        active: true,
        total-revenue: u0,
        total-crossings: u0
      }
    )
    
    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

;; Update toll zone base rate
(define-public (update-base-rate (zone-id uint) (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-rate u0) ERR-INVALID-PARAMETERS)
    
    (match (map-get? toll-zones { zone-id: zone-id })
      zone (begin
        (map-set toll-zones
          { zone-id: zone-id }
          (merge zone { base-rate: new-rate })
        )
        (ok true)
      )
      ERR-ZONE-NOT-FOUND
    )
  )
)

;; Update traffic data for dynamic pricing
(define-public (update-traffic-data 
  (zone-id uint) 
  (current-traffic uint)
  (environmental-factor uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= environmental-factor u200) ERR-INVALID-PARAMETERS)
    
    (match (map-get? toll-zones { zone-id: zone-id })
      zone (begin
        (map-set toll-zones
          { zone-id: zone-id }
          (merge zone { 
            current-traffic: current-traffic,
            environmental-factor: environmental-factor 
          })
        )
        
        ;; Store historical traffic data
        (map-set traffic-data
          { zone-id: zone-id, timestamp: burn-block-height }
          {
            vehicle-count: current-traffic,
            average-speed: u50,
            congestion-level: (calculate-congestion-factor zone-id),
            air-quality-index: environmental-factor
          }
        )
        (ok true)
      )
      ERR-ZONE-NOT-FOUND
    )
  )
)

;; ====================
;; VEHICLE FUNCTIONS
;; ====================

;; Register a vehicle for toll collection
(define-public (register-vehicle
  (vehicle-id (string-ascii 32))
  (vehicle-type (string-ascii 16))
  (emissions-class uint)
)
  (begin
    (asserts! (var-get platform-initialized) ERR-INVALID-PARAMETERS)
    (asserts! (<= emissions-class u6) ERR-INVALID-PARAMETERS)
    
    (asserts! (is-none (map-get? vehicles { vehicle-id: vehicle-id })) ERR-VEHICLE-EXISTS)
    
    (map-set vehicles
      { vehicle-id: vehicle-id }
      {
        owner: tx-sender,
        balance: u0,
        vehicle-type: vehicle-type,
        emissions-class: emissions-class,
        total-tolls-paid: u0,
        registration-block: burn-block-height,
        active: true
      }
    )
    
    (var-set total-vehicles-registered (+ (var-get total-vehicles-registered) u1))
    (ok true)
  )
)

;; Add balance to vehicle account
(define-public (add-vehicle-balance (vehicle-id (string-ascii 32)) (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-PARAMETERS)
    
    (match (map-get? vehicles { vehicle-id: vehicle-id })
      vehicle (begin
        (asserts! (is-eq tx-sender (get owner vehicle)) ERR-NOT-AUTHORIZED)
        (map-set vehicles
          { vehicle-id: vehicle-id }
          (merge vehicle { balance: (+ (get balance vehicle) amount) })
        )
        (ok (+ (get balance vehicle) amount))
      )
      ERR-VEHICLE-NOT-FOUND
    )
  )
)

;; ====================
;; TOLL CALCULATION FUNCTIONS
;; ====================

;; Calculate congestion multiplier based on current traffic vs capacity
(define-read-only (calculate-congestion-factor (zone-id uint))
  (match (map-get? toll-zones { zone-id: zone-id })
    zone (
      let (
        (traffic-ratio (/ (* (get current-traffic zone) u100) (get capacity zone)))
      )
        (if (<= traffic-ratio u50)
          u100  ;; Normal rate when under 50% capacity
          (if (<= traffic-ratio u80)
            u150  ;; 1.5x rate when 50-80% capacity
            (if (<= traffic-ratio u95)
              u200  ;; 2x rate when 80-95% capacity
              u300  ;; 3x rate when over 95% capacity
            )
          )
        )
    )
    u100  ;; Default to normal rate if zone not found
  )
)

;; Calculate emission-based discount for green vehicles
(define-read-only (calculate-emission-discount (emissions-class uint))
  (if (<= emissions-class u1)
    u50   ;; 50% discount for electric vehicles (class 0-1)
    (if (<= emissions-class u2)
      u75   ;; 25% discount for hybrid vehicles (class 2)
      (if (<= emissions-class u4)
        u90   ;; 10% discount for low-emission vehicles (class 3-4)
        u100  ;; No discount for high-emission vehicles (class 5-6)
      )
    )
  )
)

;; Calculate dynamic toll based on traffic and environmental conditions
(define-read-only (calculate-toll (zone-id uint) (vehicle-id (string-ascii 32)))
  (let (
    (zone-data (unwrap! (map-get? toll-zones { zone-id: zone-id }) ERR-ZONE-NOT-FOUND))
    (vehicle-data (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-VEHICLE-NOT-FOUND))
    (base-rate (get base-rate zone-data))
    (congestion-factor (calculate-congestion-factor zone-id))
    (environmental-factor (get environmental-factor zone-data))
    (emission-discount (calculate-emission-discount (get emissions-class vehicle-data)))
    (raw-toll (* base-rate congestion-factor))
    (env-adjusted-toll (/ (* raw-toll environmental-factor) u100))
    (final-toll (/ (* env-adjusted-toll emission-discount) u100))
  )
    (ok (/ final-toll u100))
  )
)

;; ====================
;; PAYMENT FUNCTIONS
;; ====================

;; Process toll payment
(define-public (process-payment (zone-id uint) (vehicle-id (string-ascii 32)))
  (let (
    (toll-amount (unwrap! (calculate-toll zone-id vehicle-id) ERR-INVALID-PARAMETERS))
    (vehicle-data (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-VEHICLE-NOT-FOUND))
    (zone-data (unwrap! (map-get? toll-zones { zone-id: zone-id }) ERR-ZONE-NOT-FOUND))
    (transaction-id (var-get next-transaction-id))
    (admin-fee (/ (* toll-amount (var-get admin-fee-percentage)) u100))
    (net-toll (- toll-amount admin-fee))
  )
    (asserts! (is-eq tx-sender (get owner vehicle-data)) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get balance vehicle-data) toll-amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update vehicle balance and stats
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge vehicle-data {
        balance: (- (get balance vehicle-data) toll-amount),
        total-tolls-paid: (+ (get total-tolls-paid vehicle-data) toll-amount)
      })
    )
    
    ;; Update zone stats
    (map-set toll-zones
      { zone-id: zone-id }
      (merge zone-data {
        total-revenue: (+ (get total-revenue zone-data) net-toll),
        total-crossings: (+ (get total-crossings zone-data) u1)
      })
    )
    
    ;; Record transaction
    (map-set toll-transactions
      { transaction-id: transaction-id }
      {
        vehicle-id: vehicle-id,
        zone-id: zone-id,
        amount-paid: toll-amount,
        timestamp: burn-block-height,
        congestion-factor: (calculate-congestion-factor zone-id),
        environmental-factor: (get environmental-factor zone-data)
      }
    )
    
    ;; Update system totals
    (var-set next-transaction-id (+ transaction-id u1))
    (var-set total-platform-revenue (+ (var-get total-platform-revenue) net-toll))
    
    (ok transaction-id)
  )
)

;; Emergency toll payment without balance requirement (direct STX payment)
(define-public (emergency-toll-payment (zone-id uint) (vehicle-id (string-ascii 32)))
  (let (
    (toll-amount (unwrap! (calculate-toll zone-id vehicle-id) ERR-INVALID-PARAMETERS))
    (vehicle-data (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-VEHICLE-NOT-FOUND))
    (zone-data (unwrap! (map-get? toll-zones { zone-id: zone-id }) ERR-ZONE-NOT-FOUND))
    (transaction-id (var-get next-transaction-id))
    (admin-fee (/ (* toll-amount (var-get admin-fee-percentage)) u100))
    (net-toll (- toll-amount admin-fee))
  )
    (asserts! (is-eq tx-sender (get owner vehicle-data)) ERR-NOT-AUTHORIZED)
    
    ;; Transfer STX directly for toll payment
    (try! (stx-transfer? toll-amount tx-sender (as-contract tx-sender)))
    
    ;; Update vehicle stats (no balance change for emergency payment)
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge vehicle-data {
        total-tolls-paid: (+ (get total-tolls-paid vehicle-data) toll-amount)
      })
    )
    
    ;; Update zone stats
    (map-set toll-zones
      { zone-id: zone-id }
      (merge zone-data {
        total-revenue: (+ (get total-revenue zone-data) net-toll),
        total-crossings: (+ (get total-crossings zone-data) u1)
      })
    )
    
    ;; Record transaction
    (map-set toll-transactions
      { transaction-id: transaction-id }
      {
        vehicle-id: vehicle-id,
        zone-id: zone-id,
        amount-paid: toll-amount,
        timestamp: burn-block-height,
        congestion-factor: (calculate-congestion-factor zone-id),
        environmental-factor: (get environmental-factor zone-data)
      }
    )
    
    ;; Update system totals
    (var-set next-transaction-id (+ transaction-id u1))
    (var-set total-platform-revenue (+ (var-get total-platform-revenue) net-toll))
    
    (ok transaction-id)
  )
)

;; ====================
;; READ-ONLY FUNCTIONS
;; ====================

;; Get vehicle information
(define-read-only (get-vehicle-info (vehicle-id (string-ascii 32)))
  (map-get? vehicles { vehicle-id: vehicle-id })
)

;; Get vehicle balance
(define-read-only (get-vehicle-balance (vehicle-id (string-ascii 32)))
  (match (map-get? vehicles { vehicle-id: vehicle-id })
    vehicle (ok (get balance vehicle))
    ERR-VEHICLE-NOT-FOUND
  )
)

;; Get toll zone information
(define-read-only (get-zone-info (zone-id uint))
  (map-get? toll-zones { zone-id: zone-id })
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  (ok {
    total-revenue: (var-get total-platform-revenue),
    total-vehicles: (var-get total-vehicles-registered),
    total-zones: (- (var-get next-zone-id) u1),
    total-transactions: (- (var-get next-transaction-id) u1),
    initialized: (var-get platform-initialized),
    admin-fee: (var-get admin-fee-percentage)
  })
)

;; Get transaction details
(define-read-only (get-transaction (transaction-id uint))
  (map-get? toll-transactions { transaction-id: transaction-id })
)

;; Get traffic data for analytics
(define-read-only (get-traffic-data (zone-id uint) (timestamp uint))
  (map-get? traffic-data { zone-id: zone-id, timestamp: timestamp })
)

;; Get revenue statistics for a zone
(define-read-only (get-zone-revenue-stats (zone-id uint))
  (match (map-get? toll-zones { zone-id: zone-id })
    zone (ok {
      total-revenue: (get total-revenue zone),
      total-crossings: (get total-crossings zone),
      average-toll: (if (> (get total-crossings zone) u0)
                     (/ (get total-revenue zone) (get total-crossings zone))
                     u0),
      current-congestion: (calculate-congestion-factor zone-id)
    })
    ERR-ZONE-NOT-FOUND
  )
)

;; Check if platform is operational
(define-read-only (is-platform-operational)
  (var-get platform-initialized)
)

;; Get current toll rate for a zone and vehicle (simplified version)
(define-read-only (get-current-toll-rate (zone-id uint) (vehicle-id (string-ascii 32)))
  (calculate-toll zone-id vehicle-id)
)

;; Get congestion status for all zones
(define-read-only (get-congestion-status (zone-id uint))
  (match (map-get? toll-zones { zone-id: zone-id })
    zone (
      let (
        (traffic-ratio (/ (* (get current-traffic zone) u100) (get capacity zone)))
        (congestion-level (calculate-congestion-factor zone-id))
      )
        (ok {
          traffic-ratio: traffic-ratio,
          congestion-multiplier: congestion-level,
          current-traffic: (get current-traffic zone),
          capacity: (get capacity zone),
          status: (if (<= traffic-ratio u50)
                   "normal"
                   (if (<= traffic-ratio u80)
                     "moderate"
                     (if (<= traffic-ratio u95)
                       "heavy"
                       "severe"
                     )
                   )
                 )
        })
    )
    ERR-ZONE-NOT-FOUND
  )
)

;; Administrative function to disable a zone
(define-public (disable-zone (zone-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (match (map-get? toll-zones { zone-id: zone-id })
      zone (begin
        (map-set toll-zones
          { zone-id: zone-id }
          (merge zone { active: false })
        )
        (ok true)
      )
      ERR-ZONE-NOT-FOUND
    )
  )
)

;; Administrative function to enable a zone
(define-public (enable-zone (zone-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (match (map-get? toll-zones { zone-id: zone-id })
      zone (begin
        (map-set toll-zones
          { zone-id: zone-id }
          (merge zone { active: true })
        )
        (ok true)
      )
      ERR-ZONE-NOT-FOUND
    )
  )
)
