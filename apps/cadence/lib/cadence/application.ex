defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cadence.Dashboards.DataSources, as: DashboardDataSources
  alias Cadence.IngressArchive
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Telemetry.{CurrentValueStore, RuntimeHealth, Storage}

  @impl true
  def start(_type, _args) do
    children =
      [
        Cadence.Repo,
        {Phoenix.PubSub, name: Cadence.PubSub},
        Cadence.Telemetry.Profiler,
        RuntimeHealth
      ] ++
        ingress_archive_children() ++
        protocol_record_archive_children() ++
        telemetry_backend_children() ++
        dashboard_runtime_cache_children() ++
        dashboard_source_circuit_breaker_children() ++
        dashboard_source_probe_scheduler_children() ++
        [Cadence.Runtime.Supervisor] ++
        command_dispatcher_children() ++
        command_verifier_scheduler_children() ++
        contact_scheduler_global_safety_children() ++ background_job_children()

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

    Cadence.ensure_bootstrap_admin()
  end

  defp maybe_bootstrap_dashboard_data_sources do
    dashboard_data_sources_config = Application.get_env(:cadence, :dashboard_data_sources, [])

    if Keyword.get(dashboard_data_sources_config, :bootstrap_defaults?, false) do
      _ = DashboardDataSources.ensure_default_managed_sources!()
    end

    :ok
  end

  defp contact_scheduler_global_safety_children do
    contact_scheduler_config = Application.get_env(:cadence, :contact_scheduler_global_safety, [])

    if Keyword.get(contact_scheduler_config, :enabled, false) do
      [{Cadence.Contacts.Scheduler, contact_scheduler_config}]
    else
      []
    end
  end

  defp command_dispatcher_children do
    command_dispatcher_config = Application.get_env(:cadence, :command_dispatcher, [])

    if Keyword.get(command_dispatcher_config, :enabled, true) do
      [{Cadence.Commanding.DispatchSupervisor, command_dispatcher_config}]
    else
      []
    end
  end

  defp command_verifier_scheduler_children do
    command_verifier_scheduler_config =
      Application.get_env(:cadence, :command_verifier_scheduler, [])

    if Keyword.get(command_verifier_scheduler_config, :enabled, true) do
      [{Cadence.Commanding.VerifierScheduler, command_verifier_scheduler_config}]
    else
      []
    end
  end

  defp background_job_children do
    if Application.get_env(:cadence, :start_background_jobs, true) do
      [{Cadence.Jobs.Supervisor, Application.get_env(:cadence, :background_jobs, [])}]
    else
      []
    end
  end

  defp telemetry_backend_children do
    [
      CurrentValueStore.child_spec(),
      Storage.child_spec()
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp dashboard_runtime_cache_children do
    runtime_cache_config = Application.get_env(:cadence, :dashboard_runtime_cache, [])

    if Keyword.get(runtime_cache_config, :enabled?, true) do
      [{Cadence.Dashboards.RuntimeCache, runtime_cache_config}]
    else
      []
    end
  end

  defp dashboard_source_circuit_breaker_children do
    circuit_breaker_config = Application.get_env(:cadence, :dashboard_source_circuit_breaker, [])

    if Keyword.get(circuit_breaker_config, :enabled?, false) do
      [{Cadence.Dashboards.SourceCircuitBreaker, circuit_breaker_config}]
    else
      []
    end
  end

  defp dashboard_source_probe_scheduler_children do
    scheduler_config = Application.get_env(:cadence, :dashboard_source_probe_scheduler, [])

    if Keyword.get(scheduler_config, :enabled?, false) do
      [{Cadence.Dashboards.SourceProbeScheduler, scheduler_config}]
    else
      []
    end
  end

  defp ingress_archive_children do
    [IngressArchive.child_spec()]
    |> Enum.reject(&is_nil/1)
  end

  defp protocol_record_archive_children do
    [RecordArchive.child_spec()]
    |> Enum.reject(&is_nil/1)
  end
end
