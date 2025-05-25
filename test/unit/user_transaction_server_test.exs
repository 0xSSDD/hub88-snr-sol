defmodule Challenge.UserTransactionServerTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    |> then(fn _ ->
      supervisor = TestUtils.start_fresh_challenge()
      user_id = "user1"
      Challenge.UserRegistry.create_user(user_id)
      {:ok, pid} = Challenge.UserTransactionServer.start_link(user_id)
      on_exit(fn -> TestUtils.stop_challenge(supervisor) end)
      %{user_id: user_id, server: pid}
    end)
  end

  test "RS_OK(1): win/2 credits balance", %{server: server, user_id: user_id} do
    TestUtils.bet_params(user_id)
    |> tap(&Challenge.UserTransactionServer.bet(server, &1))
    |> then(fn bet_params ->
      win_params = TestUtils.win_params(user_id, bet_params.transaction_uuid)
      assert %{status: "RS_OK"} = Challenge.UserTransactionServer.win(server, win_params)
      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000 - bet_params.amount + win_params.amount
    end)
  end

  test "RS_OK(1): bet/2 debits balance and is idempotent", %{server: server, user_id: user_id} do
    TestUtils.bet_params(user_id)
    |> tap(fn params ->
      assert %{status: "RS_OK"} = Challenge.UserTransactionServer.bet(server, params)
      # Second call with same params is idempotent
      assert %{status: "RS_OK"} = Challenge.UserTransactionServer.bet(server, params)
    end)
    |> then(fn params ->
      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000 - params.amount
    end)
  end

  test "RS_ERROR_UNKNOWN(2): bet/2 returns error for unknown user", %{server: _server} do
    {:ok, server} = Challenge.UserTransactionServer.start_link("ghost_user")

    TestUtils.bet_params("ghost_user")
    |> then(
      &assert %{status: "RS_ERROR_UNKNOWN"} = Challenge.UserTransactionServer.bet(server, &1)
    )
  end

  test "RS_ERROR_WRONG_CURRENCY(6): bet/2 returns error for wrong currency", %{
    server: server,
    user_id: user_id
  } do
    TestUtils.bet_params(user_id, %{currency: "EUR"})
    |> then(
      &assert %{status: "RS_ERROR_WRONG_CURRENCY"} =
                Challenge.UserTransactionServer.bet(server, &1)
    )
  end

  test "RS_ERROR_NOT_ENOUGH_MONEY(7): bet/2 returns error for insufficient funds", %{
    server: server,
    user_id: user_id
  } do
    TestUtils.bet_params(user_id, %{amount: 1_000_000})
    |> then(fn params ->
      assert %{status: "RS_ERROR_NOT_ENOUGH_MONEY"} =
               Challenge.UserTransactionServer.bet(server, params)

      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000
    end)
  end

  test "RS_ERROR_USER_DISABLED(8): bet/2 returns error for disabled user", %{
    server: server,
    user_id: user_id
  } do
    Challenge.UserRegistry.disable_user(user_id)

    TestUtils.bet_params(user_id)
    |> then(
      &assert %{status: "RS_ERROR_USER_DISABLED"} =
                Challenge.UserTransactionServer.bet(server, &1)
    )
  end

  test "RS_ERROR_DUPLICATE_TRANSACTION(13): bet/2 returns error for duplicate transaction with mismatched params",
       %{server: server, user_id: user_id} do
    TestUtils.bet_params(user_id, %{amount: 5})
    |> tap(&Challenge.UserTransactionServer.bet(server, &1))
    |> then(fn params ->
      params2 = %{params | amount: 10}

      assert %{status: "RS_ERROR_DUPLICATE_TRANSACTION"} =
               Challenge.UserTransactionServer.bet(server, params2)
    end)
  end

  test "RS_ERROR_TRANSACTION_DOES_NOT_EXIST(14): win/2 returns error for missing reference_transaction_uuid",
       %{server: server, user_id: user_id} do
    TestUtils.win_params(user_id, "nonexistent_bet_uuid")
    |> then(
      &assert %{status: "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"} =
                Challenge.UserTransactionServer.win(server, &1)
    )
  end
end
