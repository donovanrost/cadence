defmodule CadenceWeb.HealthController do
  use CadenceWeb, :controller

  alias Cadence.Platform.Drain
  alias Ecto.Adapters.SQL

  @moduledoc "Infrastructure probes. Readiness covers HTTP/database access, not mission ownership."

  def show(conn, _params), do: json(conn, %{data: %{status: "ok"}})

  def live(conn, _params), do: json(conn, %{status: "alive"})

  def ready(conn, _params) do
    if Drain.draining?() or draining?() or not database_ready?() do
      conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    else
      json(conn, %{status: "ready"})
    end
  end

  defp draining? do
    case Application.get_env(:cadence_web, :drain_file) do
      path when is_binary(path) -> File.exists?(path)
      nil -> false
    end
  end

  defp database_ready? do
    match?({:ok, _}, SQL.query(Cadence.Repo, "SELECT 1", [], timeout: 1_000))
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end
end
