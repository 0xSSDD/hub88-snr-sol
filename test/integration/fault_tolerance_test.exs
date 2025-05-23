defmodule Integration.FaultToleranceTest do
  use ExUnit.Case, async: false

  setup do
    TestUtils.reset_test_environment()
    supervisor = TestUtils.start_fresh_challenge()

    on_exit(fn ->
      TestUtils.stop_challenge(supervisor)
    end)

    %{root_supervisor: supervisor}
  end

  defp bet(server, params) do
    headers = %{"X-Hub88-Signature" => TestUtils.valid_signature(params)}
    Challenge.Gateway.bet(server, params, headers)
  end

  describe "UserTransactionServer Crash Recovery" do
    test "system recovers from UserTransactionServer crashes", %{root_supervisor: server} do
      user_id = "crash_test_user"
      Challenge.create_users(server, [user_id])
      params = TestUtils.bet_params(user_id)
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
      params2 = TestUtils.bet_params(user_id)
      Challenge.UserRegistry.add_token(user_id, params2.token)
      Challenge.UserRegistry.add_game_code(params2.game_code)
      result2 = bet(server, params2)
      assert result2.status == "RS_OK"
      [{new_pid, _}] = Registry.lookup(Challenge.ProcessRegistry, user_id)
      assert Process.alive?(new_pid)
      assert new_pid != user_pid
    end

  end

end
