defmodule Cadence.GroundNetworks.ProviderCredential do
  @moduledoc "Stable, non-secret registry record for a Provider Account credential."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @statuses [:active, :revoked]
  @backend_types [:env, :external]

  @type status :: :active | :revoked
  @type backend_type :: :env | :external

  @type t :: %__MODULE__{
          provider_credential_ref: binary(),
          organization_id: binary(),
          provider_account_id: binary(),
          status: status(),
          registry_version: pos_integer(),
          backend_type: backend_type(),
          backend_key: binary(),
          backend_reference: binary() | nil,
          registered_at: DateTime.t(),
          last_resolved_at: DateTime.t() | nil,
          last_rotated_at: DateTime.t() | nil,
          revoked_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :provider_credential_ref,
    :organization_id,
    :provider_account_id,
    :status,
    :registry_version,
    :backend_type,
    :backend_key,
    :backend_reference,
    :registered_at,
    :last_resolved_at,
    :last_rotated_at,
    :revoked_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_credential_ref:
        value(attrs, :provider_credential_ref, Ids.new("provider_credential")),
      organization_id: required(attrs, :organization_id),
      provider_account_id: required(attrs, :provider_account_id),
      status: attrs |> value(:status, :active) |> normalize(:status, @statuses),
      registry_version: positive_integer(value(attrs, :registry_version, 1), :registry_version),
      backend_type: attrs |> value(:backend_type) |> normalize(:backend_type, @backend_types),
      backend_key: required(attrs, :backend_key),
      backend_reference: optional_text(attrs, :backend_reference),
      registered_at: datetime(value(attrs, :registered_at, DateTime.utc_now()), :registered_at),
      last_resolved_at: optional_datetime(value(attrs, :last_resolved_at), :last_resolved_at),
      last_rotated_at: optional_datetime(value(attrs, :last_rotated_at), :last_rotated_at),
      revoked_at: optional_datetime(value(attrs, :revoked_at), :revoked_at),
      metadata: metadata(attrs)
    }
  end

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{}), do: false

  defp metadata(attrs) do
    case value(attrs, :metadata, %{}) do
      metadata when is_map(metadata) -> JsonDocument.encode(metadata)
      _other -> raise ArgumentError, "metadata must be a map"
    end
  end

  defp normalize(value, field, allowed) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp normalize(value, field, allowed) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize(value, field, _allowed),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")

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

  defp positive_integer(value, _field) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(value, field), do: datetime(value, field)

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a DateTime")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
