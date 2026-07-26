defmodule CadenceWeb.OpsDataSourcesLive.SourceRegistration do
  @moduledoc """
  Source-registration form parsing and persistence payload construction.
  """

  alias Cadence.Dashboards.DataSource
  alias Cadence.ExtensionCatalog

  @spec defaults() :: map()
  def defaults do
    %{
      "data_source_id" => "",
      "logical_source" => "telemetry",
      "kind" => "byo_tsdb",
      "isolation_level" => "customer_owned",
      "credentials_ref" => "",
      "credential_provider" => "questdb",
      "endpoint_ref" => "",
      "material_env_profile" => "",
      "http_endpoint_env" => "",
      "storage" => "questdb"
    }
  end

  @spec parse(map(), binary(), binary()) :: {:ok, map()} | {:error, binary()}
  def parse(params, organization_id, mission_id)
      when is_map(params) and is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, data_source_id} <- required_text(params, "data_source_id", "Source ID"),
         {:ok, logical_source} <- parse_logical_source(Map.get(params, "logical_source")),
         {:ok, kind} <- parse_source_kind(Map.get(params, "kind")),
         {:ok, isolation_level} <- parse_isolation_level(Map.get(params, "isolation_level")),
         :ok <- validate_kind_isolation(kind, isolation_level),
         {:ok, storage} <- parse_source_storage(Map.get(params, "storage")),
         {:ok, credentials_ref} <- source_credentials_ref(params, kind) do
      {:ok,
       %{
         data_source_id: data_source_id,
         logical_source: logical_source,
         kind: kind,
         owner: source_owner(kind),
         isolation_level: isolation_level,
         organization_id: organization_id,
         mission_id: mission_id,
         credentials_ref: credentials_ref,
         credential_provider: optional_text(Map.get(params, "credential_provider")),
         endpoint_ref: optional_text(Map.get(params, "endpoint_ref")),
         material_env_profile: optional_text(Map.get(params, "material_env_profile")),
         http_endpoint_env: optional_text(Map.get(params, "http_endpoint_env")),
         storage: storage
       }}
    end
  end

  @spec data_source(map()) :: DataSource.t()
  def data_source(attrs) when is_map(attrs) do
    {:ok, adapter_definition} = ExtensionCatalog.fetch_source_adapter(attrs.logical_source)

    %DataSource{
      data_source_id: attrs.data_source_id,
      owner: attrs.owner,
      kind: attrs.kind,
      adapter: adapter_definition.module,
      organization_id: attrs.organization_id,
      mission_id: attrs.mission_id,
      isolation_level: attrs.isolation_level,
      credentials_ref: attrs.credentials_ref,
      capabilities: adapter_definition.default_data_source_capabilities,
      metadata:
        %{
          storage: attrs.storage,
          registered_by: "ops_data_sources_live",
          logical_source: attrs.logical_source,
          endpoint_ref: attrs.endpoint_ref,
          material_env_profile: attrs.material_env_profile
        }
        |> compact()
    }
  end

  @spec credential_attrs(map(), map()) :: map()
  def credential_attrs(attrs, payload) when is_map(attrs) and is_map(payload) do
    %{
      credentials_ref: attrs.credentials_ref,
      organization_id: attrs.organization_id,
      mission_id: attrs.mission_id,
      data_source_id: attrs.data_source_id,
      owner: attrs.owner,
      kind: credential_kind(attrs.kind),
      provider: attrs.credential_provider,
      metadata:
        %{
          storage: attrs.storage,
          registered_by: "ops_data_sources_live",
          endpoint_ref: attrs.endpoint_ref,
          material_env_profile: attrs.material_env_profile,
          http_endpoint_env: attrs.http_endpoint_env
        }
        |> compact(),
      payload: payload
    }
  end

  @spec logical_source_options() :: [{binary(), binary()}]
  def logical_source_options do
    Enum.map(ExtensionCatalog.source_adapters(), fn definition ->
      {definition.label, Atom.to_string(definition.logical_source)}
    end)
  end

  @spec source_kind_options() :: [{binary(), binary()}]
  def source_kind_options do
    [
      {"Bring your own TSDB", "byo_tsdb"},
      {"Managed TSDB", "managed_tsdb"}
    ]
  end

  @spec source_isolation_options() :: [{binary(), binary()}]
  def source_isolation_options do
    [
      {"Customer owned", "customer_owned"},
      {"Mission isolated", "mission_isolated"},
      {"Organization isolated", "org_isolated"},
      {"Shared", "shared"}
    ]
  end

  @spec credential_provider_options() :: [{binary(), binary()}]
  def credential_provider_options do
    [
      {"QuestDB", "questdb"},
      {"External vault", "external_vault"},
      {"Cadence managed", "cadence_managed"}
    ]
  end

  @spec source_storage_options() :: [{binary(), binary()}]
  def source_storage_options do
    [
      {"QuestDB", "questdb"},
      {"Postgres projection", "postgres_projection"}
    ]
  end

  defp required_text(params, key, label) do
    params
    |> Map.get(key)
    |> optional_text()
    |> case do
      nil -> {:error, "#{label} is required."}
      value -> {:ok, value}
    end
  end

  defp source_credentials_ref(params, :byo_tsdb) do
    params
    |> Map.get("credentials_ref")
    |> optional_text()
    |> case do
      nil -> {:error, "Credential ref is required for BYO TSDB sources."}
      value -> {:ok, value}
    end
  end

  defp source_credentials_ref(params, :managed_tsdb) do
    {:ok, optional_text(Map.get(params, "credentials_ref"))}
  end

  defp optional_text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_text(_value), do: nil

  defp parse_logical_source(value) when is_binary(value) do
    case Enum.find(
           ExtensionCatalog.source_adapters(),
           &(Atom.to_string(&1.logical_source) == value)
         ) do
      nil -> {:error, "Choose a logical source."}
      definition -> {:ok, definition.logical_source}
    end
  end

  defp parse_logical_source(_value), do: {:error, "Choose a logical source."}

  defp parse_source_kind("managed_tsdb"), do: {:ok, :managed_tsdb}
  defp parse_source_kind("byo_tsdb"), do: {:ok, :byo_tsdb}
  defp parse_source_kind(_value), do: {:error, "Choose a source ownership model."}

  defp parse_isolation_level("shared"), do: {:ok, :shared}
  defp parse_isolation_level("org_isolated"), do: {:ok, :org_isolated}
  defp parse_isolation_level("mission_isolated"), do: {:ok, :mission_isolated}
  defp parse_isolation_level("customer_owned"), do: {:ok, :customer_owned}
  defp parse_isolation_level(_value), do: {:error, "Choose an isolation model."}

  defp validate_kind_isolation(:byo_tsdb, isolation_level)
       when isolation_level in [:customer_owned, :org_isolated, :mission_isolated],
       do: :ok

  defp validate_kind_isolation(:byo_tsdb, _isolation_level),
    do:
      {:error,
       "BYO TSDB sources must use customer_owned, org_isolated, or mission_isolated isolation."}

  defp validate_kind_isolation(:managed_tsdb, :customer_owned),
    do: {:error, "Managed TSDB sources cannot use customer_owned isolation."}

  defp validate_kind_isolation(:managed_tsdb, _isolation_level), do: :ok

  defp parse_source_storage("questdb"), do: {:ok, :questdb}
  defp parse_source_storage("postgres_projection"), do: {:ok, :postgres_projection}
  defp parse_source_storage(_value), do: {:error, "Choose a storage backend."}

  defp source_owner(:byo_tsdb), do: :customer
  defp source_owner(:managed_tsdb), do: :cadence

  defp credential_kind(:byo_tsdb), do: :byo_tsdb_connection
  defp credential_kind(:managed_tsdb), do: :managed_tsdb_connection

  defp compact(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
