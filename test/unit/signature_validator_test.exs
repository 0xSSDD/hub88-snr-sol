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
    %{foo: "bar"}
    |> SignatureValidator.validate(nil)
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for 'bad' signature" do
    %{foo: "bar"}
    |> SignatureValidator.validate("bad")
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for invalid base64 signature" do
    %{foo: "bar"}
    |> SignatureValidator.validate("!!!notbase64!!!")
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for invalid PEM public key" do
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, "not a pem")

    %{foo: "bar"}
    |> SignatureValidator.validate(Base.encode64("sig"))
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)

    Application.put_env(:challenge, :public_key, original_pubkey)
  end

  test "returns error for invalid key tuple" do
    original_pubkey = Application.get_env(:challenge, :public_key)
    Application.put_env(:challenge, :public_key, {:not, :a, :key})

    %{foo: "bar"}
    |> SignatureValidator.validate(Base.encode64("sig"))
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)

    Application.put_env(:challenge, :public_key, original_pubkey)
  end

  test "returns error for valid base64 but invalid signature" do
    %{foo: "bar"}
    |> SignatureValidator.validate(Base.encode64("sig"))
    |> then(&assert elem(&1, 0) == :error)
  end

  test "accepts both map and binary body" do
    result1 =
      %{foo: "bar"}
      |> SignatureValidator.validate(Base.encode64("sig"))

    result2 =
      "{\"foo\":\"bar\"}"
      |> SignatureValidator.validate(Base.encode64("sig"))

    assert elem(result1, 0) == :error
    assert elem(result2, 0) == :error
  end

  test "returns error for non-binary signature" do
    %{foo: "bar"}
    |> SignatureValidator.validate(123)
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)

    %{foo: "bar"}
    |> SignatureValidator.validate(:atom)
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns :ok for valid signature and key" do
    payload = %{"foo" => "bar"}
    pubkey = TestHelper.test_public_key()
    Application.put_env(:challenge, :public_key, pubkey)
    signature = TestHelper.valid_signature(payload)

    payload
    |> SignatureValidator.validate(signature)
    |> then(&assert &1 == :ok)
  end

  test "returns error for nil public key" do
    Application.put_env(:challenge, :public_key, nil)

    %{foo: "bar"}
    |> SignatureValidator.validate("somesig")
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for bad key type" do
    Application.put_env(:challenge, :public_key, 12_345)

    %{foo: "bar"}
    |> SignatureValidator.validate("somesig")
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for bad pem (pem_decode returns empty list)" do
    bad_pem = "completely invalid pem"
    Application.put_env(:challenge, :public_key, bad_pem)

    %{foo: "bar"}
    |> SignatureValidator.validate(Base.encode64("sig"))
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for decode_pem_entry raising" do
    raising_pem = "not a pem at all"
    Application.put_env(:challenge, :public_key, raising_pem)

    %{foo: "bar"}
    |> SignatureValidator.validate(Base.encode64("sig"))
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "returns error for bad key (not tuple, not binary, not nil)" do
    Application.put_env(:challenge, :public_key, [1, 2, 3])

    %{foo: "bar"}
    |> SignatureValidator.validate(Base.encode64("sig"))
    |> then(&assert {:error, "RS_ERROR_INVALID_SIGNATURE"} = &1)
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
