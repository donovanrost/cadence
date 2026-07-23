defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cadence.Auth
  alias Cadence.Dashboards.DataSources, as: DashboardDataSources
  @impl true
  def start(_type, _args) do
    Cadence.Observability.setup_repo_tracing()

    children =
      [
        Cadence.Platform.Supervisor,
        Cadence.Management.Supervisor,
        Cadence.Runtime.Supervisor,
        Cadence.Control.Supervisor,
        Cadence.Projections.Supervisor
      ] ++
        background_job_children()

    opts = [strategy: :one_for_one, name: Cadence.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        case bootstrap_after_start() do
          {:ok, _user} ->
            {:ok, pid}

          {:error, :bootstrap_admin_disabled} ->
            {:ok, pid}

          {:error, reason} ->
            Supervisor.stop(pid)
            {:error, reason}
        end

      other ->
        other
    end
  end

  defp bootstrap_after_start do
    maybe_bootstrap_dashboard_data_sources()

    Auth.ensure_bootstrap_admin()
  end

  defp maybe_bootstrap_dashboard_data_sources do
    dashboard_data_sources_config = Application.get_env(:cadence, :dashboard_data_sources, [])

    if Keyword.get(dashboard_data_sources_config, :bootstrap_defaults?, false) do
      _ = DashboardDataSources.ensure_default_managed_sources!()
    end

    :ok
  end

  defp background_job_children do
    if Application.get_env(:cadence, :start_background_jobs, true) do
      [{Cadence.Jobs.Supervisor, Application.get_env(:cadence, :background_jobs, [])}]
    else
      []
    end
  end
end
