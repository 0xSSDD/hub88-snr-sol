defmodule ConcurrencyTest do
  use ExUnit.Case, async: false

  setup do
    TestHelper.reset_test_environment()
    |> then(fn _ ->
      root_supervisor = TestHelper.start_fresh_challenge()
      user_id = "user1"
      Challenge.create_users(root_supervisor, [user_id])

      base_params = TestHelper.bet_params(user_id, %{amount: 60_000})
      Challenge.UserRegistry.add_token(user_id, base_params.token)
      Challenge.UserRegistry.add_game_code(base_params.game_code)

      on_exit(fn -> TestHelper.stop_challenge(root_supervisor) end)

      %{root_supervisor: root_supervisor, user_id: user_id, base_params: base_params}
    end)
  end

  test "concurrent bets for same user do not overdraw", %{
    root_supervisor: root_supervisor,
    user_id: user_id,
    base_params: base_params
  } do
    1..2
    |> Task.async_stream(
      fn i ->
        %{base_params | transaction_uuid: "bet_#{i}_#{System.unique_integer()}"}
        |> tap(fn params ->
          Challenge.UserRegistry.add_token(user_id, params.token)
          Challenge.UserRegistry.add_game_code(params.game_code)
        end)
        |> then(fn params ->
          headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(params)}
          Challenge.Gateway.bet(root_supervisor, params, headers)
        end)
      end,
      max_concurrency: System.schedulers_online(),
      timeout: 2_000
    )
    |> Enum.map(fn {:ok, res} -> res end)
    |> then(fn results ->
      statuses = Enum.map(results, & &1.status)
      assert Enum.sort(statuses) == Enum.sort(["RS_OK", "RS_ERROR_NOT_ENOUGH_MONEY"])
      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000 - 60_000
    end)
  end

  test "concurrent bets for different users are isolated" do
    TestHelper.reset_test_environment()
    |> then(fn _ -> TestHelper.start_fresh_challenge() end)
    |> tap(fn root_supervisor ->
      ["user1", "user2"]
      |> Enum.each(&Challenge.create_users(root_supervisor, [&1]))
    end)
    |> then(fn root_supervisor ->
      ["user1", "user2"]
      |> Enum.map(fn user_id ->
        TestHelper.bet_params(user_id, %{amount: 10_000})
        |> tap(fn params ->
          Challenge.UserRegistry.add_token(user_id, params.token)
          Challenge.UserRegistry.add_game_code(params.game_code)
        end)
        |> then(&{user_id, &1})
      end)
      |> then(fn params_list ->
        params_list
        |> Task.async_stream(
          fn {_user_id, params} ->
            headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(params)}
            Challenge.Gateway.bet(root_supervisor, params, headers)
          end,
          max_concurrency: System.schedulers_online(),
          timeout: 2_000
        )
        |> Enum.map(fn {:ok, res} -> res end)
        |> tap(fn results ->
          Enum.each(results, fn result -> assert result.status == "RS_OK" end)
        end)
        |> then(fn _ ->
          ["user1", "user2"]
          |> Enum.each(fn user_id ->
            {:ok, user} = Challenge.UserRegistry.get_user(user_id)
            assert user.balance == 100_000 - 10_000
          end)
        end)
      end)

      TestHelper.stop_challenge(root_supervisor)
    end)
  end

  test "duplicate transactions with same UUID are idempotent", %{
    root_supervisor: root_supervisor,
    user_id: user_id,
    base_params: base_params
  } do
    headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(base_params)}

    1..2
    |> Task.async_stream(
      fn _ -> Challenge.Gateway.bet(root_supervisor, base_params, headers) end,
      max_concurrency: System.schedulers_online(),
      timeout: 2_000
    )
    |> Enum.map(fn {:ok, res} -> res end)
    |> then(fn results ->
      statuses = Enum.map(results, & &1.status)
      assert statuses == ["RS_OK", "RS_OK"]
      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000 - 60_000
    end)
  end
end
