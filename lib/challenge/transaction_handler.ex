defmodule Challenge.TransactionHandler do
  @moduledoc """
  Handles transaction processing logic.

  NOTE: In a real HTTP API, the signature would be extracted from the
  "X-Hub88-Signature" header (e.g., via Plug, Phoenix, or Cowboy).
  Here, for pure OTP and testability, we require the signature as a
  separate argument to the handler functions.
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

  @valid_game_codes ["ont_blackjackclassic"]

  @doc """
  Process a bet transaction.
  """
  def bet(_server, body, signature) do
    process_transaction(:bet, body, signature)
  end

  @doc """
  Process a win transaction.
  """
  def win(_server, body, signature) do
    process_transaction(:win, body, signature)
  end

  # Common Transaction processing logic
  # TODO: Ensure: NB!
  # Token validity most not be validated in case of wins and rollbacks,
  # since they might come after the bet has been played.

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

  defp validate_user_id(%{user: user_id}) when is_binary(user_id) do
    if String.length(user_id) >= 3, do: :ok, else: {:error, "RS_ERROR_WRONG_SYNTAX"}
  end

  defp validate_user_id(_), do: {:error, "RS_ERROR_WRONG_SYNTAX"}

  defp validate_amount(%{amount: amount}) when is_integer(amount) do
    if amount > 0, do: :ok, else: {:error, "RS_ERROR_WRONG_TYPES"}
  end

  defp validate_amount(_), do: {:error, "RS_ERROR_WRONG_TYPES"}

  # Token is only required for bets, not for wins/rollbacks
  defp validate_token(%{token: token}, :bet) do
    cond do
      is_nil(token) or token == "" -> {:error, "RS_ERROR_INVALID_TOKEN"}
      token == "expired" -> {:error, "RS_ERROR_TOKEN_EXPIRED"}
      true -> :ok
    end
  end

  defp validate_token(_body, :win), do: :ok
  defp validate_token(_body, _), do: :ok

  defp validate_game_code(%{game_code: game_code}) do
    if game_code in @valid_game_codes, do: :ok, else: {:error, "RS_ERROR_INVALID_GAME"}
  end

  defp validate_game_code(_), do: {:error, "RS_ERROR_INVALID_GAME"}

  defp validate_currency_format(%{currency: currency}) do
    if is_binary(currency) and currency in @valid_currencies,
      do: :ok,
      else: {:error, "RS_ERROR_WRONG_TYPES"}
  end

  defp validate_currency_format(_), do: {:error, "RS_ERROR_WRONG_TYPES"}

  defp validate_operator_and_sub_partner(%{user: user_id} = body) do
    # Check if operator (user) is disabled
    case Challenge.UserRegistry.get_user(user_id) do
      {:ok, %{disabled: true}} ->
        {:error, "RS_ERROR_INVALID_PARTNER"}

      {:ok, _user} ->
        # Now check sub_partner_id if present
        validate_sub_partner_id(body)

      {:error, _} ->
        :ok  # Let the rest of the pipeline handle unknown user
    end
  end

  defp validate_operator_and_sub_partner(_), do: :ok

  defp validate_sub_partner_id(%{sub_partner_id: sub_partner_id}) when is_binary(sub_partner_id) do
    cond do
      Challenge.UserRegistry.sub_partner_disabled?(sub_partner_id) ->
        {:error, "RS_ERROR_INVALID_PARTNER"}
      not Challenge.UserRegistry.valid_sub_partner?(sub_partner_id) ->
        {:error, "RS_ERROR_INVALID_PARTNER"}
      true ->
        :ok
    end
  end

  defp validate_sub_partner_id(_), do: :ok  # If not present, treat as OK
end

# TODO are there any checks here that belong in user_tx_server
