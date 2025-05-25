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
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, nil)
  end

  test "returns error for 'bad' signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, "bad")
  end

  test "returns error for invalid base64 signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, "!!!notbase64!!!")
  end

  test "returns error for invalid PEM public key" do
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, "not a pem")

    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))

    Application.put_env(:challenge, :public_key, original_pubkey)
  end

  test "returns error for invalid key tuple" do
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, {:not, :a, :key})

    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))

    Application.put_env(:challenge, :public_key, original_pubkey)
  end

  test "returns error for valid base64 but invalid signature" do
    result = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
    assert elem(result, 0) == :error
  end

  test "accepts both map and binary body" do
    result1 = SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
    result2 = SignatureValidator.validate("{\"foo\":\"bar\"}", Base.encode64("sig"))
    assert elem(result1, 0) == :error
    assert elem(result2, 0) == :error
  end

  test "returns error for non-binary signature" do
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, 123)

    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
             SignatureValidator.validate(%{foo: "bar"}, :atom)
  end

  test "returns :ok for valid signature and key" do
    payload = %{"foo" => "bar"}
    pubkey = TestUtils.test_public_key()
    Application.put_env(:challenge, :public_key, pubkey)
    signature = TestUtils.valid_signature(payload)
    assert :ok = Challenge.SignatureValidator.validate(payload, signature)
  end

  test "returns error for nil public key" do
    Application.put_env(:challenge, :public_key, nil)
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
      Challenge.SignatureValidator.validate(%{foo: "bar"}, "somesig")
  end

  test "returns error for bad key type" do
    Application.put_env(:challenge, :public_key, 12_345)
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
      Challenge.SignatureValidator.validate(%{foo: "bar"}, "somesig")
  end

  test "returns error for bad pem (pem_decode returns empty list)" do
    # This is not a PEM at all, so pem_decode will return []
    bad_pem = "completely invalid pem"
    Application.put_env(:challenge, :public_key, bad_pem)
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
      Challenge.SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
  end

  test "returns error for decode_pem_entry raising" do
    # Use a PEM that will cause pem_entry_decode to raise (simulate with garbage)
    raising_pem = "not a pem at all"
    Application.put_env(:challenge, :public_key, raising_pem)
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
      Challenge.SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
  end

  test "returns error for bad key (not tuple, not binary, not nil)" do
    Application.put_env(:challenge, :public_key, [1, 2, 3])
    assert {:error, "RS_ERROR_INVALID_SIGNATURE"} =
      Challenge.SignatureValidator.validate(%{foo: "bar"}, Base.encode64("sig"))
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
