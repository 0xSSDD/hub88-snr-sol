# test/unit/signature_validator_test.exs
defmodule Challenge.SignatureValidatorTest do
  use ExUnit.Case, async: true
  alias Challenge.SignatureValidator

  setup do
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, demo_pub_pem())

    on_exit(fn ->
      Application.put_env(:challenge, :public_key, original_pubkey)
    end)

    :ok
  end

  test "returns error for nil signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, nil)
  end

  test "returns error for 'bad' signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, "bad")
  end

  test "returns error for invalid base64 signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, "!!!notbase64!!!")
  end

  test "returns error for invalid PEM public key" do
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, "not a pem")
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
    Application.put_env(:challenge, :public_key, original_pubkey)
  end

  test "returns error for invalid key tuple" do
    Application.put_env(:challenge, :public_key, {:not, :a, :key})
    # The rescue in validate/2 should catch this
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
  end

  test "returns error for valid base64 but invalid signature" do
    # The signature won't match, so should return error
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
  end

  test "accepts both map and binary body" do
    # Both should fail, but not crash
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate("{\"foo\":\"bar\"}", Base.encode64("sig"))
  end

  defp demo_pub_pem do
    """
    -----BEGIN PUBLIC KEY-----
    MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBALeQwQw6QwQwQwQwQwQwQwQwQwQwQwQw
    QwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQwQw
    QwIDAQAB
    -----END PUBLIC KEY-----
    """
  end
end
