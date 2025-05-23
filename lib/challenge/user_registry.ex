defmodule Challenge.UserRegistry do
  @moduledoc """
  Manages ETS tables for user data and transactions.
  Provides atomic operations for race-condition-free transaction processing.
  """
  use GenServer

  @users_table :users
  @transactions_table :transactions
  @processed_transactions_table :processed_transactions
  @sub_partners_table :sub_partners
  @tokens_table :tokens
  @game_codes_table :game_codes

  # Client API
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server callbacks
  @impl GenServer
  def init([]) do
    # Create ETS tables with optimized concurrency settings
    :ets.new(@users_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@transactions_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@processed_transactions_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@sub_partners_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@tokens_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@game_codes_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    {:ok, []}
  end

  # User operations
  def create_user(user_id, balance \\ 100_000, currency \\ "USD") do
    if is_binary(user_id) and user_id != "" do
      user_data = %{
        balance: balance,
        currency: currency,
        created_at: System.system_time(:millisecond),
        disabled: false
      }

      # Use insert_new for atomic creation (fails if user exists)
      case :ets.insert_new(@users_table, {user_id, user_data}) do
        true -> {:ok, user_data}
        false -> {:error, :user_already_exists}
      end
    else
      {:error, :invalid_user_id}
    end
  end

  def get_user(user_id) do
    case :ets.lookup(@users_table, user_id) do
      [{^user_id, user_data}] -> {:ok, user_data}
      [] -> {:error, :user_not_found}
    end
  end

  def get_transaction(transaction_uuid) do
    case :ets.lookup(@transactions_table, transaction_uuid) do
      [{^transaction_uuid, tx_data}] -> {:ok, tx_data}
      [] -> {:error, :transaction_not_found}
    end
  end

  # Atomic balance update using GenServer for consistency
  def update_balance(user_id, amount) do
    try do
      GenServer.call(__MODULE__, {:update_balance, user_id, amount}, 5_000)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
    end
  end

  @impl GenServer
  def handle_call({:update_balance, user_id, amount}, _from, state) do
    result =
      case :ets.lookup(@users_table, user_id) do
        [{^user_id, user_data}] ->
          new_balance = user_data.balance + amount

          # Check for insufficient funds on debit operations
          if amount < 0 and new_balance < 0 do
            {:error, :not_enough_money}
          else
            # Atomic update
            updated_user_data = %{user_data | balance: new_balance}
            :ets.insert(@users_table, {user_id, updated_user_data})
            {:ok, updated_user_data}
          end

        [] ->
          {:error, :user_not_found}
      end

    {:reply, result, state}
  end

  # UPDATED: Atomic transaction storage that prevents race conditions
  def store_transaction(tx_data) do
    transaction_uuid = tx_data.transaction_uuid

    # Use atomic insert_new to prevent duplicate processing
    case :ets.insert_new(@processed_transactions_table, {transaction_uuid, true}) do
      true ->
        # First time processing this transaction
        :ets.insert(@transactions_table, {transaction_uuid, tx_data})
        {:ok, :new_transaction}

      false ->
        # Transaction already processed by another process
        {:ok, :duplicate_transaction}
    end
  end

  # Transaction existence check (kept for compatibility)
  def transaction_exists?(transaction_uuid) do
    :ets.member(@processed_transactions_table, transaction_uuid)
  end

  # User management functions
  def disable_user(user_id) do
    case :ets.lookup(@users_table, user_id) do
      [{^user_id, user_data}] ->
        :ets.insert(@users_table, {user_id, Map.put(user_data, :disabled, true)})
        :ok

      [] ->
        {:error, :user_not_found}
    end
  end

  # Sub-partner management
  def create_sub_partner(sub_partner_id)
      when is_binary(sub_partner_id) and sub_partner_id != "" do
    :ets.insert_new(@sub_partners_table, {sub_partner_id, %{disabled: false}})
  end

  def disable_sub_partner(sub_partner_id) do
    case :ets.lookup(@sub_partners_table, sub_partner_id) do
      [{^sub_partner_id, data}] ->
        :ets.insert(@sub_partners_table, {sub_partner_id, Map.put(data, :disabled, true)})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  def sub_partner_disabled?(sub_partner_id) do
    case :ets.lookup(@sub_partners_table, sub_partner_id) do
      [{^sub_partner_id, %{disabled: true}}] -> true
      _ -> false
    end
  end

  def valid_sub_partner?(sub_partner_id) do
    case :ets.lookup(@sub_partners_table, sub_partner_id) do
      [{^sub_partner_id, %{disabled: false}}] -> true
      _ -> false
    end
  end

  # Token management
  def add_token(user_id, token) when is_binary(user_id) and is_binary(token) do
    :ets.insert(@tokens_table, {{user_id, token}, true})
  end

  def valid_token?(user_id, token) when is_binary(user_id) and is_binary(token) do
    :ets.member(@tokens_table, {user_id, token})
  end

  # Game code management
  def add_game_code(game_code) do
    :ets.insert(@game_codes_table, {game_code, true})
  end

  def remove_game_code(game_code) do
    :ets.delete(@game_codes_table, game_code)
  end

  def valid_game_code?(game_code) do
    :ets.member(@game_codes_table, game_code)
  end

  def list_game_codes do
    :ets.tab2list(@game_codes_table) |> Enum.map(fn {code, _} -> code end)
  end

  # Utility functions
  def reset_all_tables do
    for table <- [
          @users_table,
          @transactions_table,
          @processed_transactions_table,
          @sub_partners_table,
          @tokens_table,
          @game_codes_table
        ] do
      if :ets.info(table) != :undefined, do: :ets.delete_all_objects(table)
    end
  end

  # Health check and stats
  def get_stats do
    %{
      total_users: :ets.info(@users_table, :size),
      total_transactions: :ets.info(@transactions_table, :size),
      processed_transactions: :ets.info(@processed_transactions_table, :size)
    }
  end

  def health_check do
    try do
      users_ok = :ets.info(@users_table, :size) >= 0
      transactions_ok = :ets.info(@transactions_table, :size) >= 0
      processed_ok = :ets.info(@processed_transactions_table, :size) >= 0

      if users_ok and transactions_ok and processed_ok do
        :ok
      else
        {:error, :tables_not_accessible}
      end
    rescue
      _ -> {:error, :tables_missing}
    end
  end
end
