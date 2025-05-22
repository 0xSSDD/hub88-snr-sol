defmodule Challenge.DataSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
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
