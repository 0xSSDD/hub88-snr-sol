defmodule Challenge.UserTransactionServer do
  @moduledoc """
  Per-user process to serialize transactions and maintain consistency.
  """
  use GenServer
  alias Challenge.{UserRegistry, ErrorHandler}

  # Client API
  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end

  def bet(server, params) do
    GenServer.call(server, {:bet, params}, 10_000)
  end

  def win(server) do
    GenServer.call(server, :win, 10_000)
  end

  # TODO: what is this?
  defp via_tuple(user_id) do
    {:via, Registry, {Challenge.UserRegistry, user_id}}
  end

  # Server callbacks
  @impl true
  def init(user_id) do
    {:ok, %{user_id: user_id}}
  end

  def handle_call({:win, params}, _from, %{user_id: user_id} = state) do
    result = handle_transaction(:win, user_id, params)
    {:reply, result, state}
  end

  defp handle_transaction(type, user_id, params) do
    transaction_uuid = params.transaction_uuid

    if UserRegistry.transaction_exists?(transaction_uuid) do
      # Transaction already processed - get existing result
      {:ok, tx} = UserRegistry.get_transaction(transaction_uuid)
      {:ok, user} = UserRegistry.get_user(user_id)

      # Return consistent response from original processing
      %{
        user: user_id,
        status: "RS_OK",
        request_uuid: params.request_uuid,
        currency: user.currency,
        balance: user.balance
      }
    else
      # New transaction - process it based on type
      case UserRegistry.get_user(user_id) do
        {:ok, user} ->
          process_new_transaction(type, user_id, user, params)

        {:error, :user_not_found} ->
          ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
      end
    end
  end

  defp process_new_transaction(:bet, user_id, user, params) do
    # Check currency match
    if user.currency != params.currency do
      ErrorHandler.error_response(user_id, "RS_ERROR_WRONG_CURRENCY", params)
    end

    # Debit amount
    # negative for bet
    amount = -params.amount

    case UserRegistry.update_balance(user_id, amount) do
      {:ok, updated_user} ->
        # Store the transaction
        UserRegistry.store_transaction(Map.put(params, :type, :bet))
        # Return success response
        # Return success response
        %{
          user: user_id,
          status: "RS_OK",
          request_uuid: params.request_uuid,
          currency: updated_user.currency,
          balance: updated_user.balance
        }

      {:error, :not_enough_money} ->
        ErrorHandler.error_response(user_id, "RS_ERROR_NOT_ENOUGH_MONEY", params)

      {:error, _} ->
        ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
    end
  end

  defp process_new_transaction(:win, user_id, user, params) do
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
          ErrorHandler.error_response(user_id, "RS_ERROR_WRONG_CURRENCY", params)
        else
          # Credit amount
          case UserRegistry.update_balance(user_id, params.amount) do
            {:ok, updated_user} ->
              # Store transaction
              UserRegistry.store_transaction(Map.put(params, :type, :win))

              # Return success response
              %{
                user: user_id,
                status: "RS_OK",
                request_uuid: params.request_uuid,
                currency: updated_user.currency,
                balance: updated_user.balance
              }

            {:error, _} ->
              ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", params)
          end
        end

      {:error, error_code} ->
        ErrorHandler.error_response(user_id, error_code, params)
    end
  end
end
