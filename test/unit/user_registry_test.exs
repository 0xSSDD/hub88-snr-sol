defmodule Challenge.UserRegistryTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    supervisor = TestUtils.start_fresh_challenge()

    on_exit(fn ->
      TestUtils.stop_challenge(supervisor)
    end)

    %{root_supervisor: supervisor}
  end

  test "create_user/1 creates and fetches a user" do
    assert {:ok, user} = Challenge.UserRegistry.create_user("user1")
    assert user.balance == 100_000
    assert {:ok, user2} = Challenge.UserRegistry.get_user("user1")
    assert user2 == user
  end

  test "create_user/1 returns error for duplicate" do
    Challenge.UserRegistry.create_user("user1")
    assert {:error, :user_already_exists} = Challenge.UserRegistry.create_user("user1")
  end

  test "update_balance/2 updates balance atomically" do
    Challenge.UserRegistry.create_user("user1")
    assert {:ok, user} = Challenge.UserRegistry.update_balance("user1", 50)
    assert user.balance == 100_050
  end

  test "update_balance/2 returns error for insufficient funds" do
    Challenge.UserRegistry.create_user("user1")
    assert {:error, :not_enough_money} = Challenge.UserRegistry.update_balance("user1", -200_000)
    {:ok, user} = Challenge.UserRegistry.get_user("user1")
    assert user.balance == 100_000
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
    assert Challenge.UserRegistry.valid_token?("user1", "token1")
    refute Challenge.UserRegistry.valid_token?("user1", "token2")
  end

  test "add_game_code/1 and valid_game_code?/1" do
    Challenge.UserRegistry.add_game_code("game1")
    assert Challenge.UserRegistry.valid_game_code?("game1")
    refute Challenge.UserRegistry.valid_game_code?("game2")
  end

  test "create_sub_partner/1, disable_sub_partner/1, valid_sub_partner?/1, sub_partner_disabled?/1" do
    Challenge.UserRegistry.create_sub_partner("sub1")
    assert Challenge.UserRegistry.valid_sub_partner?("sub1")
    refute Challenge.UserRegistry.sub_partner_disabled?("sub1")
    Challenge.UserRegistry.disable_sub_partner("sub1")
    refute Challenge.UserRegistry.valid_sub_partner?("sub1")
    assert Challenge.UserRegistry.sub_partner_disabled?("sub1")
  end

  test "disable_user/1 disables user" do
    Challenge.UserRegistry.create_user("user1")
    :ok = Challenge.UserRegistry.disable_user("user1")
    {:ok, user} = Challenge.UserRegistry.get_user("user1")
    assert user.disabled
  end
end
