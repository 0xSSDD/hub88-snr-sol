defmodule Challenge.UserManager do
  @moduledoc """
    Manages user creation and UserTransactionServer processes.
  """
  alias Challenge.UserRegistry

  @doc """
  Creates users with default balance and currency.
  Ignores empty strings and existing users.
  """
  def create_users(_server, users) do
    users
    |> Enum.filter(&(is_binary(&1) and String.length(&1) > 0))
    |> Enum.each(&UserRegistry.create_user/1)

    # TODO: maybe this should be {:ok, "Users created"}
    :ok
  end

  @doc """
  Gets or creates a UserTransactionServer for a user_id.
  """
  def get_user_server(user_id) do
    # First try to find existing process
    case Registry.lookup(Challenge.UserRegistry, user_id) do
      [{pid, _}] ->
        pid

      [] ->
        # calculate parition
        partition =
          :erlang.phash2(
            user_id,
            PartitionSupervisor.partitions(Challenge.PartitionSupervisor)
          )

        # Get the dynamic supervisor for this partition
        dynamic_supervisor =
          PartitionSupervisor.partition(Challenge.PartitionSupervisor, partition)

        # Start child under the selected partition's dynamic supervisor
        case DynamicSupervisor.start_child(
               dynamic_supervisor,
               {Challenge.UserTransactionServer, user_id}
             ) do
          {:ok, pid} ->
            pid

          {:error, {:already_started, pid}} ->
            pid

          # Handle race condition where process was started between our lookup and start_child
          _ ->
            case Registry.lookup(Challenge.UserRegistry, user_id) do
              [{pid, _}] -> pid
              # should never happen
              [] -> nil
            end
        end
    end
  end
end
