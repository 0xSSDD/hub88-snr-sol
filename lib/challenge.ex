# lib/challenge.ex
defmodule Challenge do
  @moduledoc """
  Hub88 Operator Wallet API implementation.

  NOTE: The public API matches the required spec:
    - bet(server, body)
    - win(server, body)

  """

  alias Challenge.{UserManager, Gateway}

  @doc """
  Start a linked and isolated supervision tree and return the root server that
  will handle the requests.

  """
  @spec start :: GenServer.server()
  def start do
    case Challenge.Application.start(nil, nil) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      # in case of named supervisor
      {:error, {:already_started, _name, pid}} -> pid
      other -> raise "Unexpected return from Application.start/2: #{inspect(other)}"
    end
  end

  @doc """
  Create non-existing users with currency as "USD" and amount as 100_000.

  It ignores empty binary `""` or if the user already exists.
  """
  @spec create_users(server :: GenServer.server(), users :: [String.t()]) :: :ok
  def create_users(server, users) do
    UserManager.create_users(server, users)
  end

  @doc """
  The same behavior is from `POST /transaction/bet` docs.

  The `body` parameter is the "body" from the docs as a map with keys as atoms.
  The result is the "response" from the docs as a map with keys as atoms.
  """
  @spec bet(server :: GenServer.server(), body :: map) :: map
  def bet(server, body) do
    # For backward compatibility, handle both header and body signature
    headers = %{"X-Hub88-Signature" => Map.get(body, :signature)}
    Gateway.bet(server, body, headers)
  end

  @doc """
  The same behavior is from `POST /transaction/win` docs.

  The `body` parameter is the "body" from the docs as a map with keys as atoms.
  The result is the "response" from the docs as a map with keys as atoms.
  """
  @spec win(server :: GenServer.server(), body :: map) :: map
  def win(server, body) do
    # For backward compatibility, handle both header and body signature
    headers = %{"X-Hub88-Signature" => Map.get(body, :signature)}
    Gateway.win(server, body, headers)
  end
end
