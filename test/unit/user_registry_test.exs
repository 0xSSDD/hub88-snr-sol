defmodule Challenge.UserRegistryTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    |> then(fn _ ->
      supervisor = TestUtils.start_fresh_challenge()
      on_exit(fn -> TestUtils.stop_challenge(supervisor) end)
      %{root_supervisor: supervisor}
    end)
  end

  test "create_user/1 creates and fetches a user" do
    "user1"
    |> Challenge.UserRegistry.create_user()
    |> then(fn {:ok, user} ->
      assert user.balance == 100_000
      assert {:ok, user2} = Challenge.UserRegistry.get_user("user1")
      assert user2 == user
    end)
  end

  test "create_user/1 returns error for duplicate" do
    "user1"
    |> tap(&Challenge.UserRegistry.create_user/1)
    |> then(&assert {:error, :user_already_exists} = Challenge.UserRegistry.create_user(&1))
  end

  test "update_balance/2 updates balance atomically" do
    "user1"
    |> tap(&Challenge.UserRegistry.create_user/1)
    |> then(&Challenge.UserRegistry.update_balance(&1, 50))
    |> then(fn {:ok, user} -> assert user.balance == 100_050 end)
  end

  test "update_balance/2 returns error for insufficient funds" do
    "user1"
    |> tap(&Challenge.UserRegistry.create_user/1)
    |> then(
      &assert {:error, :not_enough_money} = Challenge.UserRegistry.update_balance(&1, -200_000)
    )
    |> then(fn _ ->
      {:ok, user} = Challenge.UserRegistry.get_user("user1")
      assert user.balance == 100_000
    end)
  end

  test "store_transaction/1 is idempotent" do
    tx = %{transaction_uuid: "tx1", user: "user1"}
    assert {:ok, :new_transaction} = Challenge.UserRegistry.store_transaction(tx)
    assert {:ok, :duplicate_transaction} = Challenge.UserRegistry.store_transaction(tx)
  end

  test "get_transaction/1 returns error for missing tx" do
    assert {:error, :transaction_not_found} = Challenge.UserRegistry.get_transaction("missing")
  end

  test "get_transaction/1 returns error for nil transaction_uuid" do
    assert {:error, :transaction_not_found} = Challenge.UserRegistry.get_transaction(nil)
  end

  test "increment_user_limit/1 and get_daily_request_limit/0" do
    user_id = "user1"
    today = Date.utc_today()
    _key = {user_id, today}
    assert Challenge.UserRegistry.increment_user_limit(user_id) == 1
    assert Challenge.UserRegistry.increment_user_limit(user_id) == 2
    assert Challenge.UserRegistry.get_daily_request_limit() == 1000
  end

  test "add_token/2 and valid_token?/2" do
    Challenge.UserRegistry.add_token("user1", "token1")
    |> then(fn _ ->
      assert Challenge.UserRegistry.valid_token?("user1", "token1")
      refute Challenge.UserRegistry.valid_token?("user1", "token2")
    end)
  end

  test "add_token/2 returns error for non-binary user_id or token" do
    assert {:error, :wrong_types} = Challenge.UserRegistry.add_token(123, "token1")
    assert {:error, :wrong_types} = Challenge.UserRegistry.add_token("user1", 123)
    assert {:error, :wrong_types} = Challenge.UserRegistry.add_token(:atom, :atom)
  end

  test "valid_token?/2 returns false for non-binary user_id or token" do
    refute Challenge.UserRegistry.valid_token?(123, "token1")
    refute Challenge.UserRegistry.valid_token?("user1", 123)
    refute Challenge.UserRegistry.valid_token?(:atom, :atom)
  end

  test "add_game_code/1 and valid_game_code?/1" do
    Challenge.UserRegistry.add_game_code("game1")
    |> then(fn _ ->
      assert Challenge.UserRegistry.valid_game_code?("game1")
      refute Challenge.UserRegistry.valid_game_code?("game2")
    end)
  end

  test "create_sub_partner/1, disable_sub_partner/1, valid_sub_partner?/1, sub_partner_disabled?/1" do
    "sub1"
    |> tap(&Challenge.UserRegistry.create_sub_partner/1)
    |> then(fn sub_id ->
      assert Challenge.UserRegistry.valid_sub_partner?(sub_id)
      refute Challenge.UserRegistry.sub_partner_disabled?(sub_id)
      Challenge.UserRegistry.disable_sub_partner(sub_id)
      refute Challenge.UserRegistry.valid_sub_partner?(sub_id)
      assert Challenge.UserRegistry.sub_partner_disabled?(sub_id)
    end)
  end

  test "disable_user/1 disables user" do
    "user1"
    |> tap(&Challenge.UserRegistry.create_user/1)
    |> then(&Challenge.UserRegistry.disable_user/1)
    |> then(fn :ok ->
      {:ok, user} = Challenge.UserRegistry.get_user("user1")
      assert user.disabled
    end)
  end

  test "create_user returns error for invalid user_id" do
    assert {:error, :invalid_user_id} = Challenge.UserRegistry.create_user(nil)
    assert {:error, :invalid_user_id} = Challenge.UserRegistry.create_user("")
  end

  test "add_token returns error for invalid types" do
    assert {:error, :wrong_types} = Challenge.UserRegistry.add_token(123, "token")
    assert {:error, :wrong_types} = Challenge.UserRegistry.add_token("user", 123)
  end

  test "valid_token? returns false for invalid types" do
    refute Challenge.UserRegistry.valid_token?(123, "token")
    refute Challenge.UserRegistry.valid_token?("user", 123)
  end

  test "create_sub_partner returns error for invalid id" do
    assert {:error, :wrong_types} = Challenge.UserRegistry.create_sub_partner(nil)
    assert {:error, :wrong_types} = Challenge.UserRegistry.create_sub_partner("")
  end

  test "disable_user returns error for non-existent user" do
    assert {:error, :user_not_found} = Challenge.UserRegistry.disable_user("no_such_user")
  end

  test "disable_sub_partner returns error for non-existent sub-partner" do
    assert {:error, :not_found} = Challenge.UserRegistry.disable_sub_partner("no_such_partner")
  end

  test "remove_game_code and list_game_codes" do
    Challenge.UserRegistry.add_game_code("game1")

    Challenge.UserRegistry.add_game_code("game2")
    |> then(fn _ ->
      assert Enum.sort(Challenge.UserRegistry.list_game_codes()) == ["game1", "game2"]
      Challenge.UserRegistry.remove_game_code("game1")
      assert Challenge.UserRegistry.list_game_codes() == ["game2"]
    end)
  end

  test "transaction_exists? returns false for missing, true for present" do
    refute Challenge.UserRegistry.transaction_exists?("tx1")

    Challenge.UserRegistry.store_transaction(%{transaction_uuid: "tx1"})
    |> then(fn _ -> assert Challenge.UserRegistry.transaction_exists?("tx1") end)
  end

  test "health_check returns :ok" do
    assert :ok = Challenge.UserRegistry.health_check()
  end
end
