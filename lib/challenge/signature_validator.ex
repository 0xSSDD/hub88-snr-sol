# lib/challenge/signature_validator.ex
defmodule Challenge.SignatureValidator do
  @moduledoc """
  Handles RSA-SHA256 signature validation for Hub88 requests.
  Uses only Elixir standard library - no external dependencies.
  """

  @doc """
  Validates the signature against the request body.
  """
  @spec validate(binary() | map(), binary() | nil) :: :ok | {:error, String.t()}
  def validate(body, signature) when is_binary(signature) and (is_map(body) or is_binary(body)) do
    body_binary = if is_map(body), do: encode_json(body), else: body

    with {:ok, decoded_signature} <- Base.decode64(signature, ignore: :whitespace),
         {:ok, public_key} <- fetch_and_parse_public_key(),
         true <- verify_signature(body_binary, decoded_signature, public_key) do
      :ok
    else
      {:error, _} -> {:error, "RS_ERROR_INVALID_SIGNATURE"}
      _ -> {:error, "RS_ERROR_INVALID_SIGNATURE"}
    end
  end

  def validate(_body, _signature), do: {:error, "RS_ERROR_INVALID_SIGNATURE"}

  defp get_public_key do
    # In a real app, this would come from config
    Application.get_env(:challenge, :public_key)
  end

  defp fetch_and_parse_public_key do
    case get_public_key() do
      nil -> {:error, :no_key}
      pem when is_binary(pem) ->
        case :public_key.pem_decode(pem) do
          [pem_entry] -> decode_pem_entry(pem_entry)
          _ -> {:error, :bad_pem}
        end
      key when is_tuple(key) -> {:ok, key}
      _ -> {:error, :bad_key}
    end
  end

  defp decode_pem_entry(pem_entry) do
    try do
      case :public_key.pem_entry_decode(pem_entry) do
        key when is_tuple(key) -> {:ok, key}
        _ -> {:error, :bad_pem_decode}
      end
    rescue
      _ -> {:error, :bad_pem_decode}
    end
  end

  defp verify_signature(body, sig, key)
       when is_binary(body) and is_binary(sig) and is_tuple(key) do
    try do
      case :public_key.verify(body, :sha256, sig, key) do
        true -> true
        false -> false
      end
    rescue
      _ -> false
    end
  end

  # This is a basic implementation that handles the common cases needed for this challenge
  defp encode_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {k, v} ->
        key_str = if is_atom(k), do: to_string(k), else: k
        "\"#{escape_string(key_str)}\":#{encode_json(v)}"
      end)
      |> Enum.join(",")

    "{#{entries}}"
  end

  defp encode_json(value) when is_list(value) do
    entries =
      value
      |> Enum.map(&encode_json/1)
      |> Enum.join(",")

    "[#{entries}]"
  end

  defp encode_json(value) when is_binary(value) do
    "\"#{escape_string(value)}\""
  end

  defp encode_json(value) when is_integer(value) or is_float(value) do
    to_string(value)
  end

  defp encode_json(true), do: "true"
  defp encode_json(false), do: "false"
  defp encode_json(nil), do: "null"

  defp encode_json(value) when is_atom(value) do
    "\"#{escape_string(to_string(value))}\""
  end

  # Basic string escaping for JSON
  defp escape_string(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
