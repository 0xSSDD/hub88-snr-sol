# defmodule Challenge.UserPartition do
#   @moduledoc """
#   """

#   def child_spec(_args) do
#     %{
#       id: __MODULE__,
#       start: {DynamicSupervisor, :start_link, [[strategy: :one_for_one]]},
#       type: :supervisor
#     }
#   end
# end

# # TODO: Shouldnt this define its children? or does Challenge.Application do that?

defmodule Challenge.PartitionSupervisor do
  @moduledoc """
  Supervises partitions of DynamicSupervisors for user transaction servers.
  """

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {DynamicSupervisor, :start_link, [[strategy: :one_for_one]]},
      type: :supervisor
    }
  end
end
