defmodule Cadence.GroundNetworks.ProviderAccountGrant do
  @moduledoc "Versioned authorization for one mission to bind a Provider Account version."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @states [:active, :revoked]
  @list_restrictions ~w(
    allowed_services allowed_directions allowed_stations allowed_delivery_kinds
    approved_protocols permitted_destinations permitted_network_ranges
  )
  @numeric_restrictions ~w(max_quota max_cost)
  @known_restrictions @list_restrictions ++ @numeric_restrictions ++ ["extensions"]

  @type t :: %__MODULE__{
          provider_account_grant_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          provider_account_id: binary(),
          provider_account_version: pos_integer(),
          version: pos_integer(),
          lifecycle_state: :active | :revoked,
          restrictions: map(),
          granted_by: binary() | nil,
          granted_at: DateTime.t(),
          grant_reason: binary() | nil,
          revoked_by: binary() | nil,
          revoked_at: DateTime.t() | nil,
          revoke_reason: binary() | nil,
          metadata: map()
        }

  defstruct [
    :provider_account_grant_id,
    :organization_id,
    :mission_id,
    :provider_account_id,
    :provider_account_version,
    :version,
    :lifecycle_state,
    :granted_by,
    :granted_at,
    :grant_reason,
    :revoked_by,
    :revoked_at,
    :revoke_reason,
    restrictions: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_account_grant_id:
        value(attrs, :provider_account_grant_id, Ids.new("provider_account_grant")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      provider_account_id: required(attrs, :provider_account_id),
      provider_account_version:
        positive(value(attrs, :provider_account_version), :provider_account_version),
      version: positive(value(attrs, :version, 1), :version),
      lifecycle_state: normalize(value(attrs, :lifecycle_state, :active)),
      restrictions: document(attrs, :restrictions),
      granted_by: optional_text(attrs, :granted_by),
      granted_at: datetime(value(attrs, :granted_at, DateTime.utc_now()), :granted_at),
      grant_reason: optional_text(attrs, :grant_reason),
      revoked_by: optional_text(attrs, :revoked_by),
      revoked_at: optional_datetime(value(attrs, :revoked_at), :revoked_at),
      revoke_reason: optional_text(attrs, :revoke_reason),
      metadata: document(attrs, :metadata)
    }
  end

  @spec restrictions_narrow?(map(), map()) :: boolean()
  def restrictions_narrow?(account_guardrails, restrictions)
      when is_map(account_guardrails) and is_map(restrictions) do
    restrictions = JsonDocument.encode(restrictions)
    account_guardrails = JsonDocument.encode(account_guardrails)

    Enum.all?(Map.keys(restrictions), &(&1 in @known_restrictions)) and
      Enum.all?(@list_restrictions, &list_narrows?(account_guardrails, restrictions, &1)) and
      Enum.all?(@numeric_restrictions, &number_narrows?(account_guardrails, restrictions, &1)) and
      bounded_extensions?(Map.get(restrictions, "extensions", %{}))
  end

  defp list_narrows?(guardrails, restrictions, key) do
    case {Map.get(guardrails, key), Map.get(restrictions, key)} do
      {_account, nil} ->
        true

      {nil, values} when is_list(values) ->
        string_list?(values)

      {account, values} when is_list(account) and is_list(values) ->
        string_list?(values) and MapSet.subset?(MapSet.new(values), MapSet.new(account))

      _other ->
        false
    end
  end

  defp number_narrows?(guardrails, restrictions, key) do
    case {Map.get(guardrails, key), Map.get(restrictions, key)} do
      {_account, nil} ->
        true

      {nil, value} when is_number(value) and value >= 0 ->
        true

      {account, value} when is_number(account) and is_number(value) ->
        value >= 0 and value <= account

      _other ->
        false
    end
  end

  defp bounded_extensions?(extensions) when is_map(extensions) do
    case Jason.encode(extensions) do
      {:ok, json} -> byte_size(json) <= 16_384
      {:error, _reason} -> false
    end
  end

  defp bounded_extensions?(_extensions), do: false
  defp string_list?(values), do: Enum.all?(values, &(is_binary(&1) and &1 != ""))

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
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(value, field), do: datetime(value, field)
  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a DateTime")

  defp normalize(value) when value in @states, do: value
  defp normalize("active"), do: :active
  defp normalize("revoked"), do: :revoked
  defp normalize(_value), do: raise(ArgumentError, "unsupported lifecycle_state")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
