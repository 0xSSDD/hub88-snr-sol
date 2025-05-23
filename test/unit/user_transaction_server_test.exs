defmodule Challenge.UserTransactionServerTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    supervisor = TestUtils.start_fresh_challenge()
    user_id = "user1"
    Challenge.UserRegistry.create_user(user_id)
    {:ok, pid} = Challenge.UserTransactionServer.start_link(user_id)

    on_exit(fn ->
      TestUtils.stop_challenge(supervisor)
    end)

    %{user_id: user_id, server: pid}
  end

  test "bet/2 debits balance and is idempotent", %{server: server, user_id: user_id} do
    params = TestUtils.bet_params(user_id)
    assert %{status: "RS_OK"} = Challenge.UserTransactionServer.bet(server, params)
    # Second call with same params is idempotent
    assert %{status: "RS_OK"} = Challenge.UserTransactionServer.bet(server, params)
    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    assert user.balance == 100_000 - params.amount
  end

  test "bet/2 returns error for insufficient funds, RS_ERROR_NOT_ENOUGH_MONEY(7)", %{server: server, user_id: user_id} do
    params = TestUtils.bet_params(user_id, %{amount: 1_000_000})
    assert %{status: "RS_ERROR_NOT_ENOUGH_MONEY"} = Challenge.UserTransactionServer.bet(server, params)
    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    assert user.balance == 100_000
  end

  test "win/2 credits balance", %{server: server, user_id: user_id} do
    # Place a bet first
    bet_params = TestUtils.bet_params(user_id)
    Challenge.UserTransactionServer.bet(server, bet_params)
    win_params = TestUtils.win_params(user_id, bet_params.transaction_uuid)
    assert %{status: "RS_OK"} = Challenge.UserTransactionServer.win(server, win_params)
    {:ok, user} = Challenge.UserRegistry.get_user(user_id)
    assert user.balance == 100_000 - bet_params.amount + win_params.amount
  end

  test "win/2 returns error for missing reference_transaction_uuid, RS_ERROR_TRANSACTION_DOES_NOT_EXIST(14)", %{server: server, user_id: user_id} do
    win_params = TestUtils.win_params(user_id, "nonexistent_bet_uuid")
    assert %{status: "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"} = Challenge.UserTransactionServer.win(server, win_params)
  end

  test "bet/2 returns error for wrong currency, RS_ERROR_WRONG_CURRENCY(6)", %{server: server, user_id: user_id} do
    params = TestUtils.bet_params(user_id, %{currency: "EUR"})
    assert %{status: "RS_ERROR_WRONG_CURRENCY"} = Challenge.UserTransactionServer.bet(server, params)
  end

  test "bet/2 returns error for disabled user, RS_ERROR_USER_DISABLED(8)", %{server: server, user_id: user_id} do
    Challenge.UserRegistry.disable_user(user_id)
    params = TestUtils.bet_params(user_id)
    assert %{status: "RS_ERROR_USER_DISABLED"} = Challenge.UserTransactionServer.bet(server, params)
  end

  test "bet/2 returns error for unknown user, RS_ERROR_UNKNOWN(2)" do
    {:ok, server} = Challenge.UserTransactionServer.start_link("ghost_user")
    params = TestUtils.bet_params("ghost_user")
    assert %{status: "RS_ERROR_UNKNOWN"} = Challenge.UserTransactionServer.bet(server, params)
  end

  test "bet/2 returns error for duplicate transaction with mismatched params, RS_ERROR_DUPLICATE_TRANSACTION(13)", %{server: server, user_id: user_id} do
    params = TestUtils.bet_params(user_id, %{amount: 5})
    Challenge.UserTransactionServer.bet(server, params)
    params2 = %{params | amount: 10}
    assert %{status: "RS_ERROR_DUPLICATE_TRANSACTION"} = Challenge.UserTransactionServer.bet(server, params2)
  end
end
