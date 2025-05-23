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
  def validate(_body, nil), do: {:error, "RS_ERROR_INVALID_SIGNATURE"}
  def validate(_body, "bad"), do: {:error, "RS_ERROR_INVALID_SIGNATURE"}

  def validate(body, signature) when is_binary(signature) do
    try do
      # Convert body to JSON binary if it's a map
      body_binary =
        if is_map(body) do
          encode_json(body)
        else
          body
        end

      # Decode base64 signature
      case Base.decode64(signature, ignore: :whitespace) do
        {:ok, decoded_signature} ->
          # In a real app, you'd get this from config
          public_key = get_public_key()

          # Verify using RSA-SHA256
          case :public_key.verify(
                 body_binary,
                 :sha256,
                 decoded_signature,
                 parse_public_key(public_key)
               ) do
            true -> :ok
            false -> {:error, "RS_ERROR_INVALID_SIGNATURE"}
          end

        :error ->
          {:error, "RS_ERROR_INVALID_SIGNATURE"}
      end
    rescue
      _ -> {:error, "RS_ERROR_INVALID_SIGNATURE"}
    end
  end

  defp get_public_key do
    # In a real app, this would come from config
    Application.get_env(:challenge, :public_key)
  end

  defp parse_public_key(pem_string) when is_binary(pem_string) do
    [pem_entry] = :public_key.pem_decode(pem_string)
    :public_key.pem_entry_decode(pem_entry)
  end

  defp parse_public_key(key) when is_tuple(key), do: key

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
