defmodule Challenge.TransactionHandler do
  @moduledoc """
  Handles all transaction processing logic for the Challenge application.

  This module is responsible for validating, routing, and processing all bet and win
  transactions according to the Hub88 Wallet API specification. It acts as the main
  business logic entrypoint for transaction requests, orchestrating signature validation,
  input validation, idempotency, and error handling.

  ## Responsibilities
    - Validates request signatures using `SignatureValidator`.
    - Validates all required fields and business rules for each transaction.
    - Delegates user and transaction process management to `UserManager`.
    - Ensures idempotency and atomicity by routing requests to the correct per-user
      `UserTransactionServer` process.
    - Handles and formats all error responses using `ErrorHandler`.

  ## Design Notes
    - This module is stateless and purely functional; all stateful operations are delegated
      to GenServers (`UserTransactionServer`, `UserRegistry`).
    - Signature validation is performed before any business logic to ensure security.
    - All transaction processing is serialized per user to prevent race conditions and
      double-spending.

  ## Usage
      Challenge.TransactionHandler.bet(server, body, signature)
      Challenge.TransactionHandler.win(server, body, signature)

  See the README and architecture diagram for a high-level overview.
  """
  alias Challenge.{UserManager, ErrorHandler, UserTransactionServer, SignatureValidator}

  @valid_currencies ~w(
  BSD TTD ZMW BMD USD BYR UGX HKD MGA GIP UZS MKD PTS mLTC EGP AWG
  CZK ILS MZN TND XPF SOS DOP RUB KRW BTN KGS BAM AOA SOC AMS BND RSD FKP PEN
  EOS GHS JPY TRY SBD UAH LTL FJD GNF MDL AFN ZAR MOP TJS BOB JMD QAR IRR SYP
  XXX NAD MYR CUP NOK BGN KPW MNT NZD uETH SGD PYG OMR DZD EUR TMT MMK PTQ ANG
  TZS CRC VES ETB THB ZWD LYD CHF MVR KES CVE LSL KMF SZL KYD BRL AED WST YER
  ALL TRX HUF GTQ uBTC IDR MWK CUC DKK TWD XCD BBD LRD KZT JOD BYN BIF PLN SDG
  VUV SEK BDT HNL BWP VND ISK SLL BHD HTG USDT ADA MUR ERN uLTC LKR COP GEL AUD
  GBP CAD PHP PAB DJF GMD PKR NIO AMD RWF KWD PGK CDF SAR IQD XRP SCR mETH MAD
  GYD INR LBP ARS MXN CLP BNB CNY KHR LAK HRK BZD SSP XOF X5T MRO NPR mBTC
)

  @doc """
  Processes a bet transaction.

  ## Parameters
    - `server`: (unused, for API compatibility)
    - `body`: The transaction request body as a map with atom keys.
    - `signature`: The cryptographic signature to validate.

  ## Returns
    - A response map as specified by the Hub88 Wallet API.

  ## Flow
    1. Validates the signature.
    2. Validates all required fields and business rules.
    3. Routes the request to the correct per-user `UserTransactionServer`.
    4. Returns the result or an error response.
  """
  def bet(_server, body, signature) do
    process_transaction(:bet, body, signature)
  end

  @doc """
  Processes a win transaction.

  ## Parameters
    - `server`: (unused, for API compatibility)
    - `body`: The transaction request body as a map with atom keys.
    - `signature`: The cryptographic signature to validate.

  ## Returns
    - A response map as specified by the Hub88 Wallet API.

  ## Flow
    1. Validates the signature.
    2. Validates all required fields and business rules.
    3. Routes the request to the correct per-user `UserTransactionServer`.
    4. Returns the result or an error response.
  """
  def win(_server, body, signature) do
    process_transaction(:win, body, signature)
  end

  # Common Transaction processing logic
  @doc false
  defp process_transaction(type, body, signature) do
    with :ok <- SignatureValidator.validate(body, signature),
         :ok <- validate_required_fields(body, type),
         :ok <- validate_user_id(body),
         :ok <- validate_amount(body),
         :ok <- validate_token(body, type),
         :ok <- validate_game_code(body),
         :ok <- validate_currency_format(body),
         :ok <- validate_operator_and_sub_partner(body) do
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

  # --- Private Helpers ---

  @doc false
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

    if Enum.empty?(missing_fields), do: :ok, else: {:error, "RS_ERROR_WRONG_SYNTAX"}
  end

  @doc false
  defp validate_user_id(%{user: user_id}) when is_binary(user_id) do
    if String.length(user_id) >= 3, do: :ok, else: {:error, "RS_ERROR_WRONG_SYNTAX"}
  end

  defp validate_user_id(_), do: {:error, "RS_ERROR_WRONG_SYNTAX"}

  @doc false
  defp validate_amount(%{amount: amount}) when is_integer(amount) do
    if amount > 0, do: :ok, else: {:error, "RS_ERROR_WRONG_TYPES"}
  end

  defp validate_amount(_), do: {:error, "RS_ERROR_WRONG_TYPES"}

  @doc false
  # Token is only required for bets, not for wins/rollbacks
  defp validate_token(%{token: token, user: user_id}, :bet) do
    cond do
      is_nil(token) or token == "" ->
        {:error, "RS_ERROR_INVALID_TOKEN"}

      token == "expired" ->
        {:error, "RS_ERROR_TOKEN_EXPIRED"}

      not Challenge.UserRegistry.valid_token?(user_id, token) ->
        {:error, "RS_ERROR_INVALID_TOKEN"}

      true ->
        :ok
    end
  end

  defp validate_token(_body, :win), do: :ok
  defp validate_token(_body, _), do: :ok

  @doc false
  defp validate_game_code(%{game_code: game_code}) do
    if Challenge.UserRegistry.valid_game_code?(game_code),
      do: :ok,
      else: {:error, "RS_ERROR_INVALID_GAME"}
  end

  defp validate_game_code(_), do: {:error, "RS_ERROR_INVALID_GAME"}

  @doc false
  defp validate_currency_format(%{currency: currency}) do
    if is_binary(currency) and currency in @valid_currencies,
      do: :ok,
      else: {:error, "RS_ERROR_WRONG_TYPES"}
  end

  defp validate_currency_format(_), do: {:error, "RS_ERROR_WRONG_TYPES"}

  @doc false
  defp validate_operator_and_sub_partner(%{user: user_id} = body) do
    # Check if operator (user) is disabled
    case Challenge.UserRegistry.get_user(user_id) do
      {:ok, %{disabled: true}} ->
        {:error, "RS_ERROR_USER_DISABLED"}

      {:ok, _user} ->
        # Now check sub_partner_id if present
        validate_sub_partner_id(body)

      {:error, _} ->
        # Let the rest of the pipeline handle unknown user
        :ok
    end
  end

  defp validate_operator_and_sub_partner(_), do: :ok

  @doc false
  defp validate_sub_partner_id(%{sub_partner_id: sub_partner_id})
       when not is_binary(sub_partner_id) or sub_partner_id == "" do
    {:error, "RS_ERROR_WRONG_TYPES"}
  end

  defp validate_sub_partner_id(%{sub_partner_id: sub_partner_id})
       when is_binary(sub_partner_id) do
    cond do
      Challenge.UserRegistry.sub_partner_disabled?(sub_partner_id) ->
        {:error, "RS_ERROR_INVALID_PARTNER"}

      not Challenge.UserRegistry.valid_sub_partner?(sub_partner_id) ->
        {:error, "RS_ERROR_INVALID_PARTNER"}

      true ->
        :ok
    end
  end

  defp validate_sub_partner_id(_), do: :ok
end
