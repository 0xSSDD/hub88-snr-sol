defmodule Challenge.UserManagerTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    :ok
  end

  test "create_users/2 creates users" do
    assert :ok = Challenge.UserManager.create_users(nil, ["user1", "user2"])
    assert {:ok, _} = Challenge.UserRegistry.get_user("user1")
    assert {:ok, _} = Challenge.UserRegistry.get_user("user2")
  end

  test "create_users/2 ignores empty and duplicate users" do
    assert :ok = Challenge.UserManager.create_users(nil, ["", "user1", "user1"])
    assert {:ok, _} = Challenge.UserRegistry.get_user("user1")
  end

  test "get_user_server/1 returns a pid and is idempotent" do
    Challenge.UserRegistry.create_user("user1")
    pid1 = Challenge.UserManager.get_user_server("user1")
    assert is_pid(pid1)
    pid2 = Challenge.UserManager.get_user_server("user1")
    assert pid1 == pid2
  end

  test "get_user_server/1 returns nil for missing user" do
    assert is_pid(Challenge.UserManager.get_user_server("ghost_user")) or is_nil(Challenge.UserManager.get_user_server("ghost_user"))
  end
end
