defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cadence.Auth
  alias Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs
  alias Cadence.Control.DataSources.TSDBBackendLifecycleJobs
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.Management.DataSources
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
        case initialize_after_start() do
          {:ok, _environment_admin} ->
            {:ok, pid}

          {:error, reason} ->
            Supervisor.stop(pid)
            {:error, reason}
        end

      other ->
        other
    end
  end

  defp initialize_after_start do
    maybe_bootstrap_data_sources()

    Auth.reconcile_environment_admin()
  end

  defp maybe_bootstrap_data_sources do
    data_sources_config = Application.get_env(:cadence, :data_sources, [])

    if Keyword.get(data_sources_config, :bootstrap_defaults?, false) do
      _ = DataSources.ensure_default_managed_sources!()
    end

    :ok
  end

  defp background_job_children do
    if Application.get_env(:cadence, :start_background_jobs, true) do
      job_runner =
        :cadence
        |> Application.get_env(:job_handlers, %{})
        |> capture_data_source_job_policies()
        |> JobRunner.new()

      background_job_opts =
        :cadence
        |> Application.get_env(:background_jobs, [])
        |> Keyword.put_new(:runner, job_runner)

      [{Cadence.Jobs.Supervisor, background_job_opts}]
    else
      []
    end
  end

  defp capture_data_source_job_policies(handlers) do
    handlers
    |> capture_data_source_job_policy(
      :managed_questdb_provisioning,
      ManagedQuestDBProvisioningJobs,
      :managed_questdb_provisioning
    )
    |> capture_data_source_job_policy(
      :tsdb_backend_lifecycle,
      TSDBBackendLifecycleJobs,
      :tsdb_backend_lifecycle
    )
  end

  defp capture_data_source_job_policy(handlers, job_type, module, config_key) do
    case Map.get(handlers, job_type) do
      {^module, :execute_enqueued_run} ->
        policy =
          :cadence
          |> Application.get_env(config_key, [])
          |> module.policy()

        Map.put(handlers, job_type, module.handler(policy))

      _custom_or_missing_handler ->
        handlers
    end
  end
end
