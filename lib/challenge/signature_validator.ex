# lib/challenge/signature_validator.ex
defmodule Challenge.SignatureValidator do
  @moduledoc """
  Handles RSA-SHA256 signature validation for Hub88 requests.

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
          Jason.encode!(body)
        else
          body
        end

      # Decode base64 signature
      case Base.decode64(signature, ignore: :whitespace) do
        {:ok, decoded_signature} ->
          # In a real app, you'd get this from config
          public_key = get_public_key()

          # Verify using RSA-SHA256
          case :public_key.verify(body_binary, :sha256, decoded_signature, parse_public_key(public_key)) do
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
end
