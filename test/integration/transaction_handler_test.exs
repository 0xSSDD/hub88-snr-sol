defmodule Challenge.TransactionHandlerTest do
  @moduledoc """
  Integration tests for Challenge.TransactionHandler.

  These tests exercise the full transaction flow, including:
  - Signature validation, user and token lookup, and business rule enforcement.
  - Orchestration between the handler, user registry, and per-user transaction servers.
  - End-to-end error handling and idempotency.

  ## Why keep these tests?

  - **Full Stack Coverage:** Ensures that all components interact correctly and that the system behaves as expected in real-world scenarios.
  - **API Contract:** Verifies that the handler returns the correct responses for both valid and invalid requests.
  - **Regression Detection:** Catches integration bugs that may not be visible in unit tests.

  For public API acceptance tests, see `challenge_test.exs`.
  For isolated business logic, see the unit test suites.
  """

  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    |> then(fn _ ->
      supervisor = TestUtils.start_fresh_challenge()
      on_exit(fn -> TestUtils.stop_challenge(supervisor) end)
      %{supervisor: supervisor}
    end)
  end

  test "RS_OK(1): win: happy path" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    bet_params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    bet_sig = TestUtils.valid_signature(bet_params)
    Challenge.TransactionHandler.bet(nil, bet_params, bet_sig)

    win_params =
      TestUtils.win_params(user, bet_params.transaction_uuid, %{
        token: "token1",
        game_code: "ont_blackjackclassic"
      })

    win_sig = TestUtils.valid_signature(win_params)
    result = Challenge.TransactionHandler.win(nil, win_params, win_sig)
    assert result.status == "RS_OK"
    assert result.user == user
    assert result.balance == 100_000 - bet_params.amount + win_params.amount
    assert result.currency == "USD"
    assert result.request_uuid == win_params.request_uuid
  end

  test "RS_OK(1): happy path: processes successful bet" do
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

  test "RS_OK(1): idempotency: duplicate bet returns RS_OK" do
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

  test "RS_ERROR_INVALID_PARTNER(3): returns error for disabled sub_partner_id" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    Challenge.UserRegistry.create_sub_partner("sub1")
    Challenge.UserRegistry.disable_sub_partner("sub1")

    params =
      TestUtils.bet_params(user, %{
        token: "token1",
        game_code: "ont_blackjackclassic",
        sub_partner_id: "sub1"
      })

    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_INVALID_PARTNER"} = &1)
  end

  test "RS_ERROR_INVALID_PARTNER(3):returns error for invalid sub_partner_id" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    params =
      TestUtils.bet_params(user, %{
        token: "token1",
        game_code: "ont_blackjackclassic",
        sub_partner_id: "notfound"
      })

    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_INVALID_PARTNER"} = &1)
  end

  test "RS_ERROR_INVALID_TOKEN(4): returns error for invalid token" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    params = TestUtils.bet_params(user)
    sig = TestUtils.valid_signature(params)
    # Don't add token to registry
    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_INVALID_TOKEN"} = &1)
  end

  test "RS_ERROR_INVALID_GAME(5): returns error for invalid game code" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    params = Map.put(TestUtils.bet_params(user), :token, "token1")
    sig = TestUtils.valid_signature(params)
    # Don't add game code to registry
    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_INVALID_GAME"} = &1)
  end

  test "RS_ERROR_WRONG_CURRENCY(6): returns error for wrong currency" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    params =
      TestUtils.bet_params(user, %{
        token: "token1",
        game_code: "ont_blackjackclassic",
        currency: "EUR"
      })

    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_WRONG_CURRENCY"} = &1)
  end

  test "RS_ERROR_NOT_ENOUGH_MONEY(7): returns error for not enough money" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    params =
      TestUtils.bet_params(user, %{
        token: "token1",
        game_code: "ont_blackjackclassic",
        amount: 1_000_000
      })

    sig = TestUtils.valid_signature(params)
    result = Challenge.TransactionHandler.bet(nil, params, sig)
    assert result.status == "RS_ERROR_NOT_ENOUGH_MONEY"
    assert result.balance == 100_000
  end

  test "RS_ERROR_USER_DISABLED(8): returns error for disabled user" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.disable_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_USER_DISABLED"} = &1)
  end

  test "RS_ERROR_INVALID_SIGNATURE(9): returns error for invalid signature" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic"})
    # Use an invalid signature
    Challenge.TransactionHandler.bet(nil, params, "invalidsig")
    |> then(&assert %{status: "RS_ERROR_INVALID_SIGNATURE"} = &1)
  end

  test "RS_ERROR_TOKEN_EXPIRED(10): returns error for expired token" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "expired")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
    params = TestUtils.bet_params(user, %{token: "expired", game_code: "ont_blackjackclassic"})
    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_TOKEN_EXPIRED"} = &1)
  end

  test "RS_ERROR_WRONG_SYNTAX(11): returns error for missing required fields" do
    %{}
    |> TestUtils.valid_signature()
    |> then(&Challenge.TransactionHandler.bet(nil, %{}, &1))
    |> then(&assert %{status: "RS_ERROR_WRONG_SYNTAX"} = &1)
  end

  test "RS_ERROR_WRONG_SYNTAX(11): returns error for short user id" do
    user = "ab"

    user
    |> tap(&Challenge.UserRegistry.create_user/1)
    |> then(fn user_id ->
      Challenge.UserRegistry.add_token(user_id, "token1")
      Challenge.UserRegistry.add_game_code("ont_blackjackclassic")
      TestUtils.bet_params(user_id, %{token: "token1", game_code: "ont_blackjackclassic"})
    end)
    |> then(fn params ->
      sig = TestUtils.valid_signature(params)
      Challenge.TransactionHandler.bet(nil, params, sig)
    end)
    |> then(&assert &1.status == "RS_ERROR_WRONG_SYNTAX")
  end

  test "RS_ERROR_WRONG_TYPES(12): returns error for non-integer amount" do
    TestUtils.bet_params("user1")
    |> Map.put(:amount, "notanint")
    |> tap(fn params -> TestUtils.valid_signature(params) end)
    |> then(fn params ->
      sig = TestUtils.valid_signature(params)
      Challenge.TransactionHandler.bet(nil, params, sig)
    end)
    |> then(&assert %{status: "RS_ERROR_WRONG_TYPES"} = &1)
  end

  test "RS_ERROR_WRONG_TYPES(12): returns error for invalid currency" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    params =
      TestUtils.bet_params(user, %{
        token: "token1",
        game_code: "ont_blackjackclassic",
        currency: "ZZZ"
      })

    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_WRONG_TYPES"} = &1)
  end

  test "RS_ERROR_WRONG_TYPES(12): returns error for invalid sub_partner_id type" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    params =
      TestUtils.bet_params(user, %{
        token: "token1",
        game_code: "ont_blackjackclassic",
        sub_partner_id: 123
      })

    sig = TestUtils.valid_signature(params)

    Challenge.TransactionHandler.bet(nil, params, sig)
    |> then(&assert %{status: "RS_ERROR_WRONG_TYPES"} = &1)
  end

  test "RS_ERROR_DUPLICATE_TRANSACTION(13): duplicate bet with different amount returns RS_ERROR_DUPLICATE_TRANSACTION" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    params =
      TestUtils.bet_params(user, %{token: "token1", game_code: "ont_blackjackclassic", amount: 5})

    sig = TestUtils.valid_signature(params)
    Challenge.TransactionHandler.bet(nil, params, sig)
    params2 = %{params | amount: 10}
    sig2 = TestUtils.valid_signature(params2)
    result2 = Challenge.TransactionHandler.bet(nil, params2, sig2)
    assert result2.status == "RS_ERROR_DUPLICATE_TRANSACTION"
  end

  test "RS_ERROR_TRANSACTION_DOES_NOT_EXIST(14): win: missing reference_transaction_uuid returns error" do
    user = "user1"
    Challenge.UserRegistry.create_user(user)
    Challenge.UserRegistry.add_token(user, "token1")
    Challenge.UserRegistry.add_game_code("ont_blackjackclassic")

    win_params =
      TestUtils.win_params(user, "nonexistent_bet_uuid", %{
        token: "token1",
        game_code: "ont_blackjackclassic"
      })

    sig = TestUtils.valid_signature(win_params)
    result = Challenge.TransactionHandler.win(nil, win_params, sig)
    assert result.status == "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"
  end
end
