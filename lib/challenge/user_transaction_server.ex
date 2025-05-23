defmodule Challenge.UserTransactionServer do
  @moduledoc """
  Per-user process to serialize transactions and maintain consistency.

  ## Idempotency and Concurrency

  This server maintains a per-user set of processed transaction UUIDs in its state.
  All transaction requests (bet/win) are serialized through the GenServer, ensuring
  that only one transaction with a given UUID is processed, even under high concurrency.

  This approach guarantees:
    - Idempotency: repeated requests with the same UUID return the same result.
    - Atomicity: only one transaction with a given UUID is ever processed for a user.
    - High throughput: each user has their own process, so requests for different users do not block each other.

  This is the idiomatic OTP approach for high-availability, high-throughput systems.
  """
  use GenServer
  alias Challenge.{UserRegistry, ErrorHandler}

  # Client API
  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end

  def bet(server, params) do
    GenServer.call(server, {:bet, params})
  end

  def win(server, params) do
    GenServer.call(server, {:win, params})
  end

  defp via_tuple(user_id) do
    {:via, Registry, {Challenge.ProcessRegistry, user_id}}
  end

  # Server callbacks
  @impl true
  def init(user_id) do
    # Add processed_uuids to state for idempotency
    {:ok, %{user_id: user_id, processed_uuids: MapSet.new()}}
  end

  @impl true
  def handle_call({:win, params}, _from, state) do
    {result, new_state} = handle_transaction(:win, params, state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:bet, params}, _from, state) do
    {result, new_state} = handle_transaction(:bet, params, state)
    {:reply, result, new_state}
  end

  # Main transaction handler with idempotency
  defp handle_transaction(type, params, %{user_id: user_id, processed_uuids: processed_uuids} = state) do
    transaction_uuid = params.transaction_uuid

    # Check if we've already processed this UUID
    if MapSet.member?(processed_uuids, transaction_uuid) do
      # Transaction already processed - get existing result
      {:ok, original_tx} = UserRegistry.get_transaction(transaction_uuid)
      {:ok, user} = UserRegistry.get_user(user_id)

      # Check for duplicate with mismatched fields
      if duplicate_transaction_mismatch?(original_tx, params) do
        {ErrorHandler.error_response(user_id, "RS_ERROR_DUPLICATE_TRANSACTION", params), state}
      else
        {
          %{
            user: user_id,
            status: "RS_OK",
            request_uuid: params.request_uuid,
            currency: user.currency,
            balance: user.balance
          },
          state
        }
      end
    else
      # New transaction - process it based on type
      case UserRegistry.get_user(user_id) do
        {:ok, %{disabled: true}} ->
          {ErrorHandler.error_response(user_id, "RS_ERROR_USER_DISABLED", params), state}

        {:ok, user} ->
          # FIXED: Remove the stale balance check - let update_balance handle it atomically
          process_new_transaction(type, user_id, user, params, state)

        {:error, :user_not_found} ->
          {ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params), state}
      end
    end
  end

  defp duplicate_transaction_mismatch?(original, incoming) do
    # Compare all relevant fields
    Enum.any?(
      [:reference_transaction_uuid, :amount, :currency, :round, :user, :game_code],
      fn field ->
        Map.get(original, field) != Map.get(incoming, field)
      end
    )
  end

  defp process_new_transaction(:bet, user_id, user, params, state) do
    if user.currency != params.currency do
      {ErrorHandler.error_response(user_id, "RS_ERROR_WRONG_CURRENCY", params), state}
    else
      amount = -params.amount
      # FIXED: The insufficient funds check now happens atomically in update_balance
      case UserRegistry.update_balance(user_id, amount) do
        {:ok, updated_user} ->
          UserRegistry.store_transaction(Map.put(params, :type, :bet))
          new_state = update_in(state.processed_uuids, &MapSet.put(&1, params.transaction_uuid))

          {
            %{
              user: user_id,
              status: "RS_OK",
              request_uuid: params.request_uuid,
              currency: updated_user.currency,
              balance: updated_user.balance
            },
            new_state
          }

        {:error, :not_enough_money} ->
          # Get current balance for error response
          {:ok, current_user} = UserRegistry.get_user(user_id)
          {ErrorHandler.error_response(user_id, "RS_ERROR_NOT_ENOUGH_MONEY", params, balance: current_user.balance), state}

        {:error, _} ->
          {ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params), state}
      end
    end
  end

  defp process_new_transaction(:win, user_id, user, params, state) do
    # Check reference transaction if provided
    ref_tx_uuid = Map.get(params, :reference_transaction_uuid)

    ref_check =
      if ref_tx_uuid do
        case UserRegistry.get_transaction(ref_tx_uuid) do
          {:ok, _} ->
            :ok

          {:error, :transaction_not_found} ->
            {:error, "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"}
        end
      else
        :ok
      end

    case ref_check do
      :ok ->
        if user.currency != params.currency do
          {ErrorHandler.error_response(user_id, "RS_ERROR_WRONG_CURRENCY", params), state}
        else
          # Credit amount
          case UserRegistry.update_balance(user_id, params.amount) do
            {:ok, updated_user} ->
              # Store transaction
              UserRegistry.store_transaction(Map.put(params, :type, :win))

              new_state =
                update_in(state.processed_uuids, &MapSet.put(&1, params.transaction_uuid))

              {
                %{
                  user: user_id,
                  status: "RS_OK",
                  request_uuid: params.request_uuid,
                  currency: updated_user.currency,
                  balance: updated_user.balance
                },
                new_state
              }

            {:error, _} ->
              {ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params), state}
          end
        end

      {:error, error_code} ->
        {ErrorHandler.error_response(user_id, error_code, params), state}
    end
  end
end
