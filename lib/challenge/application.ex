defmodule Challenge.Application do
  @moduledoc """
  The entry point for the Challenge OTP application.

  ## Supervision Tree

  This module defines the root supervisor for the Challenge system. It is responsible for starting and supervising:

    - `Challenge.DataSupervisor`: Supervises core data processes, including the ETS-backed `UserRegistry`.
    - `PartitionSupervisor`: A partitioned supervisor (one per scheduler/core) that manages multiple `DynamicSupervisor` instances.
      Each `DynamicSupervisor` supervises a set of per-user `UserTransactionServer` processes, enabling high concurrency and scalability.

  The supervision strategy is `:one_for_one`, ensuring that if any child process crashes, only that process is restarted.

  ## Design Rationale

  - **Partitioned Supervision:** By partitioning the supervision of user processes, the system can efficiently handle thousands of concurrent users with minimal contention.
  - **Data Isolation:** The `DataSupervisor` ensures that core data structures (ETS tables, registries) are always available and fault-tolerant.

  See the architecture diagram in the README for a visual overview.
  """

  use Application

  @impl true
  @spec start(:normal | :takeover | :failover, any()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    # Supervisor configuration rationale:
    #
    # max_restarts: 50_000
    #   - Allows the system to tolerate a very high number of child process restarts within the time window.
    #   - Necessary for high-concurrency scenarios (e.g., 5,000+ users) where mass process churn or failures may occur.
    #   - Prevents the supervisor from shutting down during stress tests or real-world load spikes.
    #
    # max_seconds: 60
    #   - Sets the time window for restart intensity to 60 seconds.
    #   - Provides a reasonable interval for measuring restart storms without being too aggressive.
    #
    # partitions: System.schedulers_online()
    #   - Creates one DynamicSupervisor per CPU core/scheduler.
    #   - Distributes user processes evenly across all available cores for maximum concurrency and minimal contention.
    #   - This is idiomatic for scalable Elixir/OTP systems and matches BEAM's concurrency model.

    children = [
      Challenge.DataSupervisor,
      {
        PartitionSupervisor,
        child_spec: DynamicSupervisor.child_spec(
          strategy: :one_for_one,
          max_restarts: 50_000,
          max_seconds: 60
        ),
        name: Challenge.PartitionSupervisor,
        partitions: System.schedulers_online()
      }
    ]

    opts = [strategy: :one_for_one, name: Challenge.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
