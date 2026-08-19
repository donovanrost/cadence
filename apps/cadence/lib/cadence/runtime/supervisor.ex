defmodule Cadence.Runtime.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.IngressArchive
  alias Cadence.Platform.RootComposition
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Storage}

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
    policies = persistence_policies(opts, composition)
    process_namespace = process_namespace(opts, composition)

    children =
      resource_children(opts, policies, composition) ++
        [
          {Cadence.Runtime.CapabilityRegistry, name: process_namespace.capability_registry},
          {Registry, keys: :unique, name: process_namespace.registry},
          {DynamicSupervisor,
           strategy: :one_for_one,
           name: process_namespace.mission_supervisor,
           extra_arguments: [runtime_child_opts(opts, policies, process_namespace, composition)]}
        ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp resource_children(opts, policies, composition) do
    case Keyword.fetch(opts, :resource_children) do
      {:ok, children} when is_list(children) ->
        children

      :error ->
        [{Cadence.Telemetry.Profiler, profiler_child_opts(opts, policies, composition)}] ++
          ingress_archive_children(policies) ++
          protocol_record_archive_children(policies) ++
          telemetry_backend_children(policies)
    end
  end

  defp telemetry_backend_children(policies) do
    [
      CurrentValueStore.child_spec(policies.current_value_store),
      HistoryStore.child_spec(policies.history_store),
      Storage.child_spec(policies.telemetry_storage)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp ingress_archive_children(policies) do
    [IngressArchive.child_spec(policies.ingress_archive)]
    |> Enum.reject(&is_nil/1)
  end

  defp protocol_record_archive_children(policies) do
    [RecordArchive.child_spec(policies.record_archive)]
    |> Enum.reject(&is_nil/1)
  end

  defp persistence_policies(_opts, %RootComposition{} = composition) do
    %{
      current_value_store: composition.current_value_store_policy,
      telemetry_storage: composition.telemetry_storage_policy,
      history_store: composition.history_store_policy,
      ingress_archive: composition.ingress_archive_policy,
      record_archive: composition.record_archive_policy,
      runtime_persistence: composition.runtime_persistence_policy,
      ingress_archive_consumer: composition.ingress_archive_consumer_policy
    }
  end

  defp profiler_child_opts(_opts, policies, %RootComposition{} = composition) do
    composition.profiler_child_opts
    |> Keyword.put(:ingress_archive_policy, policies.ingress_archive)
    |> Keyword.put(:record_archive_policy, policies.record_archive)
  end

  defp runtime_child_opts(
         opts,
         policies,
         process_namespace,
         %RootComposition{} = composition
       ) do
    opts
    |> Keyword.get(:mission_runtime_opts, [])
    |> Keyword.put(:process_namespace, process_namespace)
    |> Keyword.put(:persistence_policy, policies.runtime_persistence)
    |> Keyword.put(:current_value_store_policy, policies.current_value_store)
    |> Keyword.put(:telemetry_storage_policy, policies.telemetry_storage)
    |> Keyword.put(:ingress_journal_policy, composition.ingress_journal_policy)
    |> Keyword.put(:ingress_archive_consumer_policy, policies.ingress_archive_consumer)
  end

  defp process_namespace(_opts, %RootComposition{} = composition),
    do: composition.runtime_process_namespace

  defp root_composition(opts) do
    case Keyword.fetch(opts, :root_composition) do
      {:ok, %RootComposition{} = composition} ->
        composition

      :error ->
        mission_runtime_opts = Keyword.get(opts, :mission_runtime_opts, [])

        compatibility_opts =
          []
          |> Keyword.put(
            :runtime_process_namespace,
            Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
          )
          |> copy_ingress_journal_policy(opts, mission_runtime_opts)
          |> copy_option(opts, :profiler_child_opts)
          |> copy_option(opts, :current_value_store_policy)
          |> copy_option(opts, :telemetry_storage_policy)
          |> copy_option(opts, :history_store_policy)
          |> copy_option(opts, :ingress_archive_policy)
          |> copy_option(opts, :record_archive_policy)
          |> copy_option(opts, :persistence_policy, :runtime_persistence_policy)
          |> copy_option(opts, :ingress_archive_consumer_policy)

        RootComposition.from_application(compatibility_opts)
    end
  end

  defp copy_option(target, source, source_key, target_key \\ nil) do
    case Keyword.fetch(source, source_key) do
      {:ok, value} -> Keyword.put(target, target_key || source_key, value)
      :error -> target
    end
  end

  defp copy_ingress_journal_policy(target, opts, mission_runtime_opts) do
    case Keyword.fetch(opts, :ingress_journal_policy) do
      {:ok, policy} ->
        Keyword.put(target, :ingress_journal_policy, policy)

      :error ->
        copy_option(target, mission_runtime_opts, :ingress_journal_policy)
    end
  end
end
