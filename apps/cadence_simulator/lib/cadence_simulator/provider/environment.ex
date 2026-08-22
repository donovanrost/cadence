defmodule CadenceSimulator.Provider.Environment do
  @moduledoc false

  import Plug.Conn

  alias CadenceSimulator.Provider

  @header "x-simulator-environment-ref"

  @spec resolve(Plug.Conn.t()) :: {:ok, map()} | {:error, :missing | :not_found}
  def resolve(conn) do
    case get_req_header(conn, @header) do
      [environment_ref] when environment_ref != "" ->
        case Provider.fetch_run(environment_ref) do
          {:ok, run} -> {:ok, run}
          {:error, :not_found} -> {:error, :not_found}
        end

      _other ->
        {:error, :missing}
    end
  end
end
