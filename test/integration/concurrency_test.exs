defmodule ConcurrencyTest do
  use ExUnit.Case, async: false

  setup do
    root_supervisor = Challenge.start()
    Challenge.UserRegistry.reset_all_tables()
    user_id = "user1"
    Challenge.create_users(root_supervisor, [user_id])
    params = TestUtils.bet_params(user_id, %{amount: 60_000})
    Challenge.UserRegistry.add_token(user_id, params.token)
    Challenge.UserRegistry.add_game_code(params.game_code)
    on_exit(fn -> Process.exit(root_supervisor, :normal) end)
    %{root_supervisor: root_supervisor, user_id: user_id, params: params}
  end

  test "concurrent bets for same user do not overdraw", %{
    root_supervisor: root_supervisor,
    user_id: user_id,
    params: params
  } do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}

    # Two bets of 60_000 each, but user only has 100_000
    results =
      1..2
      |> Task.async_stream(
        fn _ ->
          Challenge.Gateway.bet(root_supervisor, params, headers)
        end,
        max_concurrency: 2,
        timeout: 2_000
      )
      |> Enum.map(fn {:ok, res} -> res end)

    statuses = Enum.map(results, & &1.status)
    assert Enum.sort(statuses) == Enum.sort(["RS_OK", "RS_ERROR_NOT_ENOUGH_MONEY"])

    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    # Only one bet should have succeeded
    assert user.balance == 100_000 - 60_000
  end

  test "concurrent bets for different users are isolated" do
    root_supervisor = Challenge.start()
    Challenge.UserRegistry.reset_all_tables()
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
        fn {user_id, params} ->
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
  end
end
