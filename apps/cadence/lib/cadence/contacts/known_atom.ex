defmodule Cadence.Contacts.KnownAtom do
  @moduledoc false

  alias Cadence.Capabilities.Descriptor
  alias Cadence.Capabilities.Registry, as: CapabilityRegistry
  alias Cadence.ProviderAdapters.Registry, as: ProviderAdapterRegistry

  @directions %{
    "uplink" => :uplink,
    "downlink" => :downlink
  }

  @selection_roles %{
    "selected" => :selected,
    "candidate" => :candidate,
    "contributing" => :contributing
  }

  @clock_modes %{
    "live" => :live,
    "replay" => :replay
  }

  @realized_contact_lifecycle_states %{
    "defined" => :defined,
    "active" => :active,
    "stopped" => :stopped,
    "completed" => :completed
  }

  @scheduled_contact_lifecycle_states %{
    "scheduled" => :scheduled,
    "realized" => :realized,
    "completed" => :completed,
    "expired" => :expired,
    "canceled" => :canceled
  }

  @versioned_resource_lifecycle_states %{
    "active" => :active,
    "deleted" => :deleted
  }

  @target_scopes %{
    "path" => :path,
    "transport" => :transport
  }

  @contact_action_kinds %{
    "scheduled_contact_canceled" => :scheduled_contact_canceled,
    "realized_contact_ended_early" => :realized_contact_ended_early
  }

  @spec direction!(atom() | binary()) :: :uplink | :downlink
  def direction!(value), do: normalize_known_atom!(value, @directions, :direction)

  @spec selection_role!(atom() | binary()) :: :selected | :candidate | :contributing
  def selection_role!(value), do: normalize_known_atom!(value, @selection_roles, :selection_role)

  @spec clock_mode!(atom() | binary()) :: :live | :replay
  def clock_mode!(value), do: normalize_known_atom!(value, @clock_modes, :clock_mode)

  @spec realized_contact_lifecycle_state!(atom() | binary()) ::
          :defined | :active | :stopped | :completed
  def realized_contact_lifecycle_state!(value) do
    normalize_known_atom!(value, @realized_contact_lifecycle_states, :lifecycle_state)
  end

  @spec scheduled_contact_lifecycle_state!(atom() | binary()) ::
          :scheduled | :realized | :completed | :expired | :canceled
  def scheduled_contact_lifecycle_state!(value) do
    normalize_known_atom!(value, @scheduled_contact_lifecycle_states, :lifecycle_state)
  end

  @spec versioned_resource_lifecycle_state!(atom() | binary()) :: :active | :deleted
  def versioned_resource_lifecycle_state!(value) do
    normalize_known_atom!(value, @versioned_resource_lifecycle_states, :lifecycle_state)
  end

  @spec target_scope!(atom() | binary()) :: :path | :transport
  def target_scope!(value), do: normalize_known_atom!(value, @target_scopes, :target_scope)

  @spec contact_action_kind!(atom() | binary()) ::
          :scheduled_contact_canceled | :realized_contact_ended_early
  def contact_action_kind!(value) do
    normalize_known_atom!(value, @contact_action_kinds, :action_kind)
  end

  @spec provider_adapter_key!(atom() | binary()) :: atom()
  def provider_adapter_key!(value) do
    normalize_known_atom!(value, provider_adapter_keys(), :adapter_key)
  end

  @spec transport_family_key!(atom() | binary()) :: atom()
  def transport_family_key!(value) do
    normalize_known_atom!(value, transport_family_keys(), :family_key)
  end

  defp provider_adapter_keys do
    ProviderAdapterRegistry.default()
    |> Map.keys()
    |> Map.new(fn adapter_key -> {Atom.to_string(adapter_key), adapter_key} end)
  end

  defp transport_family_keys do
    CapabilityRegistry.default()
    |> Enum.reduce(%{}, fn {family_key, family_module}, acc ->
      case family_module.descriptor() do
        %Descriptor{kind: :transport_extension} ->
          Map.put(acc, Atom.to_string(family_key), family_key)

        _other ->
          acc
      end
    end)
  end

  defp normalize_known_atom!(value, mapping, field) when is_atom(value) do
    if value in Map.values(mapping) do
      value
    else
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize_known_atom!(value, mapping, field) when is_binary(value) do
    case Map.fetch(mapping, value) do
      {:ok, normalized} ->
        normalized

      :error ->
        raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize_known_atom!(value, _mapping, field) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end
end
