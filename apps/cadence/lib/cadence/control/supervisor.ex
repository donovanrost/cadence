defmodule Cadence.Control.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Control.ProcessNamespace
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace

  def child_spec(opts) do
    process_namespace = process_namespace(opts)

    %{
      id: process_namespace.root_supervisor,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts \\ []) do
    process_namespace = process_namespace(opts)
    Supervisor.start_link(__MODULE__, opts, name: process_namespace.root_supervisor)
  end

  @impl true
  def init(opts) do
    process_namespace = process_namespace(opts)
    runtime_process_namespace = runtime_process_namespace(opts)

    children =
      [
        {Registry, keys: :unique, name: process_namespace.registry},
        {DynamicSupervisor,
         strategy: :one_for_one,
         name: process_namespace.mission_supervisor,
         extra_arguments: [
           mission_runtime_opts(opts, process_namespace, runtime_process_namespace)
         ]}
      ] ++
        mission_recovery_children(opts, process_namespace) ++
        fact_consumer_children(opts, process_namespace) ++
        shared_resource_children(opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp mission_recovery_children(opts, process_namespace) do
    if Keyword.get(opts, :start_mission_recovery?, true) do
      [
        {Cadence.Control.MissionRecovery,
         name: process_namespace.mission_recovery, process_namespace: process_namespace}
      ]
    else
      []
    end
  end

  defp fact_consumer_children(opts, process_namespace) do
    if Keyword.get(opts, :start_fact_consumers?, true) do
      [
        {Cadence.Control.ContactFactConsumer, name: process_namespace.contact_fact_consumer},
        {Cadence.Control.RuntimeFactConsumer, name: process_namespace.runtime_fact_consumer}
      ]
    else
      []
    end
  end

  defp shared_resource_children(opts) do
    if Keyword.get(opts, :start_shared_resources?, true) do
      command_dispatcher_children() ++
        command_verifier_scheduler_children() ++
        contact_scheduler_global_safety_children() ++
        provider_reservation_reconciler_children() ++
        provider_event_ingestion_children()
    else
      []
    end
  end

  defp mission_runtime_opts(opts, process_namespace, runtime_process_namespace) do
    opts
    |> Keyword.get(:mission_runtime_opts, [])
    |> Keyword.put(:process_namespace, process_namespace)
    |> Keyword.put(:runtime_process_namespace, runtime_process_namespace)
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end

  defp runtime_process_namespace(opts) do
    Keyword.get_lazy(opts, :runtime_process_namespace, &RuntimeProcessNamespace.default/0)
  end

  defp contact_scheduler_global_safety_children do
    config = Application.get_env(:cadence, :contact_scheduler_global_safety, [])

    if Keyword.get(config, :enabled, false) do
      [{Cadence.Contacts.Scheduler, config}]
    else
      []
    end
  end

  defp provider_reservation_reconciler_children do
    config = Application.get_env(:cadence, :provider_reservation_reconciler, [])

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Contacts.ProviderReservationReconciler, Keyword.delete(config, :enabled)}]
    else
      []
    end
  end

  defp provider_event_ingestion_children do
    config = Application.get_env(:cadence, :provider_event_ingestion, [])

    if Keyword.get(config, :enabled, true) do
      [
        {Cadence.GroundNetworks.ProviderEventIngestionSupervisor,
         Keyword.delete(config, :enabled)}
      ]
    else
      []
    end
  end

  defp command_dispatcher_children do
    config = Application.get_env(:cadence, :command_dispatcher, [])

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Commanding.DispatchSupervisor, config}]
    else
      []
    end
  end

  defp command_verifier_scheduler_children do
    config = Application.get_env(:cadence, :command_verifier_scheduler, [])

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Commanding.VerifierScheduler, config}]
    else
      []
    end
  end
end
