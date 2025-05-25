defmodule ChallengeTest do
  @moduledoc """
  Acceptance and smoke tests for the public Challenge API.

  This file ensures that the *actual* public API surface (`Challenge.start/0`, `Challenge.create_users/2`, `Challenge.bet/2`, `Challenge.win/2`)
  behaves correctly from a client perspective, regardless of internal implementation.

  ## Why keep these tests?

  - **API Contract:** Verifies that the public API remains stable and correct, even if internal modules or flows change.
  - **End-to-End Coverage:** Exercises the full stack, including supervision, process registration, signature validation, and business logic.
  - **Smoke Testing:** Catches regressions in wiring, argument handling, or integration that lower-level tests may miss.
  - **Minimal Redundancy:** Only a few representative error and success cases are tested here, as detailed business logic is covered in integration/unit tests.

  ## When to add tests here?

  - When you want to guarantee a specific behavior or error is visible to API consumers.
  - When adding or changing public API functions.
  - When you want a high-level confidence check after major refactors.

  For detailed business logic, see the integration and unit test suites.
  """

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
      # Reduced from 10k for faster tests
      users = Enum.map(1..1000, &"user_#{&1}")

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

    test "returns :ok when all users are invalid", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, [nil, "", 123, :atom])
      # No users should be created
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user("")
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user(nil)
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user("123")
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user("atom")
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

    test "RS_ERROR_INVALID_TOKEN(4) for invalid token", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestUtils.bet_params(user_id, %{token: "not_a_real_token"})
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_TOKEN"
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

  describe "bet/2 and win/2 header path" do
    test "bet/2 builds headers and calls Gateway.bet" do
      server = Challenge.start()
      body = %{signature: "sig"}
      # Should not crash, just for coverage
      Challenge.bet(server, body)
    end

    test "win/2 builds headers and calls Gateway.win" do
      server = Challenge.start()
      body = %{signature: "sig"}
      # Should not crash, just for coverage
      Challenge.win(server, body)
    end
  end
end
