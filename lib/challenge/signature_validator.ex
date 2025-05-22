# # lib/challenge/signature_validator.ex
# defmodule Challenge.SignatureValidator do
#   @moduledoc """
#   Handles RSA-SHA256 signature validation for Hub88 requests.

#   """

#   @doc """
#   Validates the signature against the request body.
#   For now, returns :ok (signature validation can be implemented when public keys are available).
#   """
#   def validate(body, signature \\ nil) do
#     # TODO: Implement actual signature validation when Hub88 provides public keys
#     # For the challenge, we'll skip signature validation since we don't have the keys
#     :ok
#   end

#   @doc """
#   Full signature validation implementation (for when public keys are available).
#   """
#   def validate_signature(body, encoded_signature, public_key) do
#     try do
#       # Convert body to JSON binary if it's a map
#       body_binary =
#         if is_map(body) do
#           # Would need Jason dependency
#           Jason.encode!(body)
#         else
#           body
#         end

#       # Decode base64 signature
#       case Base.decode64(encoded_signature, ignore: :whitespace) do
#         {:ok, signature} ->
#           # Verify using RSA-SHA256
#           case :public_key.verify(body_binary, :sha256, signature, parse_public_key(public_key)) do
#             true -> :ok
#             false -> {:error, "RS_ERROR_INVALID_SIGNATURE"}
#           end

#         :error ->
#           {:error, "RS_ERROR_INVALID_SIGNATURE"}
#       end
#     rescue
#       _ -> {:error, "RS_ERROR_INVALID_SIGNATURE"}
#     end
#   end

#   # Parse PEM public key (similar to HmCrypto library)
#   defp parse_public_key(pem_string) when is_binary(pem_string) do
#     [pem_entry] = :public_key.pem_decode(pem_string)
#     :public_key.pem_entry_decode(pem_entry)
#   end

#   defp parse_public_key(key) when is_tuple(key), do: key
# end
