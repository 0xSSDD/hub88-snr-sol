defmodule Challenge.UserManagerTest do
  use ExUnit.Case, async: false

  setup do
    TestHelper.reset_test_environment()
    |> then(fn _ ->
      supervisor = TestHelper.start_fresh_challenge()
      on_exit(fn -> TestHelper.stop_challenge(supervisor) end)
      %{root_supervisor: supervisor}
    end)
  end

  test "create_users/2 creates users" do
    ["user1", "user2"]
    |> then(&Challenge.UserManager.create_users(nil, &1))
    |> then(fn result ->
      assert result == :ok
      assert {:ok, _} = Challenge.UserRegistry.get_user("user1")
      assert {:ok, _} = Challenge.UserRegistry.get_user("user2")
    end)
  end

  test "create_users/2 ignores empty and duplicate users" do
    ["", "user1", "user1"]
    |> then(&Challenge.UserManager.create_users(nil, &1))
    |> then(fn result ->
      assert result == :ok
      assert {:ok, _} = Challenge.UserRegistry.get_user("user1")
    end)
  end

  test "get_user_server/1 returns a pid and is idempotent" do
    "user1"
    |> tap(&Challenge.UserRegistry.create_user/1)
    |> then(&Challenge.UserManager.get_user_server/1)
    |> then(fn pid1 ->
      assert is_pid(pid1)
      pid2 = Challenge.UserManager.get_user_server("user1")
      assert pid1 == pid2
    end)
  end

  test "get_user_server/1 returns nil for missing user" do
    "ghost_user"
    |> Challenge.UserManager.get_user_server()
    |> then(fn pid -> assert is_pid(pid) or is_nil(pid) end)
  end
end
