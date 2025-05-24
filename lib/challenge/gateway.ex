defmodule Challenge.Gateway do
  @moduledoc """
  Mimics a Cowboy/Plug/Phoenix HTTP adapter.
  Handles signature extraction from headers and delegates to TransactionHandler.
  """

  alias Challenge.TransactionHandler

  @doc """
  Handles a bet request, extracting the signature from headers.
  """
  def bet(server, body, headers) do
    signature = extract_signature(headers)
    TransactionHandler.bet(server, body, signature)
  end

  @doc """
  Handles a win request, extracting the signature from headers.
  """
  def win(server, body, headers) do
    signature = extract_signature(headers)
    TransactionHandler.win(server, body, signature)
  end

  @doc """
  Extracts the x-hub88-signature from headers (map or list), case-insensitive.
  Returns nil if not found.
  """
  def extract_signature(headers) do
    cond do
      is_map(headers) ->
        Map.get(headers, "x-hub88-signature") || Map.get(headers, "X-Hub88-Signature")

      is_list(headers) ->
        headers
        |> Enum.find_value(fn
          {"x-hub88-signature", sig} -> sig
          {"X-Hub88-Signature", sig} -> sig
          _ -> nil
        end)

      true ->
        nil
    end
  end
end
