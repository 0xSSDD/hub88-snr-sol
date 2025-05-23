defmodule Challenge.ErrorHandler do
  @moduledoc """
  Handles generating error responses for the API.
  """

  @doc """
  Creates a standardized error response.
  """
  def error_response(user_id, error_code, params, opts \\ []) do
    base = %{
      user: user_id,
      status: error_code,
      request_uuid: Map.get(params, :request_uuid, "")
    }

    case opts do
      [balance: balance] -> Map.put(base, :balance, balance)
      _ -> base
    end
  end
end
