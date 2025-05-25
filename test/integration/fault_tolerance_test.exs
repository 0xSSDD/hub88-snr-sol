defmodule Integration.FaultToleranceTest do
  use ExUnit.Case, async: false

  setup do
    TestHelper.reset_test_environment()
    supervisor = TestHelper.start_fresh_challenge()

    on_exit(fn ->
      TestHelper.stop_challenge(supervisor)
    end)

    %{root_supervisor: supervisor}
  end

  defp bet(server, params) do
    headers = %{"X-Hub88-Signature" => TestHelper.valid_signature(params)}
    Challenge.Gateway.bet(server, params, headers)
  end

  describe "UserTransactionServer Crash Recovery" do
    test "system recovers from UserTransactionServer crashes", %{root_supervisor: server} do
      user_id = "crash_test_user"
      Challenge.create_users(server, [user_id])
      params = TestHelper.bet_params(user_id)
      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)

      # Place a bet to start the process
      result = bet(server, params)
      assert result.status == "RS_OK"

      # Find the user's transaction server
      [{user_pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
      assert Process.alive?(user_pid)

      # Kill the user's transaction server
      Process.exit(user_pid, :kill)
      :timer.sleep(200)
      refute Process.alive?(user_pid)

      # Place another bet (should create a new process)
      params2 = TestHelper.bet_params(user_id)
      Challenge.UserRegistry.add_token(user_id, params2.token)
      Challenge.UserRegistry.add_game_code(params2.game_code)
      result2 = bet(server, params2)
      assert result2.status == "RS_OK"
      [{new_pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
      assert Process.alive?(new_pid)
      assert new_pid != user_pid
    end

    test "system maintains data consistency during process crashes", %{root_supervisor: server} do
      user_id = "consistency_user"
      Challenge.create_users(server, [user_id])

      # Place several bets to establish transaction history
      results =
        for _i <- 1..3 do
          params = TestHelper.bet_params(user_id, %{amount: 10_000})
          Challenge.UserRegistry.add_token(user_id, params.token)
          Challenge.UserRegistry.add_game_code(params.game_code)
          bet(server, params)
        end

      Enum.each(results, &assert(&1.status == "RS_OK"))

      # Verify balance before crash
      {:ok, user_before} = Challenge.UserRegistry.get_user(user_id)
      assert user_before.balance == 100_000 - 3 * 10_000

      # Kill the process
      [{user_pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
      Process.exit(user_pid, :kill)
      :timer.sleep(100)

      # Verify data survived the crash
      {:ok, user_after} = Challenge.UserRegistry.get_user(user_id)
      assert user_after.balance == user_before.balance

      # New transactions should still work
      params = TestHelper.bet_params(user_id, %{amount: 5_000})
      Challenge.UserRegistry.add_token(user_id, params.token)
      Challenge.UserRegistry.add_game_code(params.game_code)
      result = bet(server, params)
      assert result.status == "RS_OK"
      assert result.balance == user_before.balance - 5_000
    end

    test "system handles multiple concurrent crashes gracefully", %{root_supervisor: server} do
      user_ids = for i <- 1..5, do: "crash_user_#{i}"
      Challenge.create_users(server, user_ids)

      # Start processes for all users by placing bets
      Enum.each(user_ids, fn user_id ->
        params = TestHelper.bet_params(user_id, %{amount: 1_000})
        Challenge.UserRegistry.add_token(user_id, params.token)
        Challenge.UserRegistry.add_game_code(params.game_code)
        result = bet(server, params)
        assert result.status == "RS_OK"
      end)

      # Get all pids
      pids =
        Enum.map(user_ids, fn user_id ->
          [{pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
          {user_id, pid}
        end)

      # Kill all processes simultaneously
      Enum.each(pids, fn {_user_id, pid} ->
        Process.exit(pid, :kill)
      end)

      :timer.sleep(300)

      # Verify all processes are dead
      Enum.each(pids, fn {_user_id, pid} ->
        refute Process.alive?(pid)
      end)

      # System should still handle new requests efficiently
      start_time = System.monotonic_time(:millisecond)

      results =
        Enum.map(user_ids, fn user_id ->
          params = TestHelper.bet_params(user_id, %{amount: 2_000})
          Challenge.UserRegistry.add_token(user_id, params.token)
          Challenge.UserRegistry.add_game_code(params.game_code)
          bet(server, params)
        end)

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time

      # All requests should succeed
      Enum.each(results, &assert(&1.status == "RS_OK"))

      # Should handle recovery efficiently (under 1 second for 5 users)
      assert total_time < 1000, "Recovery took #{total_time}ms, expected < 1000ms"

      # Verify final balances are correct
      Enum.each(user_ids, fn user_id ->
        {:ok, user} = Challenge.UserRegistry.get_user(user_id)
        # Initial 100_000 - first bet (1_000) - second bet (2_000) = 97_000
        assert user.balance == 97_000
      end)
    end
  end

  describe "ETS Data Persistence" do
    test "ETS tables survive process crashes and maintain data integrity", %{
      root_supervisor: server
    } do
      user_id = "ets_test_user"
      Challenge.create_users(server, [user_id])

      # Create transaction history
      tx_count = 10

      for _i <- 1..tx_count do
        params = TestHelper.bet_params(user_id, %{amount: 1_000})
        Challenge.UserRegistry.add_token(user_id, params.token)
        Challenge.UserRegistry.add_game_code(params.game_code)
        result = bet(server, params)
        assert result.status == "RS_OK"
      end

      # Kill the user's transaction server
      [{user_pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
      Process.exit(user_pid, :kill)
      :timer.sleep(100)

      # ETS data should still be accessible directly
      {:ok, user} = Challenge.UserRegistry.get_user(user_id)
      assert user.balance == 100_000 - tx_count * 1_000

      # Transaction history should be preserved
      stats = Challenge.UserRegistry.get_stats()
      assert stats.total_transactions >= tx_count
      assert stats.processed_transactions >= tx_count
    end
  end

  describe "Performance Under Stress" do
    test "system maintains performance after multiple failures", %{root_supervisor: server} do
      # Create users and establish baseline
      user_count = 20
      user_ids = for i <- 1..user_count, do: "perf_user_#{i}"
      Challenge.create_users(server, user_ids)

      # Establish processes and create some failures
      # Every other user
      Enum.take_every(user_ids, 2)
      |> Enum.each(fn user_id ->
        params = TestHelper.bet_params(user_id)
        Challenge.UserRegistry.add_token(user_id, params.token)
        Challenge.UserRegistry.add_game_code(params.game_code)
        bet(server, params)

        # Kill half the processes to simulate failures
        [{pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
        Process.exit(pid, :kill)
      end)

      :timer.sleep(200)

      # Now measure performance with concurrent requests to all users
      start_time = System.monotonic_time(:millisecond)

      tasks =
        Enum.map(user_ids, fn user_id ->
          Task.async(fn ->
            params = TestHelper.bet_params(user_id, %{amount: 5_000})
            Challenge.UserRegistry.add_token(user_id, params.token)
            Challenge.UserRegistry.add_game_code(params.game_code)
            bet(server, params)
          end)
        end)

      results = Task.await_many(tasks, 5_000)
      end_time = System.monotonic_time(:millisecond)

      # All should succeed despite previous failures
      Enum.each(results, &assert(&1.status == "RS_OK"))

      # Performance should be reasonable (under 2 seconds for 20 concurrent requests)
      total_time = end_time - start_time

      assert total_time < 2000,
             "Performance degraded: #{total_time}ms for #{user_count} concurrent requests"

      # Average response time should be reasonable
      avg_time = total_time / user_count
      assert avg_time < 100, "Average response time too high: #{avg_time}ms per request"
    end
  end
end
