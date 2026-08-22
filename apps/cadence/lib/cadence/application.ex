defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cadence.Accounts.EnvironmentAdminPolicy
  alias Cadence.Auth
  alias Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs
  alias Cadence.Control.DataSources.TSDBBackendLifecycleJobs
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.Management.DataSources
  alias Cadence.Platform.RootComposition
  alias Cadence.Telemetry.DataManagement

  @impl true
  def start(_type, _args) do
    Cadence.Observability.setup_repo_tracing()
    root_composition = RootComposition.from_application()

    environment_admin_policy =
      :cadence
      |> Application.get_env(:environment_admin, [])
      |> EnvironmentAdminPolicy.from_config()

    control_supervisor_opts =
      :cadence
      |> Application.get_env(:control_supervisor, [])
      |> Keyword.put(:root_composition, root_composition)

    children =
      [
        {Cadence.Platform.Supervisor, root_composition: root_composition},
        Cadence.Management.Supervisor,
        {Cadence.Runtime.Supervisor, root_composition: root_composition},
        {Cadence.Control.Supervisor, control_supervisor_opts},
        {Cadence.Projections.Supervisor, root_composition: root_composition}
      ] ++
        background_job_children(root_composition)

    opts = [strategy: :one_for_one, name: Cadence.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        case initialize_after_start(environment_admin_policy) do
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

  defp initialize_after_start(environment_admin_policy) do
    maybe_bootstrap_data_sources()

    Auth.reconcile_environment_admin(environment_admin_policy)
  end

  defp maybe_bootstrap_data_sources do
    data_sources_config = Application.get_env(:cadence, :data_sources, [])

    if Keyword.get(data_sources_config, :bootstrap_defaults?, false) do
      _ = DataSources.ensure_default_managed_sources!()
    end

    :ok
  end

  defp background_job_children(%RootComposition{} = root_composition) do
    if Application.get_env(:cadence, :start_background_jobs, true) do
      job_runner =
        :cadence
        |> Application.get_env(:job_handlers, %{})
        |> capture_data_source_job_policies()
        |> capture_telemetry_data_management_policy(root_composition.data_management_policy)
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

  defp capture_telemetry_data_management_policy(handlers, policy) do
    case Map.get(handlers, :telemetry_historical_data_workflow) do
      {DataManagement, :execute_enqueued_historical_data_workflow} ->
        Map.put(
          handlers,
          :telemetry_historical_data_workflow,
          DataManagement.handler(policy)
        )

      _custom_or_missing_handler ->
        handlers
    end
  end
end
