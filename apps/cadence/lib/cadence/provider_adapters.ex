defmodule Cadence.ProviderAdapters do
  @moduledoc """
  Runtime lookup and dispatch facade for path-local provider adapters.
  """

  alias Cadence.ActionRequests.ProviderRequest
  alias Cadence.ProviderAdapters.Registry, as: ProviderRegistry
  alias Cadence.Runtime.ProcessNamespace

  @spec deliver_uplink(binary(), binary(), binary(), ProviderRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def deliver_uplink(
        mission_id,
        realized_contact_id,
        path_id,
        %ProviderRequest{} = provider_request
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) do
    deliver_uplink(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_request
    )
  end

  @spec deliver_uplink(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          ProviderRequest.t()
        ) :: {:ok, map()} | {:error, term()}
  def deliver_uplink(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        %ProviderRequest{} = provider_request
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) do
    with {:ok, adapter_module} <-
           ProviderRegistry.fetch_module(provider_request.provider_adapter_key),
         {:ok, provider_runtime} <-
           provider_runtime(
             process_namespace,
             mission_id,
             realized_contact_id,
             path_id,
             provider_request.provider_binding_id
           ) do
      adapter_module.deliver_uplink(provider_runtime, provider_request)
    end
  end

  @spec snapshot(binary(), binary(), binary(), binary(), atom()) ::
          {:ok, map()} | {:error, term()}
  def snapshot(mission_id, realized_contact_id, path_id, provider_binding_id, adapter_key)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(provider_binding_id) and is_atom(adapter_key) do
    snapshot(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id,
      adapter_key
    )
  end

  @spec snapshot(ProcessNamespace.t(), binary(), binary(), binary(), binary(), atom()) ::
          {:ok, map()} | {:error, term()}
  def snapshot(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id,
        adapter_key
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(provider_binding_id) and is_atom(adapter_key) do
    with {:ok, adapter_module} <- ProviderRegistry.fetch_module(adapter_key),
         {:ok, provider_runtime} <-
           provider_runtime(
             process_namespace,
             mission_id,
             realized_contact_id,
             path_id,
             provider_binding_id
           ) do
      adapter_module.snapshot(provider_runtime)
    end
  end

  @spec quiesce(binary(), binary(), binary(), binary(), atom()) ::
          {:ok, map()} | {:error, term()}
  def quiesce(mission_id, realized_contact_id, path_id, provider_binding_id, adapter_key)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(provider_binding_id) and is_atom(adapter_key) do
    quiesce(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id,
      adapter_key
    )
  end

  @spec quiesce(ProcessNamespace.t(), binary(), binary(), binary(), binary(), atom()) ::
          {:ok, map()} | {:error, term()}
  def quiesce(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id,
        adapter_key
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(provider_binding_id) and is_atom(adapter_key) do
    with {:ok, adapter_module} <- ProviderRegistry.fetch_module(adapter_key),
         {:ok, provider_runtime} <-
           provider_runtime(
             process_namespace,
             mission_id,
             realized_contact_id,
             path_id,
             provider_binding_id
           ) do
      adapter_module.quiesce(provider_runtime)
    end
  end

  defp provider_runtime(
         process_namespace,
         mission_id,
         realized_contact_id,
         path_id,
         provider_binding_id
       ) do
    case Elixir.Registry.lookup(
           process_namespace.registry,
           {:provider_runtime, mission_id, realized_contact_id, path_id, provider_binding_id}
         ) do
      [{provider_runtime, _value}] -> {:ok, provider_runtime}
      [] -> {:error, {:provider_runtime_not_running, provider_binding_id}}
    end
  end
end
