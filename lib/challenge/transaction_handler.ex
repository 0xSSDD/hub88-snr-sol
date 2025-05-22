defmodule Challenge.TransactionHandler do
  @moduledoc """
  Handles transaction processing logic.
  """
  alias Challenge.{SignatureValidator, UserManager, UserRegistry, ErrorHandler}

  @doc """
  Process a bet transaction.
  """
  def bet(_server, body) do
    process_transaction(:bet, body)
  end

  @doc """
  Process a win transaction.
  """
  def win(_server, body) do
    process_transaction(:win, body)
  end

  # Common Transaction processing logic
  defp process_transaction(type, body) do
    # Basic validation
    # TODO: Include signature validation
    # :ok <- SignatureValidator.validate_signature(body, signature),
    # TODO what is with syntax?
    with :ok <- validate_required_fields(body, type),
         :ok <- validate_user_id(body),
         :ok <- validate_amount(body) do
      # Get/create user server and process transaction
      user_id = body.user
      user_server = UserManager.get_user_server(user_id)

      case user_server do
        nil ->
          ErrorHandler.error_response(user_id, "RS_ERROR_UNKNOWN", body)

        server ->
          case type do
            :bet -> UserTransactionServer.bet(server, body)
            :win -> UserTransactionServer.win(server, body)
          end
      end
    else
      {:error, error_code} ->
        user_id = Map.get(body, :user, "")
        ErrorHandler.error_response(user_id, error_code, body)
    end
  end

  defp validate_required_fields(body, type) do
    common_fields = [:user, :transaction_uuid, :amount, :request_uuid, :currency, :game_code]

    required_fields =
      case type do
        :win -> [:reference_transaction_uuid | common_fields]
        :bet -> common_fields
      end

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(body, field) or is_nil(Map.get(body, field))
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "RS_ERROR_WRONG_SYNTAX"}
    end
  end

  defp validate_user_id(%{user: user_id}) when is_binary(user_id) do
    if String.length(user_id) >= 3 do
      :ok
    else
      {:error, "RS_ERROR_WRONG_SYNTAX"}
    end
  end

  defp validate_user_id(_) do
    {:error, "RS_ERROR_WRONG_SYNTAX"}
  end

  defp validate_amount(%{amount: amount}) when is_integer(amount) do
    if amount > 0 do
      :ok
    else
      {:error, "RS_ERROR_WRONG_TYPES"}
    end
  end

  defp validate_amount(_) do
    {:error, "RS_ERROR_WRONG_TYPES"}
  end
end
