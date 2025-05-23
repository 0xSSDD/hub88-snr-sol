defmodule Challenge.UserRegistry do
  @moduledoc """
  Manages ETS tables for user data and transactions.
  """
  use GenServer

  @users_table :users
  @transactions_table :transactions
  @processed_transactions_table :processed_transactions
  @sub_partners_table :sub_partners
  @tokens_table :tokens

  # Client API
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server callbacks
  @impl GenServer
  def init([]) do
    # Create ETS tables
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

    {:ok, []}
  end

  # User data functions
  # TODO: Check the default balance and currency
  def create_user(user_id, balance \\ 100_000, currency \\ "USD") do
    if is_binary(user_id) and user_id != "" do
      :ets.insert_new(
        @users_table,
        {user_id,
         %{
           balance: balance,
           currency: currency,
           created_at: System.system_time(:millisecond),
           disabled: false
         }}
      )
    else
      # TODO: Not sure if this is the best way to handle this
      false
    end
  end

  def get_transaction(transaction_uuid) do
    case :ets.lookup(@transactions_table, transaction_uuid) do
      [{^transaction_uuid, tx_data}] -> {:ok, tx_data}
      [] -> {:error, :transaction_not_found}
    end
  end

  def get_user(user_id) do
    # TODO: what does the ^ do here?
    case :ets.lookup(@users_table, user_id) do
      [{^user_id, user_data}] -> {:ok, user_data}
      [] -> {:error, :user_not_found}
    end
  end

  @impl true
  def handle_call({:update_balance, user_id, amount}, _from, state) do
    result =
      case :ets.lookup(@users_table, user_id) do
        [{^user_id, user_data}] ->
          new_balance = user_data.balance + amount

          if amount < 0 and new_balance < 0 do
            {:error, :not_enough_money}
          else
            new_user_data = %{user_data | balance: new_balance}
            :ets.insert(@users_table, {user_id, new_user_data})
            {:ok, new_user_data}
          end

        [] ->
          {:error, :user_not_found}
      end

    {:reply, result, state}
  end

  # Transaction functions
  def transaction_exists?(transaction_uuid) do
    :ets.member(@processed_transactions_table, transaction_uuid)
  end

  def store_transaction(tx_data) do
    transaction_uuid = tx_data.transaction_uuid
    :ets.insert(@transactions_table, {transaction_uuid, tx_data})
    :ets.insert(@processed_transactions_table, {transaction_uuid, true})
    :ok
  end

  def update_balance(user_id, amount) do
    try do
      # TODO what does lock pattern mean here?
      # Lock pattern using gen_server call for atomicity
      GenServer.call(__MODULE__, {:update_balance, user_id, amount})
    catch
      :exit, _ -> {:error, :timeout}
    end
  end

  def disable_user(user_id) do
    case :ets.lookup(@users_table, user_id) do
      [{^user_id, user_data}] ->
        :ets.insert(@users_table, {user_id, Map.put(user_data, :disabled, true)})
        :ok

      [] ->
        {:error, :user_not_found}
    end
  end

  def create_sub_partner(sub_partner_id)
      when is_binary(sub_partner_id) and sub_partner_id != "" do
    :ets.insert_new(:sub_partners, {sub_partner_id, %{disabled: false}})
  end

  def disable_sub_partner(sub_partner_id) do
    case :ets.lookup(:sub_partners, sub_partner_id) do
      [{^sub_partner_id, data}] ->
        :ets.insert(:sub_partners, {sub_partner_id, Map.put(data, :disabled, true)})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  def sub_partner_disabled?(sub_partner_id) do
    case :ets.lookup(:sub_partners, sub_partner_id) do
      [{^sub_partner_id, %{disabled: true}}] -> true
      _ -> false
    end
  end

  def valid_sub_partner?(sub_partner_id) do
    case :ets.lookup(:sub_partners, sub_partner_id) do
      [{^sub_partner_id, %{disabled: false}}] -> true
      _ -> false
    end
  end

  def add_token(user_id, token) when is_binary(user_id) and is_binary(token) do
    :ets.insert(@tokens_table, {{user_id, token}, true})
  end

  def valid_token?(user_id, token) when is_binary(user_id) and is_binary(token) do
    :ets.member(@tokens_table, {user_id, token})
  end
end
