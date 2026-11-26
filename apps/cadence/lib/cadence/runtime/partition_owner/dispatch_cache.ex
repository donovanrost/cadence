defmodule Cadence.Runtime.PartitionOwner.DispatchCache do
  @moduledoc """
  What the packet path reads per packet, held by the partition so it costs no decode and no
  call into a node singleton.

  Packet definitions live in the node-wide `PacketDefinitionCache` (one decode per plan revision
  for every partition on the node); this holds the partition's table handle and revision. The
  `CapabilityRegistry` lookups per handler key are small, so they are kept here, and dropped on
  every reconcile since the new activation's bindings may put different handlers in play.
  """

  alias Cadence.Runtime.{CapabilityRegistry, PacketDefinitionCache}
  alias Cadence.Telemetry.PacketDefinition

  @type t :: %__MODULE__{
          plan_id: binary() | nil,
          packet_definitions: {:ok, PacketDefinitionCache.table()} | {:error, term()},
          descriptors: %{optional(term()) => term()},
          modules: %{optional(term()) => module()}
        }

  defstruct [:plan_id, :packet_definitions, descriptors: %{}, modules: %{}]

  @doc """
  Holds the activation's telemetry plan revision in the node cache for the calling partition
  (releasing the previous one) and starts with no registry lookups cached. A plan that fails to
  decode is reported on resolve, as it was when each packet decoded it.
  """
  @spec acquire(GenServer.server(), map()) :: t()
  def acquire(cache_server, plans) do
    plan_id = plan_id(plans)

    %__MODULE__{
      plan_id: plan_id,
      packet_definitions: PacketDefinitionCache.acquire(cache_server, plan_id, plans)
    }
  end

  @doc "Resolves a bound packet definition: one ETS read."
  @spec resolve_packet_definition(t(), term()) :: {:ok, PacketDefinition.t()} | {:error, term()}
  def resolve_packet_definition(
        %__MODULE__{packet_definitions: {:ok, table}, plan_id: plan_id},
        %PacketDefinition{packet_definition_id: id} = _configured
      ) do
    case PacketDefinitionCache.fetch(table, plan_id, id) do
      {:ok, definition} -> {:ok, definition}
      :error -> {:error, {:mission_model_packet_definition_not_found, id}}
    end
  end

  def resolve_packet_definition(%__MODULE__{packet_definitions: {:ok, _table}}, configured),
    do: {:error, {:invalid_mission_model_telemetry_binding, configured}}

  def resolve_packet_definition(
        %__MODULE__{packet_definitions: {:error, _} = error},
        _configured
      ),
      do: error

  @doc "The handler's descriptor, asking the registry only on a miss."
  @spec fetch_descriptor(t(), GenServer.server(), term()) ::
          {:ok, term(), t()} | {:error, term()}
  def fetch_descriptor(%__MODULE__{} = cache, registry, handler_key) do
    fetch(cache, :descriptors, handler_key, fn ->
      CapabilityRegistry.fetch_descriptor(registry, handler_key)
    end)
  end

  @doc "The semantic handler's module, asking the registry only on a miss."
  @spec fetch_module(t(), GenServer.server(), term()) ::
          {:ok, module(), t()} | {:error, term()}
  def fetch_module(%__MODULE__{} = cache, registry, handler_key) do
    fetch(cache, :modules, handler_key, fn ->
      CapabilityRegistry.fetch_family(registry, handler_key)
    end)
  end

  defp fetch(cache, field, key, lookup) do
    case Map.fetch!(cache, field) do
      %{^key => value} ->
        {:ok, value, cache}

      _missing ->
        with {:ok, value} <- lookup.() do
          {:ok, value, Map.update!(cache, field, &Map.put(&1, key, value))}
        end
    end
  end

  defp plan_id(%{telemetry: %{plan_id: plan_id}}), do: plan_id
  defp plan_id(_plans), do: nil
end
