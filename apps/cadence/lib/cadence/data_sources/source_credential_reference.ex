defmodule Cadence.DataSources.SourceCredentialReference do
  @moduledoc """
  Non-secret reference to credential material used by a data source.

  This records ownership, scope, status, version, and external reference
  metadata. It intentionally does not store passwords, API keys, tokens, or
  decrypted connection strings.
  """

  @type owner :: :cadence | :customer
  @type kind :: :byo_tsdb_connection | :managed_tsdb_connection
  @type status :: :active | :disabled

  @type t :: %__MODULE__{
          credentials_ref: binary(),
          organization_id: binary(),
          mission_id: binary() | nil,
          data_source_id: binary() | nil,
          owner: owner(),
          kind: kind(),
          provider: binary() | nil,
          status: status(),
          credential_version: pos_integer(),
          current_event_id: binary() | nil,
          last_rotated_at: DateTime.t() | nil,
          disabled_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :credentials_ref,
    :organization_id,
    :mission_id,
    :data_source_id,
    :provider,
    :current_event_id,
    :last_rotated_at,
    :disabled_at,
    owner: :customer,
    kind: :byo_tsdb_connection,
    status: :active,
    credential_version: 1,
    metadata: %{}
  ]

  @owners [:cadence, :customer]
  @kinds [:byo_tsdb_connection, :managed_tsdb_connection]
  @statuses [:active, :disabled]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      credentials_ref: get_attr(attrs, :credentials_ref),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      data_source_id: get_attr(attrs, :data_source_id),
      owner:
        attrs
        |> get_attr(:owner, :customer)
        |> normalize(:owner, @owners),
      kind:
        attrs
        |> get_attr(:kind, :byo_tsdb_connection)
        |> normalize(:kind, @kinds),
      provider: get_attr(attrs, :provider),
      status:
        attrs
        |> get_attr(:status, :active)
        |> normalize(:status, @statuses),
      credential_version:
        attrs
        |> get_attr(:credential_version, 1)
        |> positive_integer(1),
      current_event_id: get_attr(attrs, :current_event_id),
      last_rotated_at: normalize_optional_datetime(get_attr(attrs, :last_rotated_at)),
      disabled_at: normalize_optional_datetime(get_attr(attrs, :disabled_at)),
      metadata: get_attr(attrs, :metadata, %{})
    }
  end

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{}), do: false

  defp normalize(value, field, values) when is_atom(value) do
    if value in values do
      value
    else
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize(value, field, values) when is_binary(value) do
    Enum.find(values, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize(value, field, _values) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp normalize_optional_datetime(nil), do: nil

  defp normalize_optional_datetime(%DateTime{} = datetime) do
    DateTime.truncate(datetime, :microsecond)
  end

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
