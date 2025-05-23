defmodule ChallengeTest do
  use ExUnit.Case
  doctest Challenge

  @moduletag :capture_log

  describe "Challenge.start/0" do
    test "returns a valid server pid" do
      # Clean start
      supervisor = TestUtils.start_fresh_challenge()

      assert is_pid(supervisor)
      assert Process.alive?(supervisor)

      # Clean shutdown
      TestUtils.stop_challenge(supervisor)
    end

    test "creates a supervision tree correctly" do
      supervisor = TestUtils.start_fresh_challenge()

      try do
        # Verify the main supervisor is running
        assert is_pid(supervisor)

        children = Supervisor.which_children(supervisor)
        # Verify supervisors are running
        assert length(children) == 2
        assert List.keyfind(children, Challenge.DataSupervisor, 0)
        assert List.keyfind(children, Challenge.PartitionSupervisor, 0)

        # Verify ETS tables exist
        tables = :ets.all()
        assert :users in tables
        assert :transactions in tables
        assert :processed_transactions in tables
      after
        TestUtils.stop_challenge(supervisor)
      end
    end
  end

  describe "Challenge.create_users/2" do
    setup do
      TestUtils.reset_test_environment()
      supervisor = TestUtils.start_fresh_challenge()

      on_exit(fn ->
        TestUtils.stop_challenge(supervisor)
      end)

      %{root_supervisor: supervisor}
    end

    test "creates a single user correctly", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, ["user1"])

      # Verify user was created in ETS
      {:ok, user_data} = Challenge.UserRegistry.get_user("user1")
      assert user_data.balance == 100_000
      assert user_data.currency == "USD"
      assert is_integer(user_data.created_at)
    end

    test "creates multiple users simultaneously", %{root_supervisor: root_supervisor} do
      users = Enum.map(1..1000, &"user_#{&1}")  # Reduced from 10k for faster tests

      assert :ok == Challenge.create_users(root_supervisor, users)

      # Verify all users were created in ETS
      Enum.each(users, fn user ->
        {:ok, user_data} = Challenge.UserRegistry.get_user(user)
        assert user_data.balance == 100_000
        assert user_data.currency == "USD"
        assert is_integer(user_data.created_at)
      end)
    end

    test "ignores empty string", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, [""])
      assert :ok == Challenge.create_users(root_supervisor, [""])
    end

    test "ignores existing users", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, ["user1"])

      # Modify user balance manually
      Challenge.UserRegistry.update_balance("user1", -50_000)
      {:ok, modified_user} = Challenge.UserRegistry.get_user("user1")
      original_balance = modified_user.balance

      # Try to create the same user again
      Challenge.create_users(root_supervisor, ["user1"])

      # Verify balance wasn't reset
      {:ok, final_user} = Challenge.UserRegistry.get_user("user1")
      assert final_user.balance == original_balance
    end

    test "handles nil and non-string inputs gracefully", %{root_supervisor: root_supervisor} do
      # This should not crash the system
      assert :ok = Challenge.create_users(root_supervisor, [nil, 123, :atom, "valid_user"])

      # Only valid string should be created
      {:ok, _} = Challenge.UserRegistry.get_user("valid_user")
    end
  end

  describe "Challenge.bet/2" do
    setup do
      root_supervisor = TestUtils.start_fresh_challenge()
      user_id = "user1"

      # Create user
      Challenge.create_users(root_supervisor, [user_id])

      # Generate params with a known token
      params = TestUtils.bet_params(user_id)

      # Add the generated token to the registry
      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)

      on_exit(fn ->
        TestUtils.stop_challenge(root_supervisor)
      end)

      %{root_supervisor: root_supervisor, user_id: user_id, params: params}
    end

    test "RS_OK(1): processes successful bet", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      params: params
    } do
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)

      assert result.status == "RS_OK"
      assert result.user == user_id
      assert result.balance == 100_000 - 5
      assert result.currency == "USD"
      assert result.request_uuid == params.request_uuid
    end

    test "RS_ERROR_UNKNOWN(2) for non-existent user", %{root_supervisor: root_supervisor} do
      # Do NOT create the user
      user_id = "ghost_user"
      params = TestUtils.bet_params(user_id)
      # Register token and game code for completeness
      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}

      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_UNKNOWN"
      assert result.user == user_id
      assert result.request_uuid == params.request_uuid
    end

    test "RS_ERROR_INVALID_PARTNER(3) for disabled sub_partner_id", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{sub_partner_id: "sub_disabled"})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      Challenge.UserRegistry.create_sub_partner("sub_disabled")
      Challenge.UserRegistry.disable_sub_partner("sub_disabled")
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_PARTNER"
    end

    test "RS_ERROR_INVALID_PARTNER(3) for invalid sub_partner_id", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{sub_partner_id: "nonexistent"})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_PARTNER"
    end

    test "RS_ERROR_INVALID_TOKEN(4) for invalid token", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{token: "not_a_real_token"})
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_TOKEN"
    end

    test "RS_ERROR_INVALID_GAME(5) for invalid game_code", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{game_code: "ont_whitejackclassic"})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_GAME"
    end

    test "RS_ERROR_WRONG_CURRENCY(6) for currency mismatch", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{currency: "EUR"})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_WRONG_CURRENCY"
    end

    test "RS_ERROR_NOT_ENOUGH_MONEY(7) for excessive bet", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{amount: 1_000_000_000})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}

      {:ok, user_before} = Challenge.UserRegistry.get_user(user_id)
      assert user_before.balance == 100_000

      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_NOT_ENOUGH_MONEY"
      assert result.balance == 100_000

      {:ok, user_after} = Challenge.UserRegistry.get_user(user_id)
      assert user_after.balance == user_before.balance
    end

    test "RS_ERROR_USER_DISABLED(8) for disabled user", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      params: params
    } do
      :ok = Challenge.UserRegistry.disable_user(user_id)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)

      assert result.status == "RS_ERROR_USER_DISABLED"
    end

    test "RS_ERROR_INVALID_SIGNATURE(9) for invalid signature", %{
      root_supervisor: root_supervisor,
      params: params
    } do
      headers = %{"X-Hub88-Signature" => "invalid_signature"}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_SIGNATURE"
    end

    test "RS_ERROR_TOKEN_EXPIRED(10) for expired token", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{token: "expired"})
      Challenge.UserRegistry.add_game_code(params.game_code)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_TOKEN_EXPIRED"
      assert result.user == user_id
      assert result.request_uuid == params.request_uuid
    end

    test "RS_ERROR_WRONG_SYNTAX(11) for missing required fields", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params =
        TestUtils.bet_params(user_id)
        |> Map.drop([:transaction_uuid])

      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_WRONG_SYNTAX"
    end

    test "RS_ERROR_WRONG_TYPES(12) for a random currency", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{currency: "DOG"})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_WRONG_TYPES"
    end

    test "RS_ERROR_DUPLICATE_TRANSACTION(13) for same UUID, different params", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{amount: 5})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      Challenge.Gateway.bet(root_supervisor, params, headers)

      # Change amount, but keep transaction_uuid the same
      params2 = %{params | amount: 10}
      headers2 = %{"X-Hub88-Signature" => TestUtils.valid_signature(params2)}
      result = Challenge.Gateway.bet(root_supervisor, params2, headers2)
      assert result.status == "RS_ERROR_DUPLICATE_TRANSACTION"
    end

    # TODO: RS_ERROR_LIMIT_REACHED(15)
  end

  describe "Challenge.win/2" do
    setup do
      TestUtils.reset_test_environment()
      root_supervisor = TestUtils.start_fresh_challenge()
      user_id = "user1"
      Challenge.create_users(root_supervisor, [user_id])

      # Use helpers to generate a token and game code
      params = TestUtils.bet_params(user_id)
      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)

      on_exit(fn ->
        TestUtils.stop_challenge(root_supervisor)
      end)

      %{root_supervisor: root_supervisor, user_id: user_id, bet_params: params}
    end

    test "RS_OK(1) for valid win", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      bet_params: bet_params
    } do
      # Place a bet
      bet_headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(bet_params)}
      bet_result = Challenge.Gateway.bet(root_supervisor, bet_params, bet_headers)
      assert bet_result.status == "RS_OK"

      # Win referencing the bet
      win_params =
        TestUtils.win_params(user_id, bet_params.transaction_uuid, %{
          token: bet_params.token,
          game_code: bet_params.game_code,
          currency: bet_params.currency
        })

      win_headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(win_params)}
      win_result = Challenge.Gateway.win(root_supervisor, win_params, win_headers)

      assert win_result.status == "RS_OK"
      assert win_result.user == user_id
      assert win_result.request_uuid == win_params.request_uuid
      assert win_result.balance == 100_000 - bet_params.amount + win_params.amount
      assert win_result.currency == bet_params.currency
    end

    test "RS_ERROR_TRANSACTION_DOES_NOT_EXIST(14) for missing reference_transaction_uuid", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      bet_params: bet_params
    } do
      win_params =
        TestUtils.win_params(user_id, "nonexistent_bet_uuid", %{
          token: bet_params.token,
          game_code: bet_params.game_code,
          currency: bet_params.currency
        })

      win_headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(win_params)}
      win_result = Challenge.Gateway.win(root_supervisor, win_params, win_headers)

      assert win_result.status == "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"
      assert win_result.user == user_id
      assert win_result.request_uuid == win_params.request_uuid
    end

    test "RS_ERROR_TOKEN_EXPIRED(10) does NOT check for token expiry on win", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      bet_params: bet_params
    } do
      # Place a bet with a valid token
      bet_headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(bet_params)}
      bet_result = Challenge.Gateway.bet(root_supervisor, bet_params, bet_headers)
      assert bet_result.status == "RS_OK"

      # Now win with token: "expired"
      win_params =
        TestUtils.win_params(user_id, bet_params.transaction_uuid, %{
          token: "expired",
          game_code: bet_params.game_code,
          currency: bet_params.currency
        })

      win_headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(win_params)}
      win_result = Challenge.Gateway.win(root_supervisor, win_params, win_headers)
      # Should still succeed!
      assert win_result.status == "RS_OK"
    end
  end

  describe "Test Utils" do
    test "random_uuid/0" do
      uuid = TestUtils.random_uuid()
      assert is_binary(uuid)
      assert String.length(uuid) == 36
    end
  end
end
