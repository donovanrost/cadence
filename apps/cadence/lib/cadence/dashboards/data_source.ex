defmodule Cadence.Dashboards.DataSource do
  @moduledoc """
  Registered physical source available to dashboard source adapters.

  A data source describes where values live and which adapter can read them. It
  does not describe what an observable means; that remains catalog-owned.
  """

  @type owner :: :cadence | :customer
  @type kind :: :managed_tsdb | :byo_tsdb | :postgres | :object_archive | :projection
  @type isolation_level :: :shared | :org_isolated | :mission_isolated | :customer_owned
  @type status :: :active | :disabled
  @type isolation_boundary :: :shared | :organization | :mission | :customer_connection

  @type t :: %__MODULE__{
          data_source_id: binary(),
          owner: owner(),
          kind: kind(),
          adapter: module() | nil,
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          isolation_level: isolation_level(),
          credentials_ref: binary() | nil,
          status: status(),
          current_event_id: binary() | nil,
          disabled_at: DateTime.t() | nil,
          capabilities: map(),
          metadata: map()
        }

  @type isolation_profile :: %{
          required(:isolation_level) => isolation_level(),
          required(:physical_boundary) => isolation_boundary(),
          optional(:organization_id) => binary(),
          optional(:mission_id) => binary(),
          optional(:storage) => term(),
          optional(:endpoint_ref) => binary(),
          optional(:topology_ref) => binary()
        }

  defstruct [
    :data_source_id,
    :adapter,
    :organization_id,
    :mission_id,
    :credentials_ref,
    :current_event_id,
    :disabled_at,
    owner: :cadence,
    kind: :managed_tsdb,
    isolation_level: :shared,
    status: :active,
    capabilities: %{},
    metadata: %{}
  ]

  alias Cadence.Dashboards.SecretMetadata

  @type validation_error :: {atom(), binary()}

  @spec validate_configuration(t()) :: :ok | {:error, [validation_error()]}
  def validate_configuration(%__MODULE__{} = data_source) do
    errors =
      []
      |> validate_credentials_ref(data_source)
      |> validate_metadata_secrets(data_source)
      |> validate_isolation_scope(data_source)
      |> validate_customer_owned_isolation(data_source)
      |> validate_byo_tsdb(data_source)
      |> Enum.reverse()

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{}), do: false

  @spec isolation_profile(t()) :: isolation_profile()
  def isolation_profile(%__MODULE__{} = data_source) do
    %{
      isolation_level: isolation_level(data_source),
      physical_boundary: physical_boundary(data_source),
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      storage: metadata_value(data_source.metadata, :storage),
      endpoint_ref: metadata_value(data_source.metadata, :endpoint_ref),
      topology_ref: metadata_value(data_source.metadata, :topology_ref)
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp validate_credentials_ref(errors, %__MODULE__{credentials_ref: nil}), do: errors

  defp validate_credentials_ref(errors, %__MODULE__{credentials_ref: credentials_ref})
       when is_binary(credentials_ref) do
    if String.trim(credentials_ref) == "" do
      [{:credentials_ref, "must be a non-empty indirect credential reference"} | errors]
    else
      errors
    end
  end

  defp validate_credentials_ref(errors, %__MODULE__{}) do
    [{:credentials_ref, "must be a non-empty indirect credential reference"} | errors]
  end

  defp validate_metadata_secrets(errors, %__MODULE__{metadata: metadata}) do
    if SecretMetadata.contains_secret?(metadata) do
      [{:metadata, "must not embed credentials or secrets; use credentials_ref"} | errors]
    else
      errors
    end
  end

  defp validate_isolation_scope(errors, %__MODULE__{} = data_source) do
    case isolation_level(data_source) do
      :org_isolated ->
        require_organization_id(data_source, errors, "must be set for org-isolated data sources")

      :mission_isolated ->
        data_source
        |> require_organization_id(errors, "must be set for mission-isolated data sources")
        |> require_mission_id(data_source, "must be set for mission-isolated data sources")

      _other ->
        errors
    end
  end

  defp validate_customer_owned_isolation(errors, %__MODULE__{} = data_source) do
    cond do
      isolation_level(data_source) != :customer_owned ->
        errors

      owner(data_source) != :customer ->
        [{:owner, "must be customer for customer-owned data sources"} | errors]

      blank?(data_source.organization_id) ->
        [
          {:organization_id, "must be set for customer-owned data sources"}
          | require_credentials_ref(
              errors,
              data_source,
              "must be set for customer-owned data sources"
            )
        ]

      true ->
        require_credentials_ref(
          errors,
          data_source,
          "must be set for customer-owned data sources"
        )
    end
  end

  defp validate_byo_tsdb(errors, %__MODULE__{} = data_source) do
    if kind(data_source) == :byo_tsdb do
      errors
      |> require_owner(data_source, :customer, "must be customer for BYO TSDB data sources")
      |> require_isolation_level(
        data_source,
        :customer_owned,
        "must be customer_owned for BYO TSDB data sources"
      )
      |> require_organization_id(data_source, "must be set for BYO TSDB data sources")
      |> require_credentials_ref(data_source, "must be set for BYO TSDB data sources")
    else
      errors
    end
  end

  defp require_owner(errors, %__MODULE__{} = data_source, expected, message) do
    if owner(data_source) == expected, do: errors, else: [{:owner, message} | errors]
  end

  defp require_isolation_level(errors, %__MODULE__{} = data_source, expected, message) do
    if isolation_level(data_source) == expected do
      errors
    else
      [{:isolation_level, message} | errors]
    end
  end

  defp require_organization_id(errors, %__MODULE__{} = data_source, message) do
    if blank?(data_source.organization_id),
      do: [{:organization_id, message} | errors],
      else: errors
  end

  defp require_organization_id(%__MODULE__{} = data_source, errors, message) do
    require_organization_id(errors, data_source, message)
  end

  defp require_mission_id(errors, %__MODULE__{} = data_source, message) do
    if blank?(data_source.mission_id),
      do: [{:mission_id, message} | errors],
      else: errors
  end

  defp require_credentials_ref(errors, %__MODULE__{} = data_source, message) do
    if blank?(data_source.credentials_ref),
      do: [{:credentials_ref, message} | errors],
      else: errors
  end

  defp owner(%__MODULE__{owner: owner}), do: enum(owner)
  defp kind(%__MODULE__{kind: kind}), do: enum(kind)
  defp isolation_level(%__MODULE__{isolation_level: isolation_level}), do: enum(isolation_level)

  defp physical_boundary(%__MODULE__{} = data_source) do
    case isolation_level(data_source) do
      :org_isolated -> :organization
      :mission_isolated -> :mission
      :customer_owned -> :customer_connection
      _other -> :shared
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp enum(value) when is_atom(value), do: value
  defp enum("cadence"), do: :cadence
  defp enum("customer"), do: :customer
  defp enum("managed_tsdb"), do: :managed_tsdb
  defp enum("byo_tsdb"), do: :byo_tsdb
  defp enum("postgres"), do: :postgres
  defp enum("object_archive"), do: :object_archive
  defp enum("projection"), do: :projection
  defp enum("shared"), do: :shared
  defp enum("org_isolated"), do: :org_isolated
  defp enum("mission_isolated"), do: :mission_isolated
  defp enum("customer_owned"), do: :customer_owned
  defp enum("active"), do: :active
  defp enum("disabled"), do: :disabled
  defp enum(value), do: value

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
