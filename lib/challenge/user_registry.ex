defmodule Challenge.UserRegistry do
  @moduledoc """
  Manages ETS tables for user data, transactions, tokens, sub-partners, and game codes.

  This GenServer is responsible for:
    - Creating and maintaining ETS tables for high-concurrency, in-memory storage.
    - Providing atomic, race-condition-free operations for user and transaction data.
    - Exposing a simple API for user, transaction, token, sub-partner, and game code management.
    - Enforcing daily request limits per user, 1000 by default.

  ## ETS Tables

    - `:users` — Stores user data (balance, currency, status, etc).
    - `:transactions` — Stores transaction data.
    - `:processed_transactions` — Tracks processed transaction UUIDs for idempotency.
    - `:sub_partners` — Stores sub-partner status.
    - `:tokens` — Stores user tokens for authentication.
    - `:game_codes` — Stores valid game codes.
    - `:user_limits` — Tracks daily request counts per user.

  ## Concurrency

  All ETS tables are created with `:public` access and both read/write concurrency enabled.
  Atomic operations (e.g., balance updates, transaction inserts) are performed via GenServer calls
  to ensure consistency and prevent race conditions.

  ## Usage

  This module is typically started under a supervisor and is intended to be a singleton process.
  """
  use GenServer

  @users_table :users
  @transactions_table :transactions
  @processed_transactions_table :processed_transactions
  @sub_partners_table :sub_partners
  @tokens_table :tokens
  @game_codes_table :game_codes
  @user_limits_table :user_limits

  # Client API
  @doc """
  Starts the UserRegistry GenServer and initializes all ETS tables.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server callbacks
  @impl GenServer
  @doc false
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

    # Add a table for daily request limits
    :ets.new(:user_limits, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    {:ok, []}
  end

  # User operations
  @doc """
  Creates a new user with the given `user_id`, `balance`, and `currency`.

  Returns `{:ok, user_data}` on success, or `{:error, :invalid_user_id}` / `{:error, :user_already_exists}`.
  """
  def create_user(user_id, balance \\ 100_000, currency \\ "USD")

  def create_user(user_id, _balance, _currency) when not is_binary(user_id) or user_id == "" do
    {:error, :invalid_user_id}
  end

  def create_user(user_id, balance, currency) do
    user_data = %{
      balance: balance,
      currency: currency,
      created_at: System.system_time(:millisecond),
      disabled: false
    }

    case :ets.insert_new(@users_table, {user_id, user_data}) do
      true -> {:ok, user_data}
      false -> {:error, :user_already_exists}
    end
  end

  @doc """
  Retrieves user data for the given `user_id`.

  Returns `{:ok, user_data}` or `{:error, :user_not_found}`.
  """
  def get_user(user_id) do
    case :ets.lookup(@users_table, user_id) do
      [{^user_id, user_data}] -> {:ok, user_data}
      [] -> {:error, :user_not_found}
    end
  end

  @doc """
  Retrieves transaction data for the given `transaction_uuid`.

  Returns `{:ok, tx_data}` or `{:error, :transaction_not_found}`.
  """
  def get_transaction(transaction_uuid) do
    case :ets.lookup(@transactions_table, transaction_uuid) do
      [{^transaction_uuid, tx_data}] -> {:ok, tx_data}
      [] -> {:error, :transaction_not_found}
    end
  end

  @doc """
  Atomically updates the balance for the given `user_id` by `amount`.

  Returns `{:ok, updated_user_data}` or an error tuple.
  """
  def update_balance(user_id, amount) do
    try do
      GenServer.call(__MODULE__, {:update_balance, user_id, amount}, 5_000)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
    end
  end

  @impl GenServer
  @doc false
  def handle_call({:update_balance, user_id, amount}, _from, state) do
    result =
      case :ets.lookup(@users_table, user_id) do
        [{^user_id, user_data}] ->
          new_balance = user_data.balance + amount

          # Check for insufficient funds on debit operations
          if new_balance < 0 do
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

  @doc """
  Stores a transaction atomically, ensuring idempotency.

  Returns `{:ok, :new_transaction}` if first time, or `{:ok, :duplicate_transaction}` if already processed.
  """
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

  @doc """
  Checks if a transaction with the given `transaction_uuid` has already been processed.
  """
  def transaction_exists?(transaction_uuid) do
    :ets.member(@processed_transactions_table, transaction_uuid)
  end

  # User management functions
  @doc """
  Disables a user by setting their `:disabled` flag to true.

  Returns `:ok` or `{:error, :user_not_found}`.
  """
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
  @doc """
  Creates a new sub-partner with the given `sub_partner_id`.

  Returns `{:error, :wrong_types}` if invalid, or `true` if created.
  """
  def create_sub_partner(sub_partner_id)
      when not is_binary(sub_partner_id) or sub_partner_id == "" do
    {:error, :wrong_types}
  end

  def create_sub_partner(sub_partner_id) do
    :ets.insert_new(@sub_partners_table, {sub_partner_id, %{disabled: false}})
  end

  @doc """
  Disables a sub-partner by setting their `:disabled` flag to true.

  Returns `:ok` or `{:error, :not_found}`.
  """
  def disable_sub_partner(sub_partner_id) do
    case :ets.lookup(@sub_partners_table, sub_partner_id) do
      [{^sub_partner_id, data}] ->
        :ets.insert(@sub_partners_table, {sub_partner_id, Map.put(data, :disabled, true)})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns `true` if the sub-partner is disabled, otherwise `false`.
  """
  def sub_partner_disabled?(sub_partner_id) do
    case :ets.lookup(@sub_partners_table, sub_partner_id) do
      [{^sub_partner_id, %{disabled: true}}] -> true
      _ -> false
    end
  end

  @doc """
  Returns `true` if the sub-partner is valid (exists and not disabled).
  """
  def valid_sub_partner?(sub_partner_id) do
    case :ets.lookup(@sub_partners_table, sub_partner_id) do
      [{^sub_partner_id, %{disabled: false}}] -> true
      _ -> false
    end
  end

  # Token management
  @doc """
  Adds a token for a user.

  Returns `{:error, :wrong_types}` if arguments are not binaries, otherwise `true`.
  """
  def add_token(user_id, token) when not is_binary(user_id) or not is_binary(token) do
    {:error, :wrong_types}
  end

  def add_token(user_id, token) when is_binary(user_id) and is_binary(token) do
    :ets.insert(@tokens_table, {{user_id, token}, true})
  end

  @doc """
  Returns `true` if the token is valid for the given user, otherwise `false`.
  """
  def valid_token?(user_id, token) when not is_binary(user_id) or not is_binary(token), do: false

  def valid_token?(user_id, token) when is_binary(user_id) and is_binary(token) do
    :ets.member(@tokens_table, {user_id, token})
  end

  # Game code management
  @doc """
  Adds a new game code.
  """
  def add_game_code(game_code) do
    :ets.insert(@game_codes_table, {game_code, true})
  end

  @doc """
  Removes a game code.
  """
  def remove_game_code(game_code) do
    :ets.delete(@game_codes_table, game_code)
  end

  @doc """
  Returns `true` if the game code is valid (exists), otherwise `false`.
  """
  def valid_game_code?(game_code) do
    :ets.member(@game_codes_table, game_code)
  end

  @doc """
  Returns a list of all game codes.
  """
  def list_game_codes do
    :ets.tab2list(@game_codes_table) |> Enum.map(fn {code, _} -> code end)
  end

  # Utility functions
  @doc """
  Deletes all objects from all managed ETS tables.
  """
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
  @doc """
  Returns a map of basic stats: total users, total transactions, and processed transactions.
  """
  def get_stats do
    %{
      total_users: :ets.info(@users_table, :size),
      total_transactions: :ets.info(@transactions_table, :size),
      processed_transactions: :ets.info(@processed_transactions_table, :size)
    }
  end

  @doc """
  Performs a health check on the main ETS tables.

  Returns `:ok` if all tables are accessible, otherwise `{:error, reason}`.
  """
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

  # Configurable daily request limit
  @doc """
  Returns the configured daily request limit per user (default: 1000).
  """
  def get_daily_request_limit do
    Application.get_env(:challenge, :daily_request_limit, 1000)
  end

  # Daily request limit helpers
  @doc """
  Increments the daily request count for a user and returns the new count.
  """
  def increment_user_limit(user_id) do
    today = Date.utc_today()
    key = {user_id, today}
    :ets.update_counter(@user_limits_table, key, {2, 1}, {key, 0})
  end
end
