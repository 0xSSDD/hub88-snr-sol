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
      TestHelper.start_fresh_challenge()
      |> tap(fn supervisor ->
        assert is_pid(supervisor)
        assert Process.alive?(supervisor)
      end)
      |> TestHelper.stop_challenge()
    end

    test "creates a supervision tree correctly" do
      TestHelper.start_fresh_challenge()
      |> tap(fn supervisor ->
        assert is_pid(supervisor)

        children = Supervisor.which_children(supervisor)
        assert length(children) == 2
        assert List.keyfind(children, Challenge.DataSupervisor, 0)
        assert List.keyfind(children, Challenge.PartitionSupervisor, 0)

        tables = :ets.all()
        assert :users in tables
        assert :transactions in tables
        assert :processed_transactions in tables
      end)
      |> TestHelper.stop_challenge()
    end
  end

  describe "Challenge.create_users/2" do
    setup do
      TestHelper.reset_test_environment()
      supervisor = TestHelper.start_fresh_challenge()

      on_exit(fn -> TestHelper.stop_challenge(supervisor) end)
      %{root_supervisor: supervisor}
    end

    test "creates a single user correctly", %{root_supervisor: root_supervisor} do
      root_supervisor
      |> Challenge.create_users(["user1"])
      |> then(fn :ok ->
        Challenge.UserRegistry.get_user("user1")
        |> then(fn {:ok, user_data} ->
          assert user_data.balance == 100_000
          assert user_data.currency == "USD"
          assert is_integer(user_data.created_at)
        end)
      end)
    end

    test "creates multiple users simultaneously", %{root_supervisor: root_supervisor} do
      users = Enum.map(1..1000, &"user_#{&1}")

      root_supervisor
      |> Challenge.create_users(users)
      |> then(fn :ok ->
        users
        |> Enum.each(fn user ->
          Challenge.UserRegistry.get_user(user)
          |> then(fn {:ok, user_data} ->
            assert user_data.balance == 100_000
            assert user_data.currency == "USD"
            assert is_integer(user_data.created_at)
          end)
        end)
      end)
    end

    test "ignores empty string", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, [""])
      assert :ok == Challenge.create_users(root_supervisor, [""])
    end

    test "ignores existing users", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, ["user1"])

      Challenge.UserRegistry.update_balance("user1", -50_000)
      {:ok, modified_user} = Challenge.UserRegistry.get_user("user1")
      original_balance = modified_user.balance

      Challenge.create_users(root_supervisor, ["user1"])

      {:ok, final_user} = Challenge.UserRegistry.get_user("user1")
      assert final_user.balance == original_balance
    end

    test "handles nil and non-string inputs gracefully", %{root_supervisor: root_supervisor} do
      assert :ok = Challenge.create_users(root_supervisor, [nil, 123, :atom, "valid_user"])

      Challenge.UserRegistry.get_user("valid_user")
      |> then(fn {:ok, _} -> :ok end)
    end

    test "returns :ok when all users are invalid", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, [nil, "", 123, :atom])
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user("")
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user(nil)
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user("123")
      assert {:error, :user_not_found} = Challenge.UserRegistry.get_user("atom")
    end
  end

  describe "Challenge.bet/2" do
    setup do
      root_supervisor = TestHelper.start_fresh_challenge()
      user_id = "user1"

      Challenge.create_users(root_supervisor, [user_id])

      params = TestHelper.bet_params(user_id)

      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)

      on_exit(fn -> TestHelper.stop_challenge(root_supervisor) end)

      %{root_supervisor: root_supervisor, user_id: user_id, params: params}
    end

    test "RS_OK(1): processes successful bet", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      params: params
    } do
      Challenge.Gateway.bet(root_supervisor, params, %{
        "X-Hub88-Signature" => TestHelper.valid_signature(params)
      })
      |> then(fn result ->
        assert result.status == "RS_OK"
        assert result.user == user_id
        assert result.balance == 100_000 - 5
        assert result.currency == "USD"
        assert result.request_uuid == params.request_uuid
      end)
    end

    test "RS_ERROR_INVALID_TOKEN(4) for invalid token", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestHelper.bet_params(user_id, %{token: "not_a_real_token"})

      Challenge.Gateway.bet(root_supervisor, params, %{
        "X-Hub88-Signature" => TestHelper.valid_signature(params)
      })
      |> then(&assert &1.status == "RS_ERROR_INVALID_TOKEN")
    end

    test "RS_ERROR_NOT_ENOUGH_MONEY(7) for excessive bet", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      params = TestHelper.bet_params(user_id, %{amount: 1_000_000_000})
      Challenge.UserRegistry.add_token(user_id, params.token)
      headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(params)}

      {:ok, user_before} = Challenge.UserRegistry.get_user(user_id)
      assert user_before.balance == 100_000

      Challenge.Gateway.bet(root_supervisor, params, headers)
      |> then(fn result ->
        assert result.status == "RS_ERROR_NOT_ENOUGH_MONEY"
        assert result.balance == 100_000
      end)

      {:ok, user_after} = Challenge.UserRegistry.get_user(user_id)
      assert user_after.balance == user_before.balance
    end
  end

  describe "Challenge.win/2" do
    setup do
      TestHelper.reset_test_environment()
      root_supervisor = TestHelper.start_fresh_challenge()
      user_id = "user1"
      Challenge.create_users(root_supervisor, [user_id])

      params = TestHelper.bet_params(user_id)
      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)

      on_exit(fn -> TestHelper.stop_challenge(root_supervisor) end)

      %{root_supervisor: root_supervisor, user_id: user_id, bet_params: params}
    end

    test "RS_OK(1) for valid win", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      bet_params: bet_params
    } do
      bet_headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(bet_params)}

      Challenge.Gateway.bet(root_supervisor, bet_params, bet_headers)
      |> then(&assert &1.status == "RS_OK")

      win_params =
        TestHelper.win_params(user_id, bet_params.transaction_uuid, %{
          token: bet_params.token,
          game_code: bet_params.game_code,
          currency: bet_params.currency
        })

      win_headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(win_params)}

      Challenge.Gateway.win(root_supervisor, win_params, win_headers)
      |> then(fn win_result ->
        assert win_result.status == "RS_OK"
        assert win_result.user == user_id
        assert win_result.request_uuid == win_params.request_uuid
        assert win_result.balance == 100_000 - bet_params.amount + win_params.amount
        assert win_result.currency == bet_params.currency
      end)
    end

    test "RS_ERROR_TRANSACTION_DOES_NOT_EXIST(14) for missing reference_transaction_uuid", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      bet_params: bet_params
    } do
      win_params =
        TestHelper.win_params(user_id, "nonexistent_bet_uuid", %{
          token: bet_params.token,
          game_code: bet_params.game_code,
          currency: bet_params.currency
        })

      win_headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(win_params)}

      Challenge.Gateway.win(root_supervisor, win_params, win_headers)
      |> then(fn win_result ->
        assert win_result.status == "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"
        assert win_result.user == user_id
        assert win_result.request_uuid == win_params.request_uuid
      end)
    end

    test "RS_ERROR_TOKEN_EXPIRED(10) does NOT check for token expiry on win", %{
      root_supervisor: root_supervisor,
      user_id: user_id,
      bet_params: bet_params
    } do
      bet_headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(bet_params)}

      Challenge.Gateway.bet(root_supervisor, bet_params, bet_headers)
      |> then(&assert &1.status == "RS_OK")

      win_params =
        TestHelper.win_params(user_id, bet_params.transaction_uuid, %{
          token: "expired",
          game_code: bet_params.game_code,
          currency: bet_params.currency
        })

      win_headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(win_params)}

      Challenge.Gateway.win(root_supervisor, win_params, win_headers)
      |> then(&assert &1.status == "RS_OK")
    end
  end

  describe "Test Utils" do
    test "random_uuid/0" do
      TestHelper.random_uuid()
      |> then(fn uuid ->
        assert is_binary(uuid)
        assert String.length(uuid) == 36
      end)
    end
  end

  describe "bet/2 and win/2 header path" do
    test "bet/2 builds headers and calls Gateway.bet" do
      server = Challenge.start()
      body = %{signature: "sig"}
      Challenge.bet(server, body)
    end

    test "win/2 builds headers and calls Gateway.win" do
      server = Challenge.start()
      body = %{signature: "sig"}
      Challenge.win(server, body)
    end
  end
end
