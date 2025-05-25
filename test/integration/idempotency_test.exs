defmodule IdempotencyTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    |> then(fn _ ->
      root_supervisor = TestUtils.start_fresh_challenge()
      user_id = "user1"
      Challenge.create_users(root_supervisor, [user_id])

      params =
        TestUtils.bet_params(user_id)
        |> tap(fn p ->
          Challenge.UserRegistry.add_token(user_id, p.token)
          Challenge.UserRegistry.add_game_code(p.game_code)
        end)

      on_exit(fn -> TestUtils.stop_challenge(root_supervisor) end)

      %{root_supervisor: root_supervisor, user_id: user_id, params: params}
    end)
  end

  test "duplicate bet with same transaction_uuid is idempotent", %{
    root_supervisor: root_supervisor,
    params: params,
    user_id: user_id
  } do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}

    result1 = Challenge.Gateway.bet(root_supervisor, params, headers)
    result2 = Challenge.Gateway.bet(root_supervisor, params, headers)

    assert result1.status == "RS_OK"
    assert result2.status in ["RS_OK", "RS_ERROR_DUPLICATE_TRANSACTION"]

    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    assert user.balance == 100_000 - params.amount
  end

  test "duplicate bet with same transaction_uuid but different amount returns RS_ERROR_DUPLICATE_TRANSACTION(13)",
       %{root_supervisor: root_supervisor, params: params} do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
    Challenge.Gateway.bet(root_supervisor, params, headers)

    params2 = %{params | amount: params.amount + 1}
    headers2 = %{"X-Hub88-Signature" => TestUtils.valid_signature(params2)}
    result2 = Challenge.Gateway.bet(root_supervisor, params2, headers2)

    assert result2.status == "RS_ERROR_DUPLICATE_TRANSACTION"
  end

  test "duplicate bet with same transaction_uuid and different meta is idempotent", %{
    root_supervisor: root_supervisor,
    params: params
  } do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
    Challenge.Gateway.bet(root_supervisor, params, headers)

    params2 = Map.put(params, :meta, %{foo: "bar"})
    headers2 = %{"X-Hub88-Signature" => TestUtils.valid_signature(params2)}
    result2 = Challenge.Gateway.bet(root_supervisor, params2, headers2)

    assert result2.status in ["RS_OK", "RS_ERROR_DUPLICATE_TRANSACTION"]
  end

  test "duplicate win with same transaction_uuid is idempotent", %{
    root_supervisor: root_supervisor,
    user_id: user_id,
    params: params
  } do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
    Challenge.Gateway.bet(root_supervisor, params, headers)

    win_params =
      TestUtils.win_params(user_id, params.transaction_uuid, %{
        token: params.token,
        game_code: params.game_code,
        currency: params.currency
      })

    win_headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(win_params)}
    result1 = Challenge.Gateway.win(root_supervisor, win_params, win_headers)
    result2 = Challenge.Gateway.win(root_supervisor, win_params, win_headers)

    assert result1.status == "RS_OK"
    assert result2.status in ["RS_OK", "RS_ERROR_DUPLICATE_TRANSACTION"]

    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    assert user.balance == 100_000 - params.amount + win_params.amount
  end
end
