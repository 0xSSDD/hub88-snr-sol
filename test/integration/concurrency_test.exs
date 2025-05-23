defmodule ConcurrencyTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    root_supervisor = TestUtils.start_fresh_challenge()
    user_id = "user1"
    Challenge.create_users(root_supervisor, [user_id])

    # Base params - we'll generate unique transaction_uuids for each bet
    base_params = TestUtils.bet_params(user_id, %{amount: 60_000})
    Challenge.UserRegistry.add_token(user_id, base_params.token)
    Challenge.UserRegistry.add_game_code(base_params.game_code)

    on_exit(fn ->
      TestUtils.stop_challenge(root_supervisor)
    end)

    %{root_supervisor: root_supervisor, user_id: user_id, base_params: base_params}
  end

  test "concurrent bets for same user do not overdraw", %{
    root_supervisor: root_supervisor,
    user_id: user_id,
    base_params: base_params
  } do
    # Generate different transaction_uuids for each concurrent bet
    results =
      1..2
      |> Task.async_stream(
        fn i ->
          # Create unique params for each bet
          params = %{base_params | transaction_uuid: "bet_#{i}_#{System.unique_integer()}"}
          headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
          Challenge.Gateway.bet(root_supervisor, params, headers)
        end,
        max_concurrency: 2,
        timeout: 2_000
      )
      |> Enum.map(fn {:ok, res} -> res end)

    statuses = Enum.map(results, & &1.status)

    # One should succeed and one should fail with insufficient funds
    assert Enum.sort(statuses) == Enum.sort(["RS_OK", "RS_ERROR_NOT_ENOUGH_MONEY"])

    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    # Only one bet should have succeeded
    assert user.balance == 100_000 - 60_000
  end

  test "concurrent bets for different users are isolated" do
    TestUtils.reset_test_environment()
    root_supervisor = TestUtils.start_fresh_challenge()

    user_ids = ["user1", "user2"]
    Enum.each(user_ids, &Challenge.create_users(root_supervisor, [&1]))

    params_list =
      Enum.map(user_ids, fn user_id ->
        params = TestUtils.bet_params(user_id, %{amount: 10_000})
        Challenge.UserRegistry.add_token(user_id, params.token)
        Challenge.UserRegistry.add_game_code(params.game_code)
        {user_id, params}
      end)

    results =
      params_list
      |> Task.async_stream(
        fn {_user_id, params} ->
          headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
          Challenge.Gateway.bet(root_supervisor, params, headers)
        end,
        max_concurrency: 2,
        timeout: 2_000
      )
      |> Enum.map(fn {:ok, res} -> res end)

    Enum.each(results, fn result ->
      assert result.status == "RS_OK"
    end)

    Enum.each(user_ids, fn user_id ->
      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000 - 10_000
    end)

    # Clean up
    TestUtils.stop_challenge(root_supervisor)
  end

  test "duplicate transactions with same UUID are idempotent", %{
    root_supervisor: root_supervisor,
    user_id: user_id,
    base_params: base_params
  } do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(base_params)}

    # Both requests use the same transaction_uuid (testing idempotency)
    results =
      1..2
      |> Task.async_stream(
        fn _ ->
          Challenge.Gateway.bet(root_supervisor, base_params, headers)
        end,
        max_concurrency: 2,
        timeout: 2_000
      )
      |> Enum.map(fn {:ok, res} -> res end)

    # Both should return RS_OK due to idempotency
    statuses = Enum.map(results, & &1.status)
    assert statuses == ["RS_OK", "RS_OK"]

    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    # Balance should only be debited once
    assert user.balance == 100_000 - 60_000
  end
end
