defmodule Challenge.ErrorHandler do
  @moduledoc """
  Handles generating error responses for the API.
  """

  @doc """
  Creates a standardized error response.
  """
  def error_response(user_id, error_code, params) do
    %{
      user: user_id,
      status: error_code,
      request_uuid: Map.get(params, :request_uuid, "")
    }
  end
end
