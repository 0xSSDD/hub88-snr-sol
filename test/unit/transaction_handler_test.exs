defmodule Challenge.TransactionHandlerTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    :ok
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

end
