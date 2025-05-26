# Elixir Developer Solution

**Task:** [Hub88 SNR Challenge](https://github.com/coingaming/hub88-snr)

Thank you for considering my application. To ensure timely delivery and full coverage of the requirements, I proactively implemented both game code validation (using mocks) and signature generation/verification, even though the latter was (much)later clarified as non-critical.

For the signature verification, I leveraged community resources and google/AI to deliver a robust solution without unnecessary delays.

This approach demonstrates my ability to take initiative, solve problems efficiently.

Comprehensive tests are included to illustrate and verify the system's behavior.

**To run the tests:**
```sh
mix test
```

Here is the architecture diagram `architecture.excalidraw.svg`
![Architecture Diagram](architecture.excalidraw.svg)

## Architecture Overview

This project implements the Wallet API for Hub88, using only Elixir/OTP primitives (no external dependencies or databases).

### System Architecture

- **Supervision Tree:**
  The application uses a partitioned supervision tree for maximum concurrency and fault tolerance. Each user's transactions are handled by a dedicated GenServer, supervised by a DynamicSupervisor. Supervisors are partitioned per CPU core for optimal load distribution.

- **Data Management:**
  All user, transaction, and token data is stored in ETS tables, managed by a GenServer. This ensures atomicity, idempotency, and high-throughput access.

- **Fault Tolerance:**
  The system is designed to recover gracefully from process crashes and mass failures. Supervisors are tuned to handle thousands of restarts per minute, and all critical data is persisted in ETS.

### Request Flow

1. **API Entry:**
  Requests enter via the public `Challenge` module, which validates and routes them.
2. **Signature Verification:**
  Every request is cryptographically verified for authenticity.
3. **User Process Routing:**
  The request is routed to the correct per-user GenServer, ensuring all operations for a user are serialized and race-free.
4. **Transaction Processing:**
  The transaction is validated, processed, and persisted atomically.
5. **Response:**
  The result is returned, with all error and success codes matching the Hub88 API spec.

### Supervision & Data Flow Diagram

> See `architecture.excalidraw.svg` for a visual overview of the supervision tree, process flow, and data flow.

*For further details, see inline module and function documentation. The test suite includes integration, concurrency, and fault-tolerance tests that validate the system under real-world conditions.*

> Note: Tests could run slightly (7-8 seconds on my machine)slow, as some of the performance tests in
> `test/integration/fault_tolerance_test.exs` test for high loads, e.g. 5000 users. simultaneusly seeing crashes etc. Redudcing that number will
> speed up tests.


## Performance, Scalability & Concurrency

- **High Throughput by Design:**
  The solution leverages Elixir/OTP primitives like PartitionSupervisor and DynamicSupervisors to efficiently handle thousands of concurrent users and requests.

- **Per-User Isolation:**
  Each user has a dedicated `UserTransactionServer` GenServer, ensuring all their transactions are serialized. This prevents race conditions and double-spending for a single user's balance.

- **Atomicity & Idempotency:**
  Transaction UUIDs are stored in ETS tables using `:ets.insert_new`, guaranteeing that each transaction is processed at most once, even under concurrent or repeated requests.

- **Atomic Balance Updates:**
  All balance changes are performed via a GenServer call to `UserRegistry`, ensuring atomic, race-free updates.

- **Supervisor Tuning for Real-World Load:**
  The supervision tree is explicitly configured (`max_restarts: 50_000`, `max_seconds: 60`, one partition per CPU core) to tolerate mass process churn and rapid restarts, as validated by integration tests simulating thousands of users and failures.

- **No Data Loss on Crashes:**
  All critical data (user balances, transaction history, idempotency keys) is stored in ETS tables managed by supervised GenServers, ensuring persistence and consistency even if user processes or supervisors crash and restart.

- **Proven Scalability:**
  The test suite includes scenarios with 5,000+ users and thousands of concurrent requests, demonstrating the system's ability to scale and recover in a production-like environment.

## Signature Verification

All API requests (e.g., `/transaction/bet`, `/transaction/win`) must include a cryptographic signature in the `X-Hub88-Signature` header, as required by the [Hub88 Wallet API spec](https://docs.hub88.io/developer-docs/operator-api-reference/wallet-api).

This wasnt required, but as I wasnt sure and the recruiter took time to get back to me I went ahead and implemented basic signature verification.

**How it works:**
- The client signs the JSON-encoded request body using **RSA-SHA256** with the private key.
- The signature is base64-encoded and sent in the `X-Hub88-Signature` header.
- The server (this app) base64-decodes the signature and verifies it using the public key and the same JSON encoding.
- Only requests with valid signatures are processed; invalid signatures are rejected with the correct error code.

**Test keys** (`priv/demo_priv.pem`, `priv/demo_pub.pem`) are used for local development and can be regenerated with:
```sh
openssl genpkey -algorithm RSA -out priv/demo_priv.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in priv/demo_priv.pem -out priv/demo_pub.pem
```

This implementation is fully compliant with the assignment and Hub88 requirements, using only Elixir/Erlang standard libraries.

**Note:** These keys are for testing only and are safe to commit to the repository.
