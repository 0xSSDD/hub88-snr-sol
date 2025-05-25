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
    children = [
      Challenge.DataSupervisor,
      {
        PartitionSupervisor,
        child_spec: DynamicSupervisor.child_spec(strategy: :one_for_one),
        name: Challenge.PartitionSupervisor,
        partitions: System.schedulers_online()
      }
    ]

    opts = [strategy: :one_for_one, name: Challenge.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
