defmodule ChallengeTest do
  use ExUnit.Case
  doctest Challenge

  describe "Challenge.start/0" do
    test "returns a valid server pid" do
      Challenge.start()
      |> then(fn server ->
        assert is_pid(server)
        assert Process.alive?(server)
        server
      end)
    end

    test "creates a supervision tree correctly" do
      Challenge.start()
      |> tap(fn root_supervisor ->
        # Verify the main supervisor is running
        assert is_pid(root_supervisor)
      end)
      |> Supervisor.which_children()
      |> tap(fn children ->
        # Verify supervisors are running
        assert length(children) == 2
        assert List.keyfind(children, Challenge.DataSupervisor, 0)
        assert List.keyfind(children, Challenge.PartitionSupervisor, 0)
      end)

      # Verify ETS tables exist
      :ets.all()
      |> tap(fn tables ->
        assert :users in tables
        assert :transactions in tables
        assert :processed_transactions in tables
      end)
    end
  end

  describe "Challenge.create_users/2" do
    setup do
      Challenge.start()
      |> then(&%{root_supervisor: &1})
    end

    test "creates a single user correctly", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, ["user1"])

      # Verify user was created in ETS
      "user1"
      |> Challenge.UserRegistry.get_user()
      |> then(fn {:ok, user_data} ->
        assert user_data.balance == 100_000
        assert user_data.currency == "USD"
        assert is_integer(user_data.created_at)
      end)
    end

    test "creates multiple users simultaneously", %{root_supervisor: root_supervisor} do
      1..10_000
      |> Enum.map(&"user_#{&1}")
      |> then(&Challenge.create_users(root_supervisor, &1))
      |> then(fn result -> assert :ok == result end)

      # Verify all users were created in ETS
      1..10_000
      |> Enum.map(&"user_#{&1}")
      |> Enum.each(fn user ->
        user
        |> Challenge.UserRegistry.get_user()
        |> then(fn {:ok, user_data} ->
          assert user_data.balance == 100_000
          assert user_data.currency == "USD"
          assert is_integer(user_data.created_at)
        end)
      end)
    end

    test "ignores empty string", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, [""])
      assert :ok == Challenge.create_users(root_supervisor, [""])
    end

    test "ignores existing users", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, ["user1"])

      # Modify user balance manually
      Challenge.UserRegistry.update_balance("user1", -1_000_000)
      {:ok, modified_user} = Challenge.UserRegistry.get_user("user1") |> dbg()
      original_balance = modified_user.balance

      # Try to create the same user again
      Challenge.create_users(root_supervisor, ["user1"])

      # Verify balance wasn't reset
      {:ok, final_user} = Challenge.UserRegistry.get_user("user1") |> dbg()
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
      root_supervisor = Challenge.start()
      Challenge.create_users(root_supervisor, ["user1"])
      %{root_supervisor: root_supervisor, user_id: "user1"}
    end

    test "RS_OK: processes successful bet", %{root_supervisor: root_supervisor, user_id: user_id} do
      params = TestUtils.bet_params(user_id)
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}

      result = Challenge.Gateway.bet(root_supervisor, params, headers)

      assert result.status == "RS_OK"
      assert result.user == user_id
      assert result.balance == 100_000 - 5
      assert result.currency == "USD"
      assert result.request_uuid == params.request_uuid
    end
    # todo RS_OK: processes successful win

    # todo come back to this
    test "RS_ERROR_UNKNOWN for non-existent user", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      "ghost_user"
      |> TestUtils.bet_params()
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_UNKNOWN" end)
    end

    test "RS_ERROR_INVALID_PARTNER for disabled sub_partner_id", %{root_supervisor: root_supervisor, user_id: user_id} do
      # Create and disable a sub-partner
      Challenge.UserRegistry.create_sub_partner("sub_disabled")
      Challenge.UserRegistry.disable_sub_partner("sub_disabled")

      params = TestUtils.bet_params(user_id, %{sub_partner_id: "sub_disabled"})
      headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}

      result = Challenge.Gateway.bet(root_supervisor, params, headers)
      assert result.status == "RS_ERROR_INVALID_PARTNER"
    end

    test "RS_ERROR_INVALID_TOKEN for invalid token", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      "user1"
      |> TestUtils.bet_params(%{token: nil})
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_INVALID_TOKEN" end)
    end

    test "RS_ERROR_INVALID_GAME for invalid game_code", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      "user1"
      |> TestUtils.bet_params(%{game_code: "ont_whitejackclassic"})
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_INVALID_GAME" end)
    end

    test "RS_ERROR_WRONG_CURRENCY for currency mismatch", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      "user1"
      |> TestUtils.bet_params(%{currency: "EUR"})
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_WRONG_CURRENCY" end)
    end

    test "RS_ERROR_WRONG_TYPES for a random currency", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      "user1"
      |> TestUtils.bet_params(%{currency: "DOG"})
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_WRONG_TYPES" end)
    end

    test "RS_ERROR_NOT_ENOUGH_MONEY for excessive bet", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      "user1"
      |> TestUtils.bet_params(%{amount: 1_000_000_000})
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_NOT_ENOUGH_MONEY" end)
    end

    test "RS_ERROR_USER_DISABLED for disabled user", %{
      root_supervisor: root_supervisor,
      user_id: user_id
    } do
      :ok = Challenge.UserRegistry.disable_user("user1")

      "user1"
      |> TestUtils.bet_params()
      |> then(fn params -> Challenge.bet(root_supervisor, params) end)
      |> then(fn result -> assert result.status == "RS_ERROR_USER_DISABLED" end)
    end

    test "RS_ERROR_TOKEN_EXPIRED for expired token", %{root_supervisor: root_supervisor} do
      "user1"
      |> TestUtils.bet_params(%{token: "expired"})
      |> Challenge.bet(root_supervisor)
      |> then(fn result -> assert result.status == "RS_ERROR_TOKEN_EXPIRED" end)
    end

    test "RS_ERROR_WRONG_SYNTAX for missing required fields", %{root_supervisor: root_supervisor} do
      "user1"
      |> TestUtils.bet_params()
      |> Map.drop([:transaction_uuid])
      |> Challenge.bet(root_supervisor)
      |> then(fn result -> assert result.status == "RS_ERROR_WRONG_SYNTAX" end)
    end

    test "RS_ERROR_WRONG_TYPES for wrong amount type", %{root_supervisor: root_supervisor} do
      "user1"
      |> TestUtils.bet_params(%{amount: "not_an_integer"})
      |> Challenge.bet(root_supervisor)
      |> then(fn result -> assert result.status == "RS_ERROR_WRONG_TYPES" end)
    end

    test "RS_ERROR_DUPLICATE_TRANSACTION for same UUID, different params", %{
      root_supervisor: root_supervisor
    } do
      "user1"
      |> TestUtils.bet_params(%{amount: 5})
      |> then(fn params1 ->
        Challenge.bet(root_supervisor, params1)

        %{params1 | amount: 10}
        |> Challenge.bet(root_supervisor)
        |> then(fn result -> assert result.status == "RS_ERROR_DUPLICATE_TRANSACTION" end)
      end)
    end

    test "RS_ERROR_LIMIT_REACHED for rate limit", %{root_supervisor: root_supervisor} do
      # Simulate rate limit in handler
      "user1"
      |> TestUtils.bet_params()
      |> tap(fn _params ->
        # You'd need to implement rate limiting logic in your handler for this to work
        # result = Challenge.bet(server, params)
        # assert result.status == "RS_ERROR_LIMIT_REACHED"
        :ok
      end)
    end
  end

  # describe "Challenge.win/2 status codes and edge cases" do
  #   test "RS_OK for valid win", %{server: server} do
  #     bet = bet_params("user2")
  #     Challenge.bet(server, bet)
  #     win = win_params("user2", bet.transaction_uuid)
  #     result = Challenge.win(server, win)
  #     assert result.status == "RS_OK"
  #     assert result.request_uuid == win.request_uuid
  #   end

  #   test "RS_ERROR_TRANSACTION_DOES_NOT_EXIST for missing reference_transaction_uuid", %{
  #     server: server
  #   } do
  #     win = win_params("user2", "nonexistent_tx")
  #     result = Challenge.win(server, win)
  #     assert result.status == "RS_ERROR_TRANSACTION_DOES_NOT_EXIST"
  #   end
  # end

  describe " Test Utils" do
    test "random_uuid/0" do
      TestUtils.random_uuid()
      |> then(fn uuid ->
        assert is_binary(uuid)
        assert String.length(uuid) == 36
      end)
    end
  end
end
