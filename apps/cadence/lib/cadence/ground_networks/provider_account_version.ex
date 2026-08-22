defmodule Cadence.GroundNetworks.ProviderAccountVersion do
  @moduledoc "Immutable effective configuration for one Provider Account version."

  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Persistence.JsonDocument

  @ingestion_modes [:polling, :webhook, :hybrid, :disabled]

  @type t :: %__MODULE__{
          provider_account_id: binary(),
          organization_id: binary(),
          version: pos_integer(),
          provider_type: MissionProvider.provider_type(),
          client_key: MissionProvider.client_key(),
          base_url: binary(),
          region_ref: binary() | nil,
          environment_ref: binary(),
          credential_ref: binary(),
          event_ingestion_mode: atom(),
          event_configuration: map(),
          request_policy: map(),
          guardrails: map(),
          provider_configuration: map(),
          created_by: binary() | nil,
          created_at: DateTime.t()
        }

  defstruct [
    :provider_account_id,
    :organization_id,
    :version,
    :provider_type,
    :client_key,
    :base_url,
    :region_ref,
    :environment_ref,
    :credential_ref,
    :event_ingestion_mode,
    :created_by,
    :created_at,
    event_configuration: %{},
    request_policy: %{},
    guardrails: %{},
    provider_configuration: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    provider_type =
      normalize(value(attrs, :provider_type), MissionProvider.provider_types(), :provider_type)

    %__MODULE__{
      provider_account_id: required(attrs, :provider_account_id),
      organization_id: required(attrs, :organization_id),
      version: positive(value(attrs, :version, 1), :version),
      provider_type: provider_type,
      client_key:
        normalize(
          value(attrs, :client_key, MissionProvider.client_for(provider_type)),
          MissionProvider.client_keys(),
          :client_key
        ),
      base_url: required(attrs, :base_url),
      region_ref: optional_text(attrs, :region_ref),
      environment_ref: required(attrs, :environment_ref),
      credential_ref: required(attrs, :credential_ref),
      event_ingestion_mode:
        normalize(
          value(attrs, :event_ingestion_mode, :polling),
          @ingestion_modes,
          :event_ingestion_mode
        ),
      event_configuration: document(attrs, :event_configuration),
      request_policy: document(attrs, :request_policy),
      guardrails: document(attrs, :guardrails),
      provider_configuration: document(attrs, :provider_configuration),
      created_by: optional_text(attrs, :created_by),
      created_at: datetime(value(attrs, :created_at, DateTime.utc_now()), :created_at)
    }
  end

  defp document(attrs, key) do
    case value(attrs, key, %{}) do
      document when is_map(document) -> JsonDocument.encode(document)
      _other -> raise ArgumentError, "#{key} must be a map"
    end
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_text(attrs, key) do
    case value(attrs, key) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be non-empty text"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a DateTime")

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
