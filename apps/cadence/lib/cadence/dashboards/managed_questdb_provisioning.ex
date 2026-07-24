defmodule Cadence.Dashboards.ManagedQuestDBProvisioning do
  @moduledoc """
  Provisioning boundary for Cadence-managed QuestDB dashboard data sources.

  This module turns an org/mission TSDB isolation intent into a concrete
  dashboard data-source registration. It applies the Cadence QuestDB schema
  through the existing migrator, stores only redacted topology references in the
  data-source metadata, and records the provisioning intent in the data-source
  lifecycle event payload.
  """

  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.Sources.Telemetry
  alias Cadence.Management.DataSources
  alias Cadence.Telemetry.Storage.QuestDB.SchemaMigrator

  @supported_isolation_levels [:org_isolated, :mission_isolated]

  @default_capabilities %{
    latest?: true,
    range_scan?: true,
    bounded_history?: true,
    watermarks?: true,
    native_decimation?: false
  }

  @type plan :: %{
          required(:data_source) => DataSource.t(),
          required(:connection_config) => keyword(),
          required(:isolation_profile) => DataSource.isolation_profile(),
          required(:provisioning) => map()
        }

  @type provision_result :: %{
          required(:data_source) => DataSource.t(),
          required(:applied_migrations) => [SchemaMigrator.migration()],
          required(:isolation_profile) => DataSource.isolation_profile(),
          required(:provisioning) => map()
        }

  @spec plan(map(), keyword()) :: {:ok, plan()} | {:error, term()}
  def plan(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, data_source} <- build_data_source(attrs),
         :ok <- validate_data_source(data_source) do
      {:ok,
       %{
         data_source: data_source,
         connection_config: redacted_connection_config(migration_config(attrs, opts)),
         isolation_profile: DataSource.isolation_profile(data_source),
         provisioning: provisioning_metadata(data_source, [], :planned)
       }}
    end
  end

  @spec provision(map(), keyword()) :: {:ok, provision_result()} | {:error, term()}
  def provision(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, plan} <- plan(attrs, opts),
         {:ok, applied_migrations} <- apply_schema_migrations(migration_config(attrs, opts), opts),
         data_source <- put_provisioning_metadata(plan.data_source, applied_migrations),
         {:ok, persisted_data_source} <-
           DataSources.persist_data_source(data_source,
             actor_id: actor_id(attrs, opts),
             occurred_at: occurred_at(attrs, opts),
             payload: provisioning_event_payload(data_source, applied_migrations)
           ) do
      {:ok,
       %{
         data_source: persisted_data_source,
         applied_migrations: applied_migrations,
         isolation_profile: DataSource.isolation_profile(persisted_data_source),
         provisioning: provisioning_metadata(persisted_data_source, applied_migrations, :ready)
       }}
    end
  end

  defp build_data_source(attrs) do
    with {:ok, data_source_id} <- required_binary(attrs, :data_source_id),
         {:ok, organization_id} <- required_binary(attrs, :organization_id),
         {:ok, isolation_level} <- isolation_level(attrs),
         :ok <- validate_isolation_level(isolation_level),
         {:ok, mission_id} <- mission_id(attrs, isolation_level) do
      data_source = %DataSource{
        data_source_id: data_source_id,
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Telemetry,
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: isolation_level,
        capabilities: capabilities(attrs),
        metadata: source_metadata(attrs)
      }

      {:ok, data_source}
    end
  end

  defp validate_data_source(%DataSource{} = data_source) do
    case DataSource.validate_configuration(data_source) do
      :ok -> :ok
      {:error, errors} -> {:error, {:invalid_managed_questdb_source, errors}}
    end
  end

  defp isolation_level(attrs) do
    attrs
    |> get_attr(:isolation_level, :mission_isolated)
    |> enum()
    |> then(&{:ok, &1})
  end

  defp validate_isolation_level(isolation_level)
       when isolation_level in @supported_isolation_levels,
       do: :ok

  defp validate_isolation_level(isolation_level),
    do: {:error, {:unsupported_managed_questdb_isolation_level, isolation_level}}

  defp mission_id(attrs, :mission_isolated), do: required_binary(attrs, :mission_id)
  defp mission_id(_attrs, :org_isolated), do: {:ok, nil}

  defp capabilities(attrs) do
    attrs
    |> get_attr(:capabilities, %{})
    |> normalize_map()
    |> then(&Map.merge(@default_capabilities, &1))
  end

  defp source_metadata(attrs) do
    %{
      storage: :questdb,
      endpoint_ref: get_attr(attrs, :endpoint_ref),
      topology_ref: get_attr(attrs, :topology_ref),
      provisioning_mode: :managed_questdb,
      physical_backend: :questdb
    }
    |> maybe_put(:realm, get_attr(attrs, :realm))
    |> maybe_put(:provisioning_owner, actor_id(attrs, []))
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp put_provisioning_metadata(%DataSource{} = data_source, applied_migrations) do
    %{
      data_source
      | metadata:
          Map.put(
            data_source.metadata,
            :provisioning,
            provisioning_metadata(data_source, applied_migrations, :ready)
          )
    }
  end

  defp provisioning_metadata(%DataSource{} = data_source, applied_migrations, deployment_status) do
    %{
      provisioner: :managed_questdb,
      storage: :questdb,
      deployment_backend: :questdb,
      deployment_status: deployment_status,
      isolation_level: data_source.isolation_level,
      physical_boundary: DataSource.isolation_profile(data_source).physical_boundary,
      applied_migration_versions: Enum.map(applied_migrations, & &1.version),
      applied_migration_count: length(applied_migrations)
    }
    |> maybe_put(:endpoint_ref, metadata_value(data_source.metadata, :endpoint_ref))
    |> maybe_put(:topology_ref, metadata_value(data_source.metadata, :topology_ref))
  end

  defp provisioning_event_payload(%DataSource{} = data_source, applied_migrations) do
    %{
      kind: :managed_questdb_provisioned,
      provisioning: provisioning_metadata(data_source, applied_migrations, :ready),
      physical_isolation: DataSource.isolation_profile(data_source)
    }
  end

  defp migration_config(attrs, opts) do
    [
      migrations_path: migrations_path(attrs, opts),
      http_endpoint: option_value(attrs, opts, :http_endpoint),
      hostname: hostname(attrs, opts),
      port: option_value(attrs, opts, :port),
      database: option_value(attrs, opts, :database),
      username: option_value(attrs, opts, :username),
      password: option_value(attrs, opts, :password),
      timeout: option_value(attrs, opts, :timeout),
      exec_fun: Keyword.get(opts, :exec_fun)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp migrations_path(attrs, opts) do
    get_attr(attrs, :migrations_path) ||
      Keyword.get(opts, :migrations_path, SchemaMigrator.default_migrations_path())
  end

  defp hostname(attrs, opts) do
    get_attr(attrs, :hostname) || get_attr(attrs, :host) || Keyword.get(opts, :hostname)
  end

  defp option_value(attrs, opts, key) do
    get_attr(attrs, key) || Keyword.get(opts, key)
  end

  defp redacted_connection_config(config) do
    config
    |> Keyword.drop([:password, :exec_fun])
    |> Keyword.put(:secret_material?, Keyword.has_key?(config, :password))
  end

  defp apply_schema_migrations(migration_config, opts) do
    migrator = Keyword.get(opts, :migrator, &SchemaMigrator.apply_pending/1)
    migrator.(migration_config)
  end

  defp required_binary(attrs, key) do
    case get_attr(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:required_managed_questdb_field_missing, key}}
    end
  end

  defp actor_id(attrs, opts) do
    Keyword.get(opts, :actor_id) || get_attr(attrs, :actor_id)
  end

  defp occurred_at(attrs, opts) do
    attrs
    |> get_attr(:occurred_at, Keyword.get(opts, :occurred_at, DateTime.utc_now()))
    |> DateTime.truncate(:microsecond)
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp maybe_put(map, _key, value) when value in [nil, "", []], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp enum(value) when is_atom(value), do: value
  defp enum("org_isolated"), do: :org_isolated
  defp enum("mission_isolated"), do: :mission_isolated
  defp enum(value), do: value

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
