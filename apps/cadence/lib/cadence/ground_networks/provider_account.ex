defmodule Cadence.GroundNetworks.ProviderAccount do
  @moduledoc "Stable organization-owned ground network Provider Account identity."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @states [:active, :archived]
  @credential_states [:active, :revoked, :unknown]
  @ingestion_states [:healthy, :degraded, :disabled, :unknown]

  @type t :: %__MODULE__{
          provider_account_id: binary(),
          organization_id: binary(),
          display_name: binary(),
          lifecycle_state: :active | :archived,
          active_version: pos_integer(),
          credential_status: :active | :revoked | :unknown,
          event_ingestion_status: :healthy | :degraded | :disabled | :unknown,
          last_validated_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :provider_account_id,
    :organization_id,
    :display_name,
    :lifecycle_state,
    :active_version,
    :credential_status,
    :event_ingestion_status,
    :last_validated_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_account_id: value(attrs, :provider_account_id, Ids.new("provider_account")),
      organization_id: required(attrs, :organization_id),
      display_name: required(attrs, :display_name),
      lifecycle_state:
        normalize(value(attrs, :lifecycle_state, :active), @states, :lifecycle_state),
      active_version: positive(value(attrs, :active_version, 1), :active_version),
      credential_status:
        normalize(
          value(attrs, :credential_status, :unknown),
          @credential_states,
          :credential_status
        ),
      event_ingestion_status:
        normalize(
          value(attrs, :event_ingestion_status, :unknown),
          @ingestion_states,
          :event_ingestion_status
        ),
      last_validated_at: value(attrs, :last_validated_at),
      metadata: attrs |> value(:metadata, %{}) |> JsonDocument.encode()
    }
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp normalize(value, allowed, field) when is_atom(value) do
    if value in allowed, do: value, else: raise(ArgumentError, "unsupported #{field}")
  end

  defp normalize(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}"
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
