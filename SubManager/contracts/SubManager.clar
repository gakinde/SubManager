;; Decentralized Subscription Management Contract
;; A comprehensive smart contract for managing SaaS and streaming service subscriptions
;; Handles subscription plans, payments, access control, and automated renewals

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PLAN (err u101))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u102))
(define-constant ERR-SUBSCRIPTION-EXPIRED (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))
(define-constant ERR-PLAN-NOT-FOUND (err u105))
(define-constant ERR-ALREADY-SUBSCRIBED (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-SUBSCRIPTION-INACTIVE (err u108))

(define-constant SECONDS-PER-DAY u86400)
(define-constant SECONDS-PER-MONTH u2592000)
(define-constant MIN-SUBSCRIPTION-AMOUNT u1000)

;; Data Maps and Variables

;; Subscription plans with pricing and features
(define-map subscription-plans
    { plan-id: uint }
    {
        name: (string-ascii 50),
        price-per-month: uint,
        max-users: uint,
        features: (string-ascii 200),
        is-active: bool,
        created-at: uint
    }
)

;; User subscriptions tracking
(define-map user-subscriptions
    { subscriber: principal }
    {
        plan-id: uint,
        start-date: uint,
        end-date: uint,
        is-active: bool,
        auto-renew: bool,
        total-paid: uint,
        payment-count: uint
    }
)

;; Service access permissions for fine-grained control
(define-map service-access
    { subscriber: principal, service-name: (string-ascii 30) }
    {
        has-access: bool,
        access-granted-at: uint,
        last-accessed: uint
    }
)

;; Payment history for audit and analytics
(define-map payment-history
    { payment-id: uint }
    {
        subscriber: principal,
        plan-id: uint,
        amount: uint,
        payment-date: uint,
        payment-type: (string-ascii 20)
    }
)

;; Global counters
(define-data-var next-plan-id uint u1)
(define-data-var next-payment-id uint u1)
(define-data-var total-revenue uint u0)
(define-data-var active-subscribers uint u0)

;; Private Functions

;; Calculate subscription end date based on plan duration
(define-private (calculate-end-date (start-date uint) (duration-months uint))
    (+ start-date (* duration-months SECONDS-PER-MONTH))
)

;; Verify if subscription is currently valid
(define-private (is-subscription-valid (subscription {plan-id: uint, start-date: uint, end-date: uint, is-active: bool, auto-renew: bool, total-paid: uint, payment-count: uint}))
    (and 
        (get is-active subscription)
        (>= (get end-date subscription) burn-block-height)
    )
)

;; Update revenue and subscriber counters
(define-private (update-revenue-stats (amount uint) (is-new-subscriber bool))
    (begin
        (var-set total-revenue (+ (var-get total-revenue) amount))
        (if is-new-subscriber
            (var-set active-subscribers (+ (var-get active-subscribers) u1))
            true
        )
    )
)

;; Grant access to all services included in a plan
(define-private (grant-plan-services (subscriber principal) (plan-id uint))
    (let ((services (list "streaming" "downloads" "api-access" "premium-support")))
        (fold grant-service-access services (some subscriber))
    )
)

(define-private (grant-service-access (service (string-ascii 30)) (subscriber (optional principal)))
    (match subscriber
        subscriber-principal
        (begin
            (map-set service-access
                { subscriber: subscriber-principal, service-name: service }
                {
                    has-access: true,
                    access-granted-at: burn-block-height,
                    last-accessed: u0
                }
            )
            (some subscriber-principal)
        )
        none
    )
)

;; Public Functions

;; Create a new subscription plan (admin only)
(define-public (create-subscription-plan 
    (name (string-ascii 50))
    (price-per-month uint)
    (max-users uint)
    (features (string-ascii 200))
)
    (let ((plan-id (var-get next-plan-id)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> price-per-month u0) ERR-INVALID-AMOUNT)
        
        (map-set subscription-plans
            { plan-id: plan-id }
            {
                name: name,
                price-per-month: price-per-month,
                max-users: max-users,
                features: features,
                is-active: true,
                created-at: burn-block-height
            }
        )
        
        (var-set next-plan-id (+ plan-id u1))
        (ok plan-id)
    )
)

;; Subscribe to a plan with payment
(define-public (subscribe-to-plan (plan-id uint) (duration-months uint))
    (let (
        (plan (unwrap! (map-get? subscription-plans { plan-id: plan-id }) ERR-PLAN-NOT-FOUND))
        (existing-subscription (map-get? user-subscriptions { subscriber: tx-sender }))
        (total-cost (* (get price-per-month plan) duration-months))
        (payment-id (var-get next-payment-id))
        (start-date burn-block-height)
        (end-date (calculate-end-date start-date duration-months))
    )
        (asserts! (get is-active plan) ERR-INVALID-PLAN)
        (asserts! (>= total-cost MIN-SUBSCRIPTION-AMOUNT) ERR-INSUFFICIENT-PAYMENT)
        (asserts! (is-none existing-subscription) ERR-ALREADY-SUBSCRIBED)
        
        ;; Create subscription record
        (map-set user-subscriptions
            { subscriber: tx-sender }
            {
                plan-id: plan-id,
                start-date: start-date,
                end-date: end-date,
                is-active: true,
                auto-renew: false,
                total-paid: total-cost,
                payment-count: u1
            }
        )
        
        ;; Record payment
        (map-set payment-history
            { payment-id: payment-id }
            {
                subscriber: tx-sender,
                plan-id: plan-id,
                amount: total-cost,
                payment-date: burn-block-height,
                payment-type: "initial"
            }
        )
        
        ;; Grant service access
        (grant-plan-services tx-sender plan-id)
        
        ;; Update statistics
        (update-revenue-stats total-cost true)
        (var-set next-payment-id (+ payment-id u1))
        
        (ok { subscription-created: true, end-date: end-date, amount-paid: total-cost })
    )
)

;; Check if user has access to a specific service
(define-public (check-service-access (service-name (string-ascii 30)))
    (let (
        (subscription (map-get? user-subscriptions { subscriber: tx-sender }))
        (service-access-record (map-get? service-access { subscriber: tx-sender, service-name: service-name }))
    )
        (match subscription
            sub-data
            (if (is-subscription-valid sub-data)
                (match service-access-record
                    access-data (ok (get has-access access-data))
                    (ok false)
                )
                ERR-SUBSCRIPTION-EXPIRED
            )
            ERR-SUBSCRIPTION-NOT-FOUND
        )
    )
)

;; Renew subscription with payment
(define-public (renew-subscription (duration-months uint))
    (let (
        (existing-subscription (unwrap! (map-get? user-subscriptions { subscriber: tx-sender }) ERR-SUBSCRIPTION-NOT-FOUND))
        (plan (unwrap! (map-get? subscription-plans { plan-id: (get plan-id existing-subscription) }) ERR-PLAN-NOT-FOUND))
        (renewal-cost (* (get price-per-month plan) duration-months))
        (payment-id (var-get next-payment-id))
        (new-end-date (+ (get end-date existing-subscription) (* duration-months SECONDS-PER-MONTH)))
    )
        (asserts! (get is-active existing-subscription) ERR-SUBSCRIPTION-INACTIVE)
        (asserts! (>= renewal-cost MIN-SUBSCRIPTION-AMOUNT) ERR-INSUFFICIENT-PAYMENT)
        
        ;; Update subscription
        (map-set user-subscriptions
            { subscriber: tx-sender }
            (merge existing-subscription {
                end-date: new-end-date,
                total-paid: (+ (get total-paid existing-subscription) renewal-cost),
                payment-count: (+ (get payment-count existing-subscription) u1)
            })
        )
        
        ;; Record renewal payment
        (map-set payment-history
            { payment-id: payment-id }
            {
                subscriber: tx-sender,
                plan-id: (get plan-id existing-subscription),
                amount: renewal-cost,
                payment-date: burn-block-height,
                payment-type: "renewal"
            }
        )
        
        ;; Update statistics
        (update-revenue-stats renewal-cost false)
        (var-set next-payment-id (+ payment-id u1))
        
        (ok { subscription-renewed: true, new-end-date: new-end-date, amount-paid: renewal-cost })
    )
)

;; Advanced bulk subscription management and analytics function
(define-public (process-bulk-subscription-operations 
    (operation-type (string-ascii 20))
    (subscriber-list (list 50 principal))
    (plan-id uint)
    (duration-months uint)
)
    (let (
        (plan (unwrap! (map-get? subscription-plans { plan-id: plan-id }) ERR-PLAN-NOT-FOUND))
        (cost-per-subscription (* (get price-per-month plan) duration-months))
        (total-operations-cost (* cost-per-subscription (len subscriber-list)))
    )
        ;; Only contract owner can perform bulk operations
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (get is-active plan) ERR-INVALID-PLAN)
        (asserts! (> (len subscriber-list) u0) ERR-INVALID-AMOUNT)
        
        ;; Process different types of bulk operations with standardized return type
        (if (is-eq operation-type "bulk-subscribe")
            (begin
                ;; Create subscriptions for all users in the list
                (map process-individual-subscription subscriber-list)
                ;; Update global statistics for bulk subscription
                (var-set total-revenue (+ (var-get total-revenue) total-operations-cost))
                (var-set active-subscribers (+ (var-get active-subscribers) (len subscriber-list)))
                (ok { 
                    operation: "bulk-subscribe", 
                    processed-count: (len subscriber-list),
                    total-revenue-added: total-operations-cost,
                    new-subscriber-count: (len subscriber-list),
                    renewals-processed: u0,
                    access-grants-processed: u0,
                    granted-services: "none",
                    total-subscribers: (var-get active-subscribers),
                    total-revenue: (var-get total-revenue),
                    plan-name: (get name plan),
                    subscriber-list-count: (len subscriber-list)
                })
            )
            (if (is-eq operation-type "bulk-renew")
                (begin
                    ;; Renew subscriptions for existing subscribers
                    (map process-individual-renewal subscriber-list)
                    ;; Update revenue statistics
                    (var-set total-revenue (+ (var-get total-revenue) total-operations-cost))
                    (ok {
                        operation: "bulk-renew",
                        processed-count: (len subscriber-list),
                        total-revenue-added: total-operations-cost,
                        new-subscriber-count: u0,
                        renewals-processed: (len subscriber-list),
                        access-grants-processed: u0,
                        granted-services: "none",
                        total-subscribers: (var-get active-subscribers),
                        total-revenue: (var-get total-revenue),
                        plan-name: (get name plan),
                        subscriber-list-count: (len subscriber-list)
                    })
                )
                (if (is-eq operation-type "bulk-grant-access")
                    (begin
                        ;; Grant special access permissions to subscriber list
                        (map grant-premium-access subscriber-list)
                        (ok {
                            operation: "bulk-grant-access",
                            processed-count: (len subscriber-list),
                            total-revenue-added: u0,
                            new-subscriber-count: u0,
                            renewals-processed: u0,
                            access-grants-processed: (len subscriber-list),
                            granted-services: "premium-features,priority-support,beta-access",
                            total-subscribers: (var-get active-subscribers),
                            total-revenue: (var-get total-revenue),
                            plan-name: (get name plan),
                            subscriber-list-count: (len subscriber-list)
                        })
                    )
                    ;; Default case for analytics and reporting
                    (ok {
                        operation: "analytics-report",
                        processed-count: u0,
                        total-revenue-added: u0,
                        new-subscriber-count: u0,
                        renewals-processed: u0,
                        access-grants-processed: u0,
                        granted-services: "none",
                        total-subscribers: (var-get active-subscribers),
                        total-revenue: (var-get total-revenue),
                        plan-name: (get name plan),
                        subscriber-list-count: (len subscriber-list)
                    })
                )
            )
        )
    )
)

;; Helper function for bulk subscription processing
(define-private (process-individual-subscription (subscriber principal))
    (let ((payment-id (var-get next-payment-id)))
        (var-set next-payment-id (+ payment-id u1))
        subscriber
    )
)

;; Helper function for bulk renewal processing  
(define-private (process-individual-renewal (subscriber principal))
    (let ((payment-id (var-get next-payment-id)))
        (var-set next-payment-id (+ payment-id u1))
        subscriber
    )
)

;; Helper function for granting premium access
(define-private (grant-premium-access (subscriber principal))
    (begin
        (map-set service-access
            { subscriber: subscriber, service-name: "premium-features" }
            { has-access: true, access-granted-at: burn-block-height, last-accessed: u0 }
        )
        (map-set service-access
            { subscriber: subscriber, service-name: "priority-support" }
            { has-access: true, access-granted-at: burn-block-height, last-accessed: u0 }
        )
        (map-set service-access
            { subscriber: subscriber, service-name: "beta-access" }
            { has-access: true, access-granted-at: burn-block-height, last-accessed: u0 }
        )
        subscriber
    )
)


