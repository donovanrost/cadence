defmodule Cadence.Control.DataSources.SourceOperations do
  @moduledoc false

  alias Cadence.DataSources.AdapterRegistry

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.DataSources.{SourceHealthEvent, SourceProbe}

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{DataSource, ResolvedSourceCredential, SourceCredentialMaterial}

  alias Cadence.Platform.Fingerprint

  def probe_data_source(data_source_id, attrs, opts, {fetch_fun, persist_fun})
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    with {:ok, %DataSource{} = data_source} <- fetch_fun.(data_source_id),
         {:ok, mission_id} <- probe_mission_id(data_source, attrs) do
      probe = probe_data_source_health(data_source, opts)

      data_source
      |> source_probe_attrs(mission_id, probe, attrs, opts)
      |> annotate_capability_probe_drift()
      |> record_probe_health_and_maybe_materialize_capabilities(data_source, opts, persist_fun)
    end
  end

  defp probe_mission_id(%DataSource{mission_id: mission_id}, _attrs) when is_binary(mission_id),
    do: {:ok, mission_id}

  defp probe_mission_id(%DataSource{}, attrs) do
    case get_attr(attrs, :mission_id) do
      mission_id when is_binary(mission_id) and mission_id != "" ->
        {:ok, mission_id}

      _other ->
        {:error, "Mission id is required to record source health."}
    end
  end

  defp probe_data_source_health(%DataSource{status: :disabled}, _opts) do
    SourceProbe.unavailable(:source_disabled, %{}, probe_kind: :descriptor)
  end

  defp probe_data_source_health(%DataSource{} = data_source, opts) do
    with :ok <- validate_probe_configuration(data_source),
         {:ok, credential} <- resolve_probe_credentials(data_source, opts),
         {:ok, adapter} <- resolve_adapter(data_source, opts),
         {:ok, probe_adapter} <- resolve_probe_adapter(data_source, opts) do
      materialized_source = %DataSource{data_source | adapter: adapter}

      run_adapter_probe(
        materialized_source,
        probe_adapter,
        put_probe_connection_profile(opts, materialized_source, credential)
      )
    else
      {:degraded, reason} ->
        SourceProbe.degraded(reason, %{}, probe_kind: :descriptor)

      {:unavailable, reason} ->
        SourceProbe.unavailable(reason, %{}, probe_kind: :descriptor)
    end
  end

  defp run_adapter_probe(%DataSource{adapter: adapter} = data_source, probe_adapter, opts)
       when is_atom(adapter) and is_atom(probe_adapter) do
    probe =
      if function_exported?(probe_adapter, :probe, 2) do
        data_source
        |> probe_adapter.probe(opts)
        |> SourceProbe.normalize()
      else
        SourceProbe.unsupported(%{adapter: module_text(probe_adapter)})
      end

    probe
    |> SourceProbe.merge_metadata(connection_probe_metadata(opts))
    |> SourceProbe.merge_metadata(capability_probe_metadata(data_source, adapter, probe))
  end

  defp validate_probe_configuration(%DataSource{} = data_source) do
    case DataSource.validate_configuration(data_source) do
      :ok -> :ok
      {:error, _errors} -> {:degraded, :invalid_data_source_configuration}
    end
  end

  defp resolve_probe_credentials(%DataSource{credentials_ref: nil}, _opts), do: {:ok, nil}

  defp resolve_probe_credentials(%DataSource{} = data_source, opts) do
    resolver_opts = credential_resolver_opts(data_source, opts)

    resolver_result =
      if credential_material_resolver_configured?(opts) do
        SourceCredentials.resolve_material(data_source.credentials_ref, resolver_opts)
      else
        SourceCredentials.resolve(data_source.credentials_ref, resolver_opts)
      end

    case resolver_result do
      {:ok, credential} -> {:ok, credential}
      {:error, reason} -> {:unavailable, reason}
    end
  end

  defp credential_resolver_opts(%DataSource{} = data_source, opts) do
    opts
    |> Keyword.take([
      :credential_material_resolver,
      :credential_material_authorizer,
      :credential_secret_backend,
      :secret_backend,
      :env_material_profiles,
      :env_reader
    ])
    |> Keyword.merge(
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      data_source_id: data_source.data_source_id
    )
  end

  defp credential_material_resolver_configured?(opts) do
    configured = Application.get_env(:cadence, :data_source_credentials, [])

    Keyword.has_key?(opts, :credential_material_resolver) ||
      Keyword.has_key?(opts, :credential_secret_backend) ||
      Keyword.has_key?(opts, :secret_backend) ||
      Keyword.has_key?(configured, :material_resolver) ||
      Keyword.has_key?(configured, :secret_backend)
  end

  defp put_probe_connection_profile(opts, _data_source, nil), do: opts

  defp put_probe_connection_profile(
         opts,
         %DataSource{} = data_source,
         %ResolvedSourceCredential{} = credential
       ) do
    profile = ResolvedSourceCredential.connection_profile(credential, data_source)

    opts
    |> Keyword.put(:source_connection_profile, profile)
    |> maybe_put_questdb_http_endpoint(profile)
  end

  defp put_probe_connection_profile(
         opts,
         %DataSource{} = data_source,
         %SourceCredentialMaterial{} = credential_material
       ) do
    profile =
      SourceCredentialMaterial.redacted_connection_profile(credential_material, data_source)

    opts
    |> Keyword.put(:source_connection_profile, profile)
    |> Keyword.put(
      :source_connection_material,
      SourceCredentialMaterial.adapter_options(credential_material)
    )
    |> maybe_put_questdb_http_endpoint(profile)
  end

  defp maybe_put_questdb_http_endpoint(opts, %{http_endpoint: http_endpoint})
       when is_binary(http_endpoint) do
    Keyword.put_new(opts, :questdb_http_endpoint, http_endpoint)
  end

  defp maybe_put_questdb_http_endpoint(opts, _profile), do: opts

  defp record_probe_health_and_maybe_materialize_capabilities(
         attrs,
         data_source,
         opts,
         persist_fun
       ) do
    case SourceHealth.record_source_health(attrs, opts) do
      {:ok, event_or_unchanged, _status} = result ->
        with :ok <-
               maybe_materialize_adapter_capabilities(
                 data_source,
                 attrs,
                 source_health_event_id(event_or_unchanged),
                 opts,
                 persist_fun
               ) do
          result
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp source_health_event_id(%SourceHealthEvent{} = event), do: event.source_health_event_id
  defp source_health_event_id(_event_or_unchanged), do: nil

  defp maybe_materialize_adapter_capabilities(
         %DataSource{} = data_source,
         attrs,
         event_id,
         opts,
         persist_fun
       ) do
    if Keyword.get(opts, :materialize_adapter_capabilities?, false) do
      materialize_adapter_capabilities(data_source, attrs, event_id, opts, persist_fun)
    else
      :ok
    end
  end

  defp materialize_adapter_capabilities(
         %DataSource{} = data_source,
         attrs,
         event_id,
         opts,
         persist_fun
       ) do
    metadata = probe_metadata(attrs)

    with true <- materializable_adapter_capability_probe?(attrs, metadata),
         reported when is_map(reported) <-
           metadata_value(metadata, :adapter_reported_capabilities) do
      reported = normalize_capability_map(reported)

      materialized =
        %DataSource{
          data_source
          | capabilities: reported,
            metadata:
              Map.merge(data_source.metadata || %{}, %{
                adapter_capability_discovery?: true,
                adapter_capability_discovery_source: :probe,
                adapter_capability_discovery_health: get_attr(attrs, :source_health),
                adapter_capability_discovery_reason: get_attr(attrs, :reason),
                adapter_capability_discovery_fingerprint:
                  metadata_value(metadata, :source_reported_capability_fingerprint)
              })
        }

      payload =
        %{
          source: "data_source_probe",
          adapter_capability_discovery?: true,
          source_health_event_id: event_id,
          probe_kind: get_in(attrs, [:payload, :probe_kind]),
          source_health: get_attr(attrs, :source_health),
          reason: get_attr(attrs, :reason),
          previous_capabilities: data_source.capabilities,
          adapter_reported_capabilities: reported,
          source_reported_capability_fingerprint:
            metadata_value(metadata, :source_reported_capability_fingerprint)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
        |> Map.new()

      case persist_fun.(materialized,
             actor_id: Keyword.get(opts, :actor_id),
             occurred_at: get_attr(attrs, :observed_at, DateTime.utc_now()),
             payload: payload
           ) do
        {:ok, _source} -> :ok
        {:error, reason} -> {:error, {:adapter_capability_materialization_failed, reason}}
      end
    else
      _not_materializable -> :ok
    end
  end

  defp materializable_adapter_capability_probe?(attrs, metadata) do
    get_in(attrs, [:payload, :probe_kind]) == "adapter" and
      get_attr(attrs, :source_health) in [:healthy, :degraded] and
      is_map(metadata_value(metadata, :adapter_reported_capabilities))
  end

  defp normalize_capability_map(capabilities) when is_map(capabilities) do
    capabilities
    |> Enum.map(fn {key, value} -> {text(key), value} end)
    |> Map.new()
  end

  defp resolve_adapter(%DataSource{} = source, opts) do
    case AdapterRegistry.resolve(source.adapter, nil, adapter_policy(opts)) do
      {:ok, adapter} ->
        if Code.ensure_loaded?(adapter) do
          {:ok, adapter}
        else
          {:unavailable, :source_adapter_unavailable}
        end

      :error ->
        {:unavailable, :source_adapter_missing}
    end
  end

  defp resolve_probe_adapter(%DataSource{} = source, opts) do
    case AdapterRegistry.resolve_probe(source.adapter, adapter_policy(opts)) do
      {:ok, adapter} ->
        if Code.ensure_loaded?(adapter) do
          {:ok, adapter}
        else
          {:unavailable, :source_probe_adapter_unavailable}
        end

      :error ->
        {:unavailable, :source_probe_adapter_missing}
    end
  end

  defp capability_probe_metadata(%DataSource{} = data_source, adapter, %SourceProbe{} = probe) do
    case adapter_capabilities(adapter, data_source) do
      %SourceCapabilities{} = capabilities ->
        fingerprint = source_capability_fingerprint(capabilities)
        reported_metadata = reported_capability_probe_metadata(adapter, probe, fingerprint)

        Map.merge(
          %{
            source_capability_fingerprint: fingerprint,
            source_supported_sampling: Enum.join(capabilities.supported_sampling, ","),
            source_supports_watermarks?: capabilities.supports_watermarks?,
            source_capabilities: source_capability_snapshot(adapter, capabilities, fingerprint)
          },
          reported_metadata
        )

      nil ->
        %{
          source_capabilities: %{
            adapter: module_text(adapter),
            supported?: false
          }
        }
    end
  end

  defp connection_probe_metadata(opts) do
    case Keyword.get(opts, :source_connection_profile) do
      profile when is_map(profile) -> %{source_connection_profile: profile}
      _other -> %{}
    end
  end

  defp reported_capability_probe_metadata(adapter, %SourceProbe{} = probe, configured_fingerprint) do
    case metadata_value(probe.metadata, :adapter_reported_capabilities) do
      reported when is_map(reported) ->
        case adapter_capabilities(adapter, %{capabilities: reported}) do
          %SourceCapabilities{} = capabilities ->
            fingerprint = source_capability_fingerprint(capabilities)

            %{
              source_reported_capability_fingerprint: fingerprint,
              source_reported_supported_sampling: Enum.join(capabilities.supported_sampling, ","),
              source_reported_supports_watermarks?: capabilities.supports_watermarks?,
              source_reported_capability_mismatch?: fingerprint != configured_fingerprint,
              source_reported_capabilities:
                source_capability_snapshot(adapter, capabilities, fingerprint)
            }

          nil ->
            %{source_reported_capabilities: %{adapter: module_text(adapter), supported?: false}}
        end

      _other ->
        %{}
    end
  end

  defp adapter_capabilities(adapter, data_source) when is_atom(adapter) and is_map(data_source) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :capabilities, 0),
         %SourceCapabilities{} = adapter_capabilities <-
           SourceCapabilities.normalize(adapter.capabilities()) do
      SourceCapabilities.with_data_source_capabilities(adapter_capabilities, data_source)
    else
      _other -> nil
    end
  end

  defp adapter_capabilities(_adapter, _data_source), do: nil

  defp source_capability_snapshot(adapter, %SourceCapabilities{} = capabilities, fingerprint) do
    %{
      adapter: module_text(adapter),
      supported_sampling: capabilities.supported_sampling,
      supported_products: capabilities.supported_products,
      supported_time_axes: capabilities.supported_time_axes,
      supported_value_types: capabilities.supported_value_types,
      supported_shapes: capabilities.supported_shapes,
      supports_watermarks?: capabilities.supports_watermarks?,
      completeness: capabilities.completeness,
      data_source_capabilities: get_in(capabilities.metadata, [:data_source_capabilities]) || %{},
      capability_fingerprint: fingerprint
    }
  end

  defp source_capability_fingerprint(%SourceCapabilities{} = capabilities) do
    "source-capability:" <>
      Fingerprint.canonical_url_sha256(%{
        logical_source: capabilities.logical_source,
        supported_sampling: capabilities.supported_sampling,
        supported_products: capabilities.supported_products,
        supported_time_axes: capabilities.supported_time_axes,
        supported_value_types: capabilities.supported_value_types,
        supported_shapes: capabilities.supported_shapes,
        supports_watermarks?: capabilities.supports_watermarks?,
        completeness: capabilities.completeness,
        data_source_capabilities:
          get_in(capabilities.metadata, [:data_source_capabilities]) || %{}
      })
  end

  defp source_probe_attrs(
         %DataSource{} = data_source,
         mission_id,
         %SourceProbe{} = probe,
         attrs,
         opts
       ) do
    payload =
      %{
        probe_kind: text(probe.probe_kind),
        actor_id: Keyword.get(opts, :actor_id)
      }
      |> Map.merge(Keyword.get(opts, :payload, %{}))
      |> Map.merge(connection_test_payload(probe))
      |> maybe_put_payload(:probe_message, probe.message)
      |> maybe_put_payload(:probe_metadata, probe.metadata)

    %{
      organization_id: data_source.organization_id,
      mission_id: mission_id,
      logical_source:
        AdapterRegistry.logical_source(data_source.adapter, adapter_policy(opts)) || :unknown,
      data_source_id: data_source.data_source_id,
      source_health: probe.source_health,
      reason: probe.reason,
      observed_at: get_attr(attrs, :observed_at, occurred_at(attrs, opts)),
      payload: payload
    }
  end

  defp connection_test_payload(%SourceProbe{} = probe) do
    classification = connection_test_classification(probe)

    %{
      connection_test_result: text(classification.result),
      connection_test_kind: text(classification.kind),
      connection_test_message: classification.message
    }
  end

  defp connection_test_classification(%SourceProbe{probe_kind: :adapter_unsupported}) do
    %{
      result: :unsupported,
      kind: :adapter_capability,
      message: "Adapter does not implement an active connection test."
    }
  end

  defp connection_test_classification(%SourceProbe{probe_kind: :adapter, source_health: :healthy}) do
    %{
      result: :succeeded,
      kind: :adapter_io,
      message: "Adapter connection test succeeded."
    }
  end

  defp connection_test_classification(%SourceProbe{probe_kind: :adapter}) do
    %{
      result: :failed,
      kind: :adapter_io,
      message: "Adapter connection test failed."
    }
  end

  defp connection_test_classification(%SourceProbe{source_health: :healthy}) do
    %{
      result: :skipped,
      kind: :descriptor_preflight,
      message: "Connection test was not attempted."
    }
  end

  defp connection_test_classification(%SourceProbe{}) do
    %{
      result: :blocked,
      kind: :descriptor_preflight,
      message: "Connection test was blocked before adapter IO."
    }
  end

  defp adapter_policy(opts) do
    Keyword.get_lazy(opts, :data_source_adapter_policy, &AdapterRegistry.default_policy/0)
  end

  defp annotate_capability_probe_drift(attrs) when is_map(attrs) do
    current_metadata = probe_metadata(attrs)
    current_fingerprint = metadata_value(current_metadata, :source_capability_fingerprint)

    with fingerprint when is_binary(fingerprint) <- current_fingerprint,
         {:ok, previous_status} <- previous_source_health_status(attrs),
         previous_metadata when is_map(previous_metadata) <- probe_metadata(previous_status),
         previous_fingerprint when is_binary(previous_fingerprint) <-
           metadata_value(previous_metadata, :source_capability_fingerprint),
         true <- previous_fingerprint != fingerprint do
      put_probe_metadata(
        attrs,
        Map.merge(current_metadata, %{
          source_capability_drift?: true,
          previous_source_capability_fingerprint: previous_fingerprint,
          current_source_capability_fingerprint: fingerprint,
          previous_source_supported_sampling:
            metadata_value(previous_metadata, :source_supported_sampling),
          current_source_supported_sampling:
            metadata_value(current_metadata, :source_supported_sampling),
          previous_source_supports_watermarks?:
            metadata_value(previous_metadata, :source_supports_watermarks?),
          current_source_supports_watermarks?:
            metadata_value(current_metadata, :source_supports_watermarks?)
        })
      )
    else
      _other -> attrs
    end
  end

  defp previous_source_health_status(attrs) do
    attrs
    |> SourceHealthEvent.source_health_key()
    |> SourceHealth.fetch_source_health_status()
  end

  defp probe_metadata(%{payload: payload}) when is_map(payload) do
    case metadata_value(payload, :probe_metadata) do
      metadata when is_map(metadata) -> metadata
      _other -> %{}
    end
  end

  defp probe_metadata(_other), do: %{}

  defp put_probe_metadata(attrs, metadata) when is_map(attrs) and is_map(metadata) do
    payload = Map.get(attrs, :payload, %{}) |> Map.put(:probe_metadata, metadata)
    Map.put(attrs, :payload, payload)
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp maybe_put_payload(payload, _key, nil), do: payload
  defp maybe_put_payload(payload, _key, metadata) when metadata == %{}, do: payload
  defp maybe_put_payload(payload, key, value), do: Map.put(payload, key, value)

  defp occurred_at(attrs, opts) do
    attrs
    |> get_attr(:occurred_at, Keyword.get(opts, :occurred_at, DateTime.utc_now()))
    |> DateTime.truncate(:microsecond)
  end

  defp module_text(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp text(nil), do: "none"
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
