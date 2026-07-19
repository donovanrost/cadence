defmodule CadenceWeb.OpsDataSourcesLive.SourceInventoryPresentation do
  @moduledoc """
  Source inventory rows, health rollups, and operational action presentation.
  """

  alias Cadence.Dashboards.{
    DataSource,
    SourceCapabilities,
    SourceHealth,
    SourceProbePolicy,
    SourceReadiness,
    TSDBDeploymentStatus
  }

  alias CadenceWeb.OpsDataSourcesLive.{SourceActivityPresentation, SourceContract}

  @spec rows([DataSource.t()], [map()], [map()], [map()], map()) :: [map()]
  def rows(sources, credentials, health_statuses, watermark_statuses, readiness_policy) do
    credentials_by_ref = Map.new(credentials, &{&1.credentials_ref, &1})

    sources
    |> Enum.map(fn %DataSource{} = source ->
      credential = Map.get(credentials_by_ref, source.credentials_ref)
      health = source_health_rollup(health_statuses, source, readiness_policy)
      watermark = source_watermark_rollup(watermark_statuses, source)
      credential_status = source_credential_rollup(source, credential, health.connection_profile)
      capabilities = SourceContract.effective_capabilities(source)
      deployment_status = TSDBDeploymentStatus.from_data_source(source)
      probe_policy = SourceProbePolicy.from_data_source(source)

      %{
        data_source_id: source.data_source_id,
        status_text: text(source.status),
        kind_text: text(source.kind),
        owner_text: text(source.owner),
        isolation_text: text(source.isolation_level),
        adapter_text: module_text(source.adapter),
        credentials_ref: source.credentials_ref,
        credential_action?: credential_action?(source, credential),
        backend_reconcile_action?: backend_reconcile_action?(source),
        backend_provision_action?: backend_provision_action?(source, deployment_status),
        backend_deprovision_action?: backend_deprovision_action?(source),
        enable_action?: enable_action?(source, deployment_status),
        credential_ref_text: credential_text(source, credential),
        credential_state_text: credential_status.state,
        credential_provider_text: credential_status.provider,
        credential_version_text: credential_status.version,
        credential_material_state_text: credential_status.material_state,
        credential_endpoint_text: credential_status.endpoint,
        credential_secret_fields_text: credential_status.secret_fields,
        deployment_status_text: deployment_status.status_text,
        deployment_mode_text: deployment_status.mode_text,
        deployment_backend_text: deployment_status.backend_text,
        deployment_boundary_text: deployment_status.physical_boundary_text,
        deployment_job_id_text: text(deployment_status.job_id),
        deployment_run_id_text: text(deployment_status.run_id),
        deployment_remediation_text: deployment_status.remediation,
        deployment_lifecycle_operation_text: deployment_status.lifecycle_operation_text,
        deployment_lifecycle_status_text: deployment_status.lifecycle_status_text,
        deployment_lifecycle_observed_at_text: deployment_status.lifecycle_observed_at_text,
        capability_text: capability_text(source.capabilities),
        supported_sampling_text: supported_sampling_text(capabilities),
        supported_products_text: supported_products_text(capabilities),
        supported_metric_history_products_text:
          supported_metric_history_products_text(capabilities),
        supported_product_families_text: supported_product_families_text(capabilities),
        health_status: health.status,
        health_reason_text: health.reason,
        probe_policy_text: probe_policy.policy_id,
        probe_stale_after_ms_text: SourceProbePolicy.stale_after_ms_text(probe_policy),
        source_readiness_status: health.readiness_status,
        source_readiness_policy_id: health.readiness_policy_id,
        source_readiness_reason_text: health.readiness_reason,
        probe_kind_text: health.probe_kind,
        probe_message_text: health.probe_message,
        probe_metadata_text: health.probe_metadata,
        probe_diagnostic_kind_text: health.probe_diagnostic_kind,
        probe_diagnostic_stage_text: health.probe_diagnostic_stage,
        probe_remediation_text: health.probe_remediation,
        connection_test_result_text: health.connection_test_result,
        connection_test_kind_text: health.connection_test_kind,
        connection_test_message_text: health.connection_test_message,
        watermark_text: watermark.complete_through,
        watermark_confidence_text: watermark.confidence
      }
    end)
    |> Enum.sort_by(& &1.data_source_id)
  end

  defp credential_action?(%DataSource{credentials_ref: nil}, _credential), do: false
  defp credential_action?(%DataSource{}, nil), do: false
  defp credential_action?(%DataSource{}, _credential), do: true

  defp backend_reconcile_action?(%DataSource{
         status: :active,
         kind: :byo_tsdb,
         isolation_level: isolation_level
       })
       when isolation_level in [:org_isolated, :mission_isolated],
       do: true

  defp backend_reconcile_action?(%DataSource{}), do: false

  defp backend_provision_action?(
         %DataSource{
           status: :active,
           kind: :byo_tsdb,
           isolation_level: isolation_level
         },
         deployment_status
       )
       when isolation_level in [:org_isolated, :mission_isolated] do
    deployment_status.lifecycle_status_text not in ["provision_requested", "provisioned"]
  end

  defp backend_provision_action?(%DataSource{}, _deployment_status), do: false

  defp backend_deprovision_action?(%DataSource{
         status: :active,
         kind: :byo_tsdb,
         isolation_level: isolation_level
       })
       when isolation_level in [:org_isolated, :mission_isolated],
       do: true

  defp backend_deprovision_action?(%DataSource{}), do: false

  defp enable_action?(%DataSource{status: :disabled}, %{lifecycle_status_text: lifecycle_status}) do
    lifecycle_status != "deprovision_requested"
  end

  defp enable_action?(%DataSource{}, _deployment_status), do: false

  defp source_health_rollup(statuses, %DataSource{} = source, readiness_policy) do
    statuses =
      statuses
      |> Enum.filter(&(&1.data_source_id == source.data_source_id))
      |> Enum.map(&SourceHealth.classify_status(&1, source))
      |> Enum.sort_by(&source_health_sort_key/1)

    case statuses do
      [health | _rest] ->
        readiness = SourceReadiness.classify(health, readiness_policy)

        %{
          status: text(health.source_health),
          reason: text(health.reason),
          readiness_status: readiness_status(readiness),
          readiness_policy_id: text(readiness.policy_id),
          readiness_reason: readiness_reason_text(readiness),
          probe_kind: SourceActivityPresentation.probe_payload_text(health.status, :probe_kind),
          probe_message:
            SourceActivityPresentation.probe_payload_text(health.status, :probe_message),
          probe_metadata: SourceActivityPresentation.probe_metadata_summary(health.status),
          probe_diagnostic_kind:
            SourceActivityPresentation.probe_metadata_payload_text(
              health.status,
              :probe_diagnostic_kind
            ),
          probe_diagnostic_stage:
            SourceActivityPresentation.probe_metadata_payload_text(
              health.status,
              :probe_diagnostic_stage
            ),
          probe_remediation:
            SourceActivityPresentation.probe_metadata_payload_text(
              health.status,
              :probe_remediation
            ),
          connection_test_result:
            SourceActivityPresentation.probe_payload_text(health.status, :connection_test_result),
          connection_test_kind:
            SourceActivityPresentation.probe_payload_text(health.status, :connection_test_kind),
          connection_test_message:
            SourceActivityPresentation.probe_payload_text(
              health.status,
              :connection_test_message
            ),
          connection_profile: SourceActivityPresentation.connection_profile(health.status)
        }

      [] ->
        health = SourceHealth.classify_status(nil, source)
        readiness = SourceReadiness.classify(health, readiness_policy)

        %{
          status: text(health.source_health),
          reason: text(health.reason),
          readiness_status: readiness_status(readiness),
          readiness_policy_id: text(readiness.policy_id),
          readiness_reason: readiness_reason_text(readiness),
          probe_kind: "none",
          probe_message: "none",
          probe_metadata: "none",
          probe_diagnostic_kind: "none",
          probe_diagnostic_stage: "none",
          probe_remediation: "none",
          connection_test_result: "none",
          connection_test_kind: "none",
          connection_test_message: "none",
          connection_profile: nil
        }
    end
  end

  defp source_health_sort_key(health) do
    {
      source_health_severity(health.source_health),
      health.last_seen_at && -DateTime.to_unix(health.last_seen_at, :microsecond)
    }
  end

  defp source_health_severity(:unavailable), do: 0
  defp source_health_severity(:degraded), do: 1
  defp source_health_severity(:unknown), do: 2
  defp source_health_severity(_source_health), do: 3

  defp readiness_status(%{blocked?: true}), do: "blocked"
  defp readiness_status(%{blocked?: false}), do: "ready"

  defp readiness_reason_text(%{reasons: []}), do: "none"
  defp readiness_reason_text(%{reasons: reasons}), do: joined_text(reasons)

  defp joined_text(values) when is_list(values), do: Enum.map_join(values, " ", &text/1)

  defp source_watermark_rollup(statuses, %DataSource{} = source) do
    statuses
    |> Enum.filter(&(&1.data_source_id == source.data_source_id))
    |> Enum.sort_by(&source_watermark_sort_key/1)
    |> case do
      [status | _rest] ->
        %{
          complete_through: text(status.complete_through || status.latest_receipt_time),
          confidence: text(status.confidence)
        }

      [] ->
        %{complete_through: "none", confidence: "unknown"}
    end
  end

  defp source_watermark_sort_key(status) do
    observed_at = status.last_seen_at || status.observed_at
    observed_at && -DateTime.to_unix(observed_at, :microsecond)
  end

  defp source_credential_rollup(%DataSource{credentials_ref: nil}, _credential, _profile) do
    %{
      state: "none",
      provider: "none",
      version: "none",
      material_state: "none",
      endpoint: "none",
      secret_fields: "none"
    }
  end

  defp source_credential_rollup(%DataSource{} = source, nil, profile) do
    %{
      state: "unresolved",
      provider: "unknown",
      version: "unknown",
      material_state: credential_material_state(source, profile),
      endpoint: credential_endpoint(source, nil, profile),
      secret_fields: credential_secret_fields(profile)
    }
  end

  defp source_credential_rollup(%DataSource{} = source, credential, profile) do
    %{
      state: text(credential.status),
      provider: text(credential.provider),
      version: text(credential.credential_version),
      material_state: credential_material_state(source, profile),
      endpoint: credential_endpoint(source, credential, profile),
      secret_fields: credential_secret_fields(profile)
    }
  end

  defp credential_material_state(%DataSource{}, profile) when is_map(profile) do
    if truthy?(metadata_value(profile, :secret_material?)), do: "resolved", else: "descriptor"
  end

  defp credential_material_state(%DataSource{}, _profile), do: "unprobed"

  defp credential_endpoint(%DataSource{} = source, credential, profile) do
    metadata_value(profile, :http_endpoint) ||
      metadata_value(source.metadata, :http_endpoint) ||
      (credential && metadata_value(credential.metadata, :http_endpoint)) ||
      "none"
  end

  defp credential_secret_fields(profile) when is_map(profile) do
    profile
    |> metadata_value(:secret_material_fields)
    |> List.wrap()
    |> Enum.map(&text/1)
    |> Enum.reject(&(&1 in ["", "none"]))
    |> case do
      [] -> "none"
      fields -> Enum.join(fields, " ")
    end
  end

  defp credential_secret_fields(_profile), do: "none"

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp credential_text(%DataSource{credentials_ref: nil}, _credential), do: "none"
  defp credential_text(%DataSource{credentials_ref: ref}, nil), do: "#{ref} (unresolved)"

  defp credential_text(%DataSource{credentials_ref: ref}, credential) do
    "#{ref} / #{text(credential.status)} v#{credential.credential_version}"
  end

  defp capability_text(capabilities) when is_map(capabilities) do
    enabled =
      capabilities
      |> Enum.filter(fn {_key, value} -> value == true end)
      |> Enum.map(fn {key, _value} -> text(key) end)
      |> Enum.sort()

    case enabled do
      [] -> "none"
      values -> Enum.join(values, " ")
    end
  end

  defp capability_text(_capabilities), do: "none"

  defp supported_sampling_text(%SourceCapabilities{} = capabilities),
    do: capability_values_text(capabilities.supported_sampling)

  defp supported_sampling_text(_capabilities), do: "unknown"

  defp supported_products_text(%SourceCapabilities{} = capabilities),
    do: capability_values_text(capabilities.supported_products)

  defp supported_products_text(_capabilities), do: "unknown"

  defp supported_metric_history_products_text(%SourceCapabilities{} = capabilities) do
    capabilities
    |> SourceContract.supported_metric_history_products()
    |> capability_values_text()
  end

  defp supported_metric_history_products_text(_capabilities), do: "unknown"

  defp supported_product_families_text(%SourceCapabilities{} = capabilities),
    do: capability_values_text(SourceContract.supported_product_families(capabilities))

  defp supported_product_families_text(_capabilities), do: "unknown"

  defp capability_values_text([]), do: "none"

  defp capability_values_text(values) when is_list(values) do
    values
    |> Enum.map(&text/1)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp module_text(nil), do: "none"

  defp module_text(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp module_text(value), do: text(value)

  defp text(nil), do: "none"
  defp text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)
end
