defmodule Challenge.TransactionHandlerTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    supervisor = TestUtils.start_fresh_challenge()
    on_exit(fn -> TestUtils.stop_challenge(supervisor) end)
    %{supervisor: supervisor}
  end

  test "returns error for missing required fields" do
    params = %{}
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_WRONG_SYNTAX"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for short user id" do
    params = TestUtils.bet_params("ab")
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_WRONG_SYNTAX"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for non-integer amount" do
    params = Map.put(TestUtils.bet_params("user1"), :amount, "notanint")
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_WRONG_TYPES"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for invalid token" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    params = TestUtils.bet_params(user)
    sig = TestUtils.valid_signature(params)
    # Don't add token to registry
    assert %{status: "RS_ERROR_INVALID_TOKEN"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for invalid game code" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    params = Map.put(TestUtils.bet_params(user), :token, "token1")
    sig = TestUtils.valid_signature(params)
    # Don't add game code to registry
    assert %{status: "RS_ERROR_INVALID_GAME"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for invalid currency" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", currency: "ZZZ"})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_WRONG_TYPES"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for disabled user" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.disable_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_USER_DISABLED"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for invalid signature" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    # Use an invalid signature
    assert %{status: "RS_ERROR_INVALID_SIGNATURE"} =
      Challenge.TransactionHandler.bet(nil, params, "invalidsig")
  end

  test "returns error for expired token" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "expired")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "expired", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_TOKEN_EXPIRED"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for wrong currency" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", currency: "EUR"})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_WRONG_CURRENCY"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for not enough money" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", amount: 1_000_000})
    sig = TestUtils.valid_signature(params)
    result = Challenge.TransactionHandler.bet(nil, params, sig)
    assert result.status == "RS_ERROR_NOT_ENOUGH_MONEY"
    assert result.balance == 100_000
  end

  test "returns error for invalid sub_partner_id type" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", sub_partner_id: 123})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_WRONG_TYPES"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for disabled sub_partner_id" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    Challenge.UserRegistry.create_sub_partner("sub1")
    Challenge.UserRegistry.disable_sub_partner("sub1")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", sub_partner_id: "sub1"})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_INVALID_PARTNER"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "returns error for invalid sub_partner_id" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", sub_partner_id: "notfound"})
    sig = TestUtils.valid_signature(params)
    assert %{status: "RS_ERROR_INVALID_PARTNER"} =
      Challenge.TransactionHandler.bet(nil, params, sig)
  end

  test "happy path: processes successful bet" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(params)
    result = Challenge.TransactionHandler.bet(nil, params, sig)
    assert result.status == "RS_OK"
    assert result.user == user
    assert result.balance == 100_000 - params.amount
    assert result.currency == "USD"
    assert result.request_uuid == params.request_uuid
  end

  test "idempotency: duplicate bet returns RS_OK" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(params)
    result1 = Challenge.TransactionHandler.bet(nil, params, sig)
    result2 = Challenge.TransactionHandler.bet(nil, params, sig)
    assert result1.status == "RS_OK"
    assert result2.status == "RS_OK"
  end

  test "duplicate bet with different amount returns RS_ERROR_DUPLICATE_TRANSACTION" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", amount: 5})
    sig = TestUtils.valid_signature(params)
    Challenge.TransactionHandler.bet(nil, params, sig)
    params2 = %{params | amount: 10}
    sig2 = TestUtils.valid_signature(params2)
    result2 = Challenge.TransactionHandler.bet(nil, params2, sig2)
    assert result2.status == "RS_ERROR_DUPLICATE_TRANSACTION"
  end

  test "win: missing reference_transaction_uuid returns error" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    win_params = TestUtils.win_params(user, "nonexistent_bet_uuid", %{token: "token1", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(win_params)
    result = Challenge.TransactionHandler.win(nil, win_params, sig)
    assert result.status == "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"
  end

  test "win: happy path" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    bet_params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    bet_sig = TestUtils.valid_signature(bet_params)
    Challenge.TransactionHandler.bet(nil, bet_params, bet_sig)
    win_params = TestUtils.win_params(user, bet_params.transaction_uuid, %{token: "token1", game_code: "ont_blackjackclassic"})
    win_sig = TestUtils.valid_signature(win_params)
    result = Challenge.TransactionHandler.win(nil, win_params, win_sig)
    assert result.status == "RS_OK"
    assert result.user == user
    assert result.balance == 100_000 - bet_params.amount + win_params.amount
    assert result.currency == "USD"
    assert result.request_uuid == win_params.request_uuid
  end
end
