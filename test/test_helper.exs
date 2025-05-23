ExUnit.start()

defmodule TestUtils do
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
  Returns a valid signature (mimics a valid X-Hub88-Signature header).
  """
  def valid_signature, do: "good"

  @doc """
  Returns an invalid signature (mimics a bad X-Hub88-Signature header).
  """
  def invalid_signature, do: "bad"
end
