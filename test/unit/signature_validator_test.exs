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
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, {:not, :a, :key})
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
    Application.put_env(:challenge, :public_key, original_pubkey)
  end

  test "returns error for valid base64 but invalid signature" do
    assert SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig")) == {:error, "RS_ERROR_INVALID_SIGNATURE"}
  end

  test "accepts both map and binary body" do
    assert SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig")) == {:error, "RS_ERROR_INVALID_SIGNATURE"}
    assert SignatureValidator.validate("{\"foo\":\"bar\"}", Base.encode64("sig")) == {:error, "RS_ERROR_INVALID_SIGNATURE"}
  end

  test "returns error for non-binary signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, 123)
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = SignatureValidator.validate(%{foo: "bar"}, :atom)
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
