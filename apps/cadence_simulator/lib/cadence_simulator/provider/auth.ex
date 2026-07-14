defmodule CadenceSimulator.Provider.Auth do
  @moduledoc false

  import Plug.Conn

  alias CadenceSimulator.Provider.Contract

  @spec authenticate(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  def authenticate(conn, config_key) when is_atom(config_key) do
    expected_token = Application.get_env(:cadence_simulator, config_key)

    if authorized?(conn, expected_token) do
      conn
    else
      conn
      |> Contract.error(401, "authentication_failed", "a valid bearer token is required")
      |> halt()
    end
  end

  @spec authorized?(Plug.Conn.t(), binary() | nil) :: boolean()
  def authorized?(_conn, expected_token) when expected_token in [nil, ""], do: true

  def authorized?(conn, expected_token) when is_binary(expected_token) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> supplied_token] -> secure_compare(supplied_token, expected_token)
      _other -> false
    end
  end

  @spec validate_configuration!(boolean(), boolean(), binary() | nil, binary() | nil) :: :ok
  def validate_configuration!(enabled?, required?, admin_token, provider_token) do
    if enabled? and required? and
         (missing_token?(admin_token) or missing_token?(provider_token)) do
      raise ArgumentError,
            "simulator admin and provider API tokens are required when HTTP is enabled"
    end

    :ok
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_left, _right), do: false

  defp missing_token?(token), do: not (is_binary(token) and token != "")
end
