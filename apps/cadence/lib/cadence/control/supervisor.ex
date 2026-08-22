defmodule Cadence.Control.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Control.ProcessNamespace
  alias Cadence.Platform.RootComposition
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace

  def child_spec(opts) do
    composition = root_composition(opts)
    process_namespace = process_namespace(opts, composition)

    %{
      id: process_namespace.root_supervisor,
      start: {__MODULE__, :start_link, [Keyword.put(opts, :root_composition, composition)]},
      type: :supervisor
    }
  end

  def start_link(opts \\ []) do
    composition = root_composition(opts)
    opts = Keyword.put(opts, :root_composition, composition)
    process_namespace = process_namespace(opts, composition)
    Supervisor.start_link(__MODULE__, opts, name: process_namespace.root_supervisor)
  end

  @impl true
  def init(opts) do
    composition = root_composition(opts)
    process_namespace = process_namespace(opts, composition)
    runtime_process_namespace = runtime_process_namespace(opts, composition)

    children =
      [
        {Registry, keys: :unique, name: process_namespace.registry},
        {DynamicSupervisor,
         strategy: :one_for_one,
         name: process_namespace.mission_supervisor,
         extra_arguments: [
           mission_runtime_opts(
             opts,
             process_namespace,
             runtime_process_namespace,
             composition
           )
         ]}
      ] ++
        mission_recovery_children(opts, process_namespace) ++
        fact_consumer_children(opts, process_namespace, composition) ++
        shared_resource_children(opts, composition)

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

  defp fact_consumer_children(opts, process_namespace, composition) do
    if Keyword.get(opts, :start_fact_consumers?, true) do
      [
        {Cadence.Control.ContactFactConsumer,
         composition.control_contact_fact_consumer_opts
         |> Keyword.put(:name, process_namespace.contact_fact_consumer)
         |> Keyword.put(:event_bus, composition.event_bus)},
        {Cadence.Control.RuntimeFactConsumer,
         composition.control_runtime_fact_consumer_opts
         |> Keyword.put(:name, process_namespace.runtime_fact_consumer)
         |> Keyword.put(:event_bus, composition.event_bus)}
      ]
    else
      []
    end
  end

  defp shared_resource_children(opts, composition) do
    if Keyword.get(opts, :start_shared_resources?, true) do
      command_dispatcher_children(composition) ++
        command_verifier_scheduler_children(composition) ++
        contact_scheduler_global_safety_children(composition) ++
        provider_reservation_reconciler_children(composition) ++
        provider_event_ingestion_children(composition)
    else
      []
    end
  end

  defp mission_runtime_opts(
         opts,
         process_namespace,
         runtime_process_namespace,
         %RootComposition{} = composition
       ) do
    mission_runtime_opts = Keyword.get(opts, :mission_runtime_opts, [])

    contact_scheduler_opts = Keyword.delete(composition.contact_scheduler_config, :enabled)

    mission_runtime_opts
    |> Keyword.put(
      :start_contact_scheduler?,
      Keyword.get(composition.contact_scheduler_config, :enabled, true) == true
    )
    |> Keyword.put(:contact_scheduler_opts, contact_scheduler_opts)
    |> Keyword.put(:process_namespace, process_namespace)
    |> Keyword.put(:runtime_process_namespace, runtime_process_namespace)
  end

  defp process_namespace(_opts, %RootComposition{} = composition),
    do: composition.control_process_namespace

  defp runtime_process_namespace(_opts, %RootComposition{} = composition),
    do: composition.runtime_process_namespace

  defp contact_scheduler_global_safety_children(%RootComposition{} = composition) do
    config = composition.contact_scheduler_global_safety_config

    if Keyword.get(config, :enabled, false) do
      [{Cadence.Contacts.Scheduler, config}]
    else
      []
    end
  end

  defp provider_reservation_reconciler_children(%RootComposition{} = composition) do
    config = composition.provider_reservation_reconciler_config

    if Keyword.get(config, :enabled, true) do
      [{Cadence.Contacts.ProviderReservationReconciler, Keyword.delete(config, :enabled)}]
    else
      []
    end
  end

  defp provider_event_ingestion_children(%RootComposition{} = composition) do
    config = composition.provider_event_ingestion_config

    if Keyword.get(config, :enabled, true) do
      [
        {Cadence.GroundNetworks.ProviderEventIngestionSupervisor,
         Keyword.delete(config, :enabled)}
      ]
    else
      []
    end
  end

  defp command_dispatcher_children(%RootComposition{} = composition) do
    if composition.command_dispatch_supervisor_enabled? do
      [
        {Cadence.Commanding.DispatchSupervisor,
         composition.command_dispatch_supervisor_child_opts}
      ]
    else
      []
    end
  end

  defp command_verifier_scheduler_children(%RootComposition{} = composition) do
    if composition.command_verifier_scheduler_enabled? do
      [
        {Cadence.Commanding.VerifierScheduler, composition.command_verifier_scheduler_child_opts}
      ]
    else
      []
    end
  end

  defp root_composition(opts) do
    case Keyword.fetch(opts, :root_composition) do
      {:ok, %RootComposition{} = composition} ->
        composition

      :error ->
        mission_runtime_opts = Keyword.get(opts, :mission_runtime_opts, [])

        compatibility_opts =
          []
          |> Keyword.put(
            :control_process_namespace,
            Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
          )
          |> Keyword.put(
            :runtime_process_namespace,
            Keyword.get_lazy(
              opts,
              :runtime_process_namespace,
              &RuntimeProcessNamespace.default/0
            )
          )
          |> copy_option(
            opts,
            :contact_fact_consumer_opts,
            :control_contact_fact_consumer_opts
          )
          |> copy_option(
            opts,
            :runtime_fact_consumer_opts,
            :control_runtime_fact_consumer_opts
          )
          |> copy_option(
            mission_runtime_opts,
            :start_contact_scheduler?,
            :contact_scheduler_enabled?
          )
          |> copy_option(
            mission_runtime_opts,
            :contact_scheduler_opts,
            :contact_scheduler_opts
          )

        RootComposition.from_application(compatibility_opts)
    end
  end

  defp copy_option(target, source, source_key, target_key) do
    case Keyword.fetch(source, source_key) do
      {:ok, value} -> Keyword.put(target, target_key, value)
      :error -> target
    end
  end
end
