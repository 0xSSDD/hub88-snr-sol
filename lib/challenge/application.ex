defmodule Challenge.Application do
  use Application

  @impl true
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
