defmodule Challenge.UserManager do
  @moduledoc """
  Provides user management utilities for the Challenge application.

  ## Responsibilities
    - Creates users with default balances and currency, ensuring idempotency.
    - Manages the lifecycle of per-user `UserTransactionServer` GenServers.
    - Looks up or starts user transaction processes using the process registry and partitioned supervision tree.

  ## How UserTransactionServer Lookup/Start Works

  When a transaction is received for a user, this module:
    1. Attempts to find the user's `UserTransactionServer` PID in the `Challenge.ProcessRegistry`.
    2. If not found, requests the correct partitioned `DynamicSupervisor` (via `PartitionSupervisor`) to start the process.
    3. Handles race conditions by re-checking the registry if another process started the server concurrently.

  This ensures that each user always has a single, uniquely registered transaction server, and that the system remains highly concurrent and scalable.

  This module is stateless and acts as a utility layer for orchestrating user-related operations.
  """
  alias Challenge.UserRegistry

  @doc """
  Creates users with a default balance and currency.

  Ignores empty strings and users that already exist.

  ## Parameters
    - `server`: (unused, for API compatibility)
    - `users`: List of user IDs (strings).

  ## Returns
    - `:ok`
  """
  def create_users(_server, users) do
    users
    |> Enum.filter(&(is_binary(&1) and String.length(&1) > 0))
    |> Enum.each(&UserRegistry.create_user/1)

    :ok
  end

  @doc """
  Looks up or starts a `UserTransactionServer` GenServer for the given user ID.

  ## Parameters
    - `user_id`: The user ID (string).

  ## Returns
    - The PID of the user's transaction server, or `nil` if unable to start or find one.

  ## Details
    - First attempts to look up the process in the `Challenge.ProcessRegistry`.
    - If not found, starts the process under the correct partitioned `DynamicSupervisor`
      using the `PartitionSupervisor`.
    - Handles race conditions by re-checking the registry if the process was started concurrently.
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
