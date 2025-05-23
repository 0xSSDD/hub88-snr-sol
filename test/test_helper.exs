ExUnit.start()

Application.ensure_all_started(:crypto)
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
  def win_params(user_id, reference_transaction_uuid, overrides \\ %{}) do
    base = %{
      user: user_id,
      transaction_uuid: random_uuid(),
      reference_transaction_uuid: reference_transaction_uuid,
      amount: 10,
      request_uuid: random_uuid(),
      currency: "USD",
      game_code: "ont_blackjackclassic",
      token: random_uuid()
    }

    Map.merge(base, overrides)
  end

  @doc """
  Generates a valid RSA-SHA256 signature for the given payload.
  Uses the test private key to sign the JSON-encoded payload.
  """
  def valid_signature(payload \\ %{test: "data"}) do
    json = encode_json(payload)

    json
    |> sign_payload()
    |> Base.encode64()
  end

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

  @doc """
  Returns the test public key for use in tests.
  """
  def test_public_key, do: @test_public_key

  @doc """
  Returns the test private key for use in tests.
  """
  def test_private_key, do: @test_private_key

  @doc """
  Starts a fresh Challenge application instance with clean state.
  Returns the root supervisor PID.
  """
  def start_fresh_challenge do
    # Stop any existing Challenge application
    case Application.stop(:challenge) do
      :ok -> :ok
      {:error, :not_started} -> :ok
      {:error, _reason} -> :ok
    end

    # Wait a bit for cleanup
    Process.sleep(10)

    # Start fresh
    Challenge.start()
  end

  @doc """
  Ensures clean test environment by resetting all ETS tables.
  """
  def reset_test_environment do
    try do
      Challenge.UserRegistry.reset_all_tables()
    rescue
      # Tables might not exist yet
      _ -> :ok
    end
  end

  @doc """
  Clean shutdown of Challenge application.
  """
  def stop_challenge(supervisor_pid) when is_pid(supervisor_pid) do
    try do
      Process.exit(supervisor_pid, :normal)
      # Wait for clean shutdown
      Process.sleep(10)
    rescue
      _ -> :ok
    end
  end

  def stop_challenge(_), do: :ok
end
