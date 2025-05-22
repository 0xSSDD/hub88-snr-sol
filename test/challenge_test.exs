defmodule ChallengeTest do
  use ExUnit.Case
  doctest Challenge

  describe "Challenge.start/0" do
    test "returns a  valid server pid" do
      server = Challenge.start()
      assert is_pid(server)
      assert Process.alive?(server)
    end

    test "creates a supervision tree correctly" do
      root_supervisor = Challenge.start()

      # Verify the main supervisor is running: RootSupervisor
      assert is_pid(root_supervisor)

      # Verify Partition and DataSupervisor supervisors are running:
      children = Supervisor.which_children(root_supervisor)
      assert length(children) == 2
      assert List.keyfind(children, Challenge.DataSupervisor, 0)
      assert List.keyfind(children, Challenge.PartitionSupervisor, 0)

      # Verify ETS tables are created:
      tables = :ets.all()
      assert :users in tables
      assert :transactions in tables
      assert :processed_transactions in tables
    end
  end

  describe "Challenge.create_users/2" do
    setup do
      root_supervisor = Challenge.start()
      %{root_supervisor: root_supervisor}
    end

    test "creates a single user correctly", %{root_supervisor: root_supervisor} do
      assert :ok == Challenge.create_users(root_supervisor, ["user1"])

      # Verify user was created in ETS
      {:ok, user_data} = Challenge.UserRegistry.get_user("user1")
      assert user_data.balance == 100_000
      assert user_data.currency == "USD"
      assert is_integer(user_data.created_at)
    end

    test " creates multiple users simultaneously", %{root_supervisor: root_supervisor} do
      users = for i <- 1..10_000, into: [], do: "user_#{i}"
      assert :ok == Challenge.create_users(root_supervisor, users)

      # Verify all users were created in ETS
      for user <- users do
        {:ok, user_data} = Challenge.UserRegistry.get_user(user)
        assert user_data.balance == 100_000
        assert user_data.currency == "USD"
        assert is_integer(user_data.created_at)
      end
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
end
