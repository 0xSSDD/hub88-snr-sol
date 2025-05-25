defmodule Challenge.DataSupervisor do
  @moduledoc """
  The `Challenge.DataSupervisor` is responsible for supervising the core data infrastructure
  of the Challenge application.

  ## Responsibilities

    * Starts and supervises the `Registry` used for unique process registration and lookup
      of per-user `UserTransactionServer` GenServers.
    * Starts and supervises the `Challenge.UserRegistry` GenServer, which manages all ETS tables
      for user, transaction, and token data.

  This supervisor ensures that the core data and process registry components are always available
  and automatically restarted if they fail, providing a reliable foundation for the rest of the application.

  ## Supervision Strategy

  Uses the `:one_for_one` strategy: if a child process crashes, only that process is restarted.

  ## Children

    - `Registry`: Provides unique process registration for user transaction servers.
    - `Challenge.UserRegistry`: Manages all ETS tables and atomic data operations.
  """

  use Supervisor

  @doc """
  Starts the `Challenge.DataSupervisor` and its children.

  ## Parameters

    - `init_arg`: An initialization argument (not used).

  ## Returns

    - `{:ok, pid}` on success.
    - `{:error, reason}` on failure.
  """
  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_init_arg) do
    children = [
      # Registry for UserTransactionServer processes
      {Registry, keys: :unique, name: Challenge.ProcessRegistry},

      # ETS table manager
      Challenge.UserRegistry
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
