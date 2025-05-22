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
    # Use the renamed registry
    case Registry.lookup(Challenge.ProcessRegistry, user_id) do
      [{pid, _}] ->
        pid

      [] ->
        # Start the UserTransactionServer under the correct DynamicSupervisor partitioned by user_id,
        # using the PartitionSupervisor defined in application.ex
        case DynamicSupervisor.start_child(
               {:via, PartitionSupervisor, {Challenge.PartitionSupervisor, user_id}},
               {Challenge.UserTransactionServer, user_id}
             ) do
          {:ok, pid} ->
            pid

          {:error, {:already_started, pid}} ->
            pid

          # Handle race condition
          _ ->
            case Registry.lookup(Challenge.ProcessRegistry, user_id) do
              [{pid, _}] -> pid
              [] -> nil
            end
        end
    end
  end
end
