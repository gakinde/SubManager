# SubManager

---

## Table of Contents
- Description
- Features
- Error Codes
- Constants
- Data Maps and Variables
- Functions
  - Private Functions
  - Public Functions
- Usage
- Contributing
- License
- Contact

---

## Description
This smart contract, **SubManager**, provides a comprehensive decentralized solution for managing SaaS and streaming service subscriptions on the Stacks blockchain. It handles subscription plan creation, user subscriptions, payment processing, access control, and automated renewals. The contract aims to streamline subscription services by leveraging the transparency and immutability of blockchain technology.

---

## Features
- **Subscription Plan Management**: Create and manage different subscription tiers with distinct pricing, user limits, and features.
- **User Subscriptions**: Users can subscribe to available plans for specified durations.
- **Payment Processing**: Integrates payment handling for initial subscriptions and renewals.
- **Access Control**: Granular control over service access based on active subscriptions.
- **Automated Renewals**: Supports subscription renewals to extend service access.
- **Payment History**: Maintains a detailed record of all subscription payments for auditing and analytics.
- **Revenue and Subscriber Tracking**: Global counters for total revenue and active subscribers.
- **Bulk Operations**: Provides administrative functions for bulk subscription, renewal, and access granting operations.

---

## Error Codes
| Code | Name                       | Description                                  |
| :--- | :------------------------- | :------------------------------------------- |
| `u100` | `ERR-NOT-AUTHORIZED`       | Caller is not the contract owner.            |
| `u101` | `ERR-INVALID-PLAN`         | The specified plan is invalid or inactive.   |
| `u102` | `ERR-SUBSCRIPTION-NOT-FOUND`| No active subscription found for the user.   |
| `u103` | `ERR-SUBSCRIPTION-EXPIRED` | The user's subscription has expired.         |
| `u104` | `ERR-INSUFFICIENT-PAYMENT` | Payment amount is less than the minimum required or calculated cost.|
| `u105` | `ERR-PLAN-NOT-FOUND`       | The specified plan ID does not exist.        |
| `u106` | `ERR-ALREADY-SUBSCRIBED`   | User already has an active subscription.     |
| `u107` | `ERR-INVALID-AMOUNT`       | An invalid amount was provided (e.g., zero price).|
| `u108` | `ERR-SUBSCRIPTION-INACTIVE`| The subscription is not active and cannot be renewed.|

---

## Constants
- `CONTRACT-OWNER`: Defines the deployer of the contract as the owner with administrative privileges.
- `SECONDS-PER-DAY`: `u86400` (Number of seconds in a day).
- `SECONDS-PER-MONTH`: `u2592000` (Approximate number of seconds in a 30-day month).
- `MIN-SUBSCRIPTION-AMOUNT`: `u1000` (Minimum acceptable payment amount for a subscription).

---

## Data Maps and Variables

### Data Maps
- `subscription-plans`: Stores details of each subscription plan, including `name`, `price-per-month`, `max-users`, `features`, `is-active`, and `created-at`.
- `user-subscriptions`: Tracks individual user subscriptions, including `plan-id`, `start-date`, `end-date`, `is-active`, `auto-renew`, `total-paid`, and `payment-count`.
- `service-access`: Manages fine-grained access permissions for users to specific services, recording `has-access`, `access-granted-at`, and `last-accessed`.
- `payment-history`: Logs all payments made, detailing `subscriber`, `plan-id`, `amount`, `payment-date`, and `payment-type`.

### Variables
- `next-plan-id`: A counter for generating unique `plan-id`s.
- `next-payment-id`: A counter for generating unique `payment-id`s.
- `total-revenue`: Accumulates the total revenue generated from all subscriptions.
- `active-subscribers`: Counts the total number of currently active subscribers.

---

## Functions

### Private Functions
These functions are internal helpers and cannot be called directly by external users.
- `(calculate-end-date (start-date uint) (duration-months uint))`: Calculates the subscription end date based on a start date and duration in months.
- `(is-subscription-valid (subscription {plan-id: uint, start-date: uint, end-date: uint, is-active: bool, auto-renew: bool, total-paid: uint, payment-count: uint}))`: Checks if a given subscription record is currently valid and active.
- `(update-revenue-stats (amount uint) (is-new-subscriber bool))`: Updates the `total-revenue` and `active-subscribers` global variables.
- `(grant-plan-services (subscriber principal) (plan-id uint))`: Grants a subscriber access to a predefined list of services associated with their plan.
- `(grant-service-access (service (string-ascii 30)) (subscriber (optional principal)))`: Helper to set service access for a specific service and subscriber.
- `(process-individual-subscription (subscriber principal))`: Helper for `process-bulk-subscription-operations` to handle individual subscription creation.
- `(process-individual-renewal (subscriber principal))`: Helper for `process-bulk-subscription-operations` to handle individual subscription renewals.
- `(grant-premium-access (subscriber principal))`: Helper for `process-bulk-subscription-operations` to grant specific premium access features.

### Public Functions
These functions can be called by external users to interact with the contract.

- `(create-subscription-plan (name (string-ascii 50)) (price-per-month uint) (max-users uint) (features (string-ascii 200)))`:
  - **Description**: Allows the `CONTRACT-OWNER` to create a new subscription plan.
  - **Parameters**:
    - `name`: Name of the plan (e.g., "Basic", "Premium").
    - `price-per-month`: Monthly price of the plan.
    - `max-users`: Maximum number of users allowed per subscription under this plan.
    - `features`: A description of features included in the plan.
  - **Returns**: `(ok uint)` with the `plan-id` on success, or an error.

- `(subscribe-to-plan (plan-id uint) (duration-months uint))`:
  - **Description**: Allows any user to subscribe to an available plan.
  - **Parameters**:
    - `plan-id`: The ID of the subscription plan.
    - `duration-months`: The desired subscription duration in months.
  - **Returns**: `(ok { subscription-created: bool, end-date: uint, amount-paid: uint })` on success, or an error.

- `(check-service-access (service-name (string-ascii 30)))`:
  - **Description**: Checks if the calling user has access to a specific service.
  - **Parameters**:
    - `service-name`: The name of the service to check access for (e.g., "streaming", "downloads").
  - **Returns**: `(ok bool)` indicating `true` for access or `false` for no access, or an error if no subscription is found or it's expired.

- `(renew-subscription (duration-months uint))`:
  - **Description**: Allows an existing subscriber to renew their subscription for an additional period.
  - **Parameters**:
    - `duration-months`: The duration in months to extend the subscription.
  - **Returns**: `(ok { subscription-renewed: bool, new-end-date: uint, amount-paid: uint })` on success, or an error.

- `(process-bulk-subscription-operations (operation-type (string-ascii 20)) (subscriber-list (list 50 principal)) (plan-id uint) (duration-months uint))`:
  - **Description**: A powerful administrative function for the `CONTRACT-OWNER` to perform bulk operations like subscribing, renewing, or granting special access to a list of subscribers.
  - **Parameters**:
    - `operation-type`: Specifies the type of operation ("bulk-subscribe", "bulk-renew", "bulk-grant-access", "analytics-report").
    - `subscriber-list`: A list of principals (user addresses) to apply the operation to. Max 50.
    - `plan-id`: The ID of the relevant plan for the operation.
    - `duration-months`: The duration in months relevant for subscription or renewal operations.
  - **Returns**: `(ok { ... })` with details about the processed operations, or an error.

---

## Usage
To interact with this contract, you will need a Stacks wallet and some STX tokens.

---

### Deployment
Deploy the contract to the Stacks blockchain. Once deployed, the deployer will automatically be set as the `CONTRACT-OWNER`.

---

### Creating Plans
Only the contract owner can create subscription plans:

(contract-call? 'SP123...your-contract-address.sub-manager create-subscription-plan "Premium Plan" u5000 u5 "HD Streaming, Offline Downloads")

---

### Subscribing to a Plan
Any user can subscribe:
(contract-call? 'SP123...your-contract-address.sub-manager subscribe-to-plan u1 u12)

(where `u1` is `plan-id` and `u12` is `duration-months`)

---

### Checking Service Access
Users can check their access:
(contract-call? 'SP123...your-contract-address.sub-manager check-service-access "streaming")

---

### Renewing a Subscription
Existing subscribers can renew:
(contract-call? 'SP123...your-contract-address.sub-manager renew-subscription u6)

(where `u6` is `duration-months`)

---

### Bulk Operations (Contract Owner Only)
(contract-call? 'SP123...your-contract-address.sub-manager process-bulk-subscription-operations
"bulk-subscribe"
(list 'SPXYZ...user1 'SPABC...user2)
u1
u3
)

---

## Contributing
Contributions are welcome! If you have suggestions for improvements or find any issues, please open an issue or submit a pull request on the GitHub repository.

---

## License
This project is licensed under the MIT License - see the LICENSE.md file for details.

---

## Contact
For questions or inquiries, please open an issue in the GitHub repository.
