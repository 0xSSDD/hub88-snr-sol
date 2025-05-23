ExUnit.start()
Application.ensure_all_started(:public_key)
Application.put_env(:challenge, :public_key, File.read!("priv/demo_pub.pem"))

defmodule TestUtils do
  @moduledoc """
  Test utilities for the Challenge application.
  Includes helpers for generating test data and cryptographic signatures.
  """

  # Load test keys from priv directory
  @test_private_key File.read!("priv/demo_priv.pem")
  @test_public_key File.read!("priv/demo_pub.pem")

  @doc """
  Generates a random 16-byte UUID string in standard 8-4-4-4-12 format.
  """
  def random_uuid do
    <<a1::32, a2::16, a3::16, a4::16, a5::48>> = :crypto.strong_rand_bytes(16)

    Enum.join(
      [
        Base.encode16(<<a1::32>>, case: :lower),
        Base.encode16(<<a2::16>>, case: :lower),
        Base.encode16(<<a3::16>>, case: :lower),
        Base.encode16(<<a4::16>>, case: :lower),
        Base.encode16(<<a5::48>>, case: :lower)
      ],
      "-"
    )
  end

  @doc """
  Returns a valid bet params map for a given user.
    user: user_id
    transaction_uuid: random_uuid()
    supplier_transaction_id: random_uuid()
    token: random_uuid()
    supplier_user: random_uuid()
    round_closed: false
    round: "round_#{:rand.uniform(1000)}"
    reward_uuid: random_uuid()
    request_uuid: random_uuid()
    is_free: false
    is_aggregated: false
    game_code: "game_123"
    currency: "USD"
    bet: "center"
    amount: 5
  """
  def bet_params(user, overrides \\ %{}) do
    Map.merge(
      %{
        user: user,
        transaction_uuid: random_uuid(),
        supplier_transaction_id: random_uuid(),
        token: random_uuid(),
        supplier_user: random_uuid(),
        round_closed: false,
        round: "round_#{:rand.uniform(1000)}",
        reward_uuid: random_uuid(),
        request_uuid: random_uuid(),
        is_free: false,
        is_aggregated: false,
        game_code: "ont_blackjackclassic",
        currency: "USD",
        bet: "center",
        amount: 5,
        meta: nil
      },
      overrides
    )
  end

  @doc """
  Returns a valid win params map for a given user and reference transaction.
  """
  def win_params(user, ref_tx_uuid, overrides \\ %{}) do
    Map.merge(bet_params(user, overrides), %{
      reference_transaction_uuid: ref_tx_uuid
    })
  end

  @doc """
  Generates a valid RSA-SHA256 signature for the given payload.
  Uses the test private key to sign the JSON-encoded payload.
  """
  def valid_signature(payload \\ %{test: "data"}) do
    dbg(payload)
    json = Jason.encode!(payload)
    IO.inspect(json, label: "JSON to sign")

    json
    |> sign_payload()
    |> Base.encode64()
  end

  @doc """
  Returns an invalid signature (for testing error cases).
  """
  def invalid_signature, do: "bad"

  @doc """
  Returns a map with both the payload and its valid signature.
  Useful for testing the complete request flow.
  """
  def signed_payload(payload) do
    signature = valid_signature(payload)
    {payload, signature}
  end

  # Private helpers for signature generation

  defp sign_payload(payload) do
    [pem_entry] = :public_key.pem_decode(@test_private_key)
    private_key = :public_key.pem_entry_decode(pem_entry)
    :public_key.sign(payload, :sha256, private_key)
  end

  @doc """
  Returns the test public key for use in tests.
  """
  def test_public_key, do: @test_public_key

  @doc """
  Returns the test private key for use in tests.
  """
  def test_private_key, do: @test_private_key
end
