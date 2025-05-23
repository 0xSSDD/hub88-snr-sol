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
    signature = get_signature(headers)
    TransactionHandler.bet(server, body, signature)
  end

  @doc """
  Handles a win request, extracting the signature from headers.
  """
  def win(server, body, headers) do
    signature = get_signature(headers)
    TransactionHandler.win(server, body, signature)
  end

  defp get_signature(headers) do
    cond do
      is_map(headers) ->
        Map.get(headers, "X-Hub88-Signature")
      is_list(headers) ->
        headers
        |> Enum.find_value(fn
          {"X-Hub88-Signature", sig} -> sig
          _ -> nil
        end)
      true -> nil
    end
  end
end
