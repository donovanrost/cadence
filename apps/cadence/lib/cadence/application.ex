defmodule Cadence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cadence.Auth
  alias Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs
  alias Cadence.Control.DataSources.TSDBBackendLifecycleJobs
  alias Cadence.IngressArchive
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.Management.DataSources
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Runtime.{IngressArchiveConsumer, Persistence}
  alias Cadence.Telemetry.{CurrentValueStore, DataManagement, HistoryStore, Storage}
  @impl true
  def start(_type, _args) do
    Cadence.Observability.setup_repo_tracing()
    persistence_policies = capture_persistence_policies()

    children =
      [
        Cadence.Platform.Supervisor,
        Cadence.Management.Supervisor,
        {Cadence.Runtime.Supervisor, runtime_opts(persistence_policies)},
        Cadence.Control.Supervisor,
        Cadence.Projections.Supervisor
      ] ++
        background_job_children(persistence_policies)

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

  defp background_job_children(persistence_policies) do
    if Application.get_env(:cadence, :start_background_jobs, true) do
      job_runner =
        :cadence
        |> Application.get_env(:job_handlers, %{})
        |> capture_data_source_job_policies()
        |> capture_telemetry_data_management_policy(persistence_policies.data_management)
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

  defp capture_persistence_policies do
    current_value_store =
      :cadence
      |> Application.get_env(:telemetry_current_value_store, [])
      |> CurrentValueStore.policy()

    telemetry_storage =
      :cadence
      |> Application.get_env(:telemetry_storage, [])
      |> Storage.policy(current_value_store_policy: current_value_store)

    history_store =
      :cadence
      |> Application.get_env(:telemetry_history_store, [])
      |> HistoryStore.policy(storage_policy: telemetry_storage)

    ingress_archive =
      :cadence
      |> Application.get_env(:ingress_archive, [])
      |> IngressArchive.policy()

    record_archive =
      :cadence
      |> Application.get_env(:protocol_record_archive, [])
      |> RecordArchive.policy()

    %{
      current_value_store: current_value_store,
      telemetry_storage: telemetry_storage,
      history_store: history_store,
      ingress_archive: ingress_archive,
      record_archive: record_archive,
      runtime_persistence: Persistence.policy(ingress_archive, record_archive, telemetry_storage),
      ingress_archive_consumer:
        IngressArchiveConsumer.policy(
          Application.get_env(:cadence, :ingress_archive_consumer, []),
          ingress_archive
        ),
      data_management: DataManagement.policy(telemetry_storage, history_store)
    }
  end

  defp runtime_opts(policies) do
    [
      current_value_store_policy: policies.current_value_store,
      telemetry_storage_policy: policies.telemetry_storage,
      history_store_policy: policies.history_store,
      ingress_archive_policy: policies.ingress_archive,
      record_archive_policy: policies.record_archive,
      persistence_policy: policies.runtime_persistence,
      ingress_archive_consumer_policy: policies.ingress_archive_consumer
    ]
  end
end
