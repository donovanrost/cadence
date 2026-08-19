defmodule Cadence.Runtime.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.IngressArchive
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Runtime.{IngressArchiveConsumer, Persistence, ProcessNamespace}
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Storage}

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
    policies = persistence_policies(opts)
    process_namespace = process_namespace(opts)

    children =
      resource_children(opts, policies) ++
        [
          {Cadence.Runtime.CapabilityRegistry, name: process_namespace.capability_registry},
          {Registry, keys: :unique, name: process_namespace.registry},
          {DynamicSupervisor,
           strategy: :one_for_one,
           name: process_namespace.mission_supervisor,
           extra_arguments: [runtime_child_opts(opts, policies, process_namespace)]}
        ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp resource_children(opts, policies) do
    case Keyword.fetch(opts, :resource_children) do
      {:ok, children} when is_list(children) ->
        children

      :error ->
        [Cadence.Telemetry.Profiler] ++
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

  defp persistence_policies(opts) do
    current_value_store =
      Keyword.get_lazy(opts, :current_value_store_policy, &CurrentValueStore.configured_policy/0)

    telemetry_storage =
      Keyword.get_lazy(opts, :telemetry_storage_policy, fn ->
        Storage.policy(Application.get_env(:cadence, :telemetry_storage, []),
          current_value_store_policy: current_value_store
        )
      end)

    ingress_archive =
      Keyword.get_lazy(opts, :ingress_archive_policy, &IngressArchive.configured_policy/0)

    record_archive =
      Keyword.get_lazy(opts, :record_archive_policy, &RecordArchive.configured_policy/0)

    %{
      current_value_store: current_value_store,
      telemetry_storage: telemetry_storage,
      history_store:
        Keyword.get_lazy(opts, :history_store_policy, fn ->
          HistoryStore.policy(Application.get_env(:cadence, :telemetry_history_store, []),
            storage_policy: telemetry_storage
          )
        end),
      ingress_archive: ingress_archive,
      record_archive: record_archive,
      runtime_persistence:
        Keyword.get_lazy(opts, :persistence_policy, fn ->
          Persistence.policy(ingress_archive, record_archive, telemetry_storage)
        end),
      ingress_archive_consumer:
        Keyword.get_lazy(opts, :ingress_archive_consumer_policy, fn ->
          IngressArchiveConsumer.policy(
            Application.get_env(:cadence, :ingress_archive_consumer, []),
            ingress_archive
          )
        end)
    }
  end

  defp runtime_child_opts(opts, policies, process_namespace) do
    opts
    |> Keyword.get(:mission_runtime_opts, [])
    |> Keyword.put(:process_namespace, process_namespace)
    |> Keyword.put(:persistence_policy, policies.runtime_persistence)
    |> Keyword.put(:current_value_store_policy, policies.current_value_store)
    |> Keyword.put(:telemetry_storage_policy, policies.telemetry_storage)
    |> Keyword.put(:ingress_archive_consumer_policy, policies.ingress_archive_consumer)
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end
end
