defmodule Challenge.UserTransactionServer do
  @moduledoc """
  Per-user process to serialize transactions and maintain consistency.

  ## Idempotency and Concurrency

  This server serializes all transactions for a user through a single GenServer process.
  Transaction idempotency is handled atomically using ETS tables as the source of truth.

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
    # Simple state - ETS tables handle transaction tracking
    {:ok, %{user_id: user_id}}
  end

  @impl true
  def handle_call({:win, params}, _from, state) do
    result = handle_transaction(:win, params, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:bet, params}, _from, state) do
    result = handle_transaction(:bet, params, state)
    {:reply, result, state}
  end

  # Main transaction handler with atomic idempotency
  defp handle_transaction(type, params, %{user_id: user_id} = state) do
    transaction_uuid = params.transaction_uuid

    # Increment and get the new count
    current_count = Challenge.UserRegistry.increment_user_limit(user_id)
    limit = Challenge.UserRegistry.get_daily_request_limit()
    if current_count > limit do
      {ErrorHandler.error_response(user_id, "RS_ERROR_LIMIT_REACHED", params), state}
    else
      # Use ETS as single source of truth for processed transactions
      case UserRegistry.get_transaction(transaction_uuid) do
        {:ok, original_tx} ->
          # Transaction already processed
          handle_duplicate_transaction(user_id, params, original_tx)

        {:error, :transaction_not_found} ->
          # New transaction - process it
          process_new_transaction(type, user_id, params)
      end
    end
  end

  defp handle_duplicate_transaction(user_id, params, original_tx) do
    # Check for duplicate with mismatched fields
    if duplicate_transaction_mismatch?(original_tx, params) do
      ErrorHandler.error_response(user_id, "RS_ERROR_DUPLICATE_TRANSACTION", params)
    else
      # Return success with current user balance
      case UserRegistry.get_user(user_id) do
        {:ok, user} ->
          %{
            user: user_id,
            status: "RS_OK",
            request_uuid: params.request_uuid,
            currency: user.currency,
            balance: user.balance
          }

        {:error, :user_not_found} ->
          ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
      end
    end
  end

  defp process_new_transaction(type, user_id, params) do
    case UserRegistry.get_user(user_id) do
      {:ok, %{disabled: true}} ->
        ErrorHandler.error_response(user_id, "RS_ERROR_USER_DISABLED", params)

      {:ok, user} ->
        execute_transaction(type, user_id, user, params)

      {:error, :user_not_found} ->
        ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
    end
  end

  defp execute_transaction(:bet, user_id, user, params) do
    if user.currency != params.currency do
      ErrorHandler.error_response(user_id, "RS_ERROR_WRONG_CURRENCY", params)
    else
      amount = -params.amount

      # Atomic transaction processing with race condition handling
      case process_transaction_atomically(user_id, params, amount) do
        {:ok, updated_user} ->
          %{
            user: user_id,
            status: "RS_OK",
            request_uuid: params.request_uuid,
            currency: updated_user.currency,
            balance: updated_user.balance
          }

        {:error, :not_enough_money} ->
          # Get current balance for error response
          {:ok, current_user} = UserRegistry.get_user(user_id)

          ErrorHandler.error_response(user_id, "RS_ERROR_NOT_ENOUGH_MONEY", params,
            balance: current_user.balance
          )

        {:error, :duplicate_transaction} ->
          # Another process stored this transaction while we were processing
          # Get the stored transaction and return consistent response
          {:ok, stored_tx} = UserRegistry.get_transaction(params.transaction_uuid)
          handle_duplicate_transaction(user_id, params, stored_tx)

        {:error, _} ->
          ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
      end
    end
  end

  defp execute_transaction(:win, user_id, user, params) do
    # Check reference transaction if provided
    case validate_reference_transaction(params) do
      :ok ->
        if user.currency != params.currency do
          ErrorHandler.error_response(user_id, "RS_ERROR_WRONG_CURRENCY", params)
        else
          # Credit amount
          case process_transaction_atomically(user_id, params, params.amount) do
            {:ok, updated_user} ->
              %{
                user: user_id,
                status: "RS_OK",
                request_uuid: params.request_uuid,
                currency: updated_user.currency,
                balance: updated_user.balance
              }

            {:error, :duplicate_transaction} ->
              # Handle race condition
              {:ok, stored_tx} = UserRegistry.get_transaction(params.transaction_uuid)
              handle_duplicate_transaction(user_id, params, stored_tx)

            {:error, _} ->
              ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
          end
        end

      {:error, error_code} ->
        ErrorHandler.error_response(user_id, error_code, params)
    end
  end

  # Atomic transaction processing that handles race conditions
  defp process_transaction_atomically(user_id, params, amount) do
    # First, try to store the transaction atomically
    case UserRegistry.store_transaction(
           Map.put(params, :type, if(amount < 0, do: :bet, else: :win))
         ) do
      {:ok, :new_transaction} ->
        # We successfully stored the transaction first, now update balance
        case UserRegistry.update_balance(user_id, amount) do
          {:ok, updated_user} ->
            {:ok, updated_user}

          {:error, reason} ->
            # Balance update failed, but transaction is already stored
            # This is a rare edge case - log and return error
            {:error, reason}
        end

      {:ok, :duplicate_transaction} ->
        # Another process stored this transaction while we were processing
        {:error, :duplicate_transaction}
    end
  end

  defp validate_reference_transaction(params) do
    ref_tx_uuid = Map.get(params, :reference_transaction_uuid)

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
end
