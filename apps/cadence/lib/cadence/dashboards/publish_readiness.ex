defmodule Cadence.Dashboards.PublishReadiness do
  @moduledoc """
  Mission-aware dashboard publish readiness validation.

  Structural document validation is intentionally context-free so drafts can be
  saved while source configuration is still in progress. Publish readiness is
  stricter: a published dashboard should not depend on source bindings or
  physical source capabilities that cannot satisfy its planned requests.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    Engine,
    ResolveWarning,
    ValidationResult
  }

  alias Cadence.Reads.DataSources

  # Facts about the source itself block a save (lead 11-14): it isn't bound, configured, enabled
  # or capable, or its connection test failed.
  @source_fact_codes [
    :missing_source_binding,
    :source_binding_interval_ambiguous,
    :missing_data_source,
    :disabled_data_source,
    :invalid_data_source_configuration,
    :source_connection_failed,
    :unsupported_source_capability,
    :unsupported_observable_scope,
    :invalid_runtime_context
  ]
  # Health a read reported (a timed-out preview records source_unavailable for up to 24 h) only
  # warns: one slow read must not block every save on the mission. It still blocks when the same
  # evidence carries a failed connection test.
  @source_health_codes [:source_unavailable, :source_degraded]
  @failed_connection_tests ["failed", "blocked"]
  @source_evidence_warning_codes [
    :stale_data,
    :watermark_unknown,
    :unknown_watermark,
    :retention_gap
  ]

  @spec validate(binary(), binary(), Document.t(), keyword()) :: ValidationResult.t()
  def validate(organization_id, mission_id, %Document{} = document, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    validation = Document.validate(document)

    if validation.valid? do
      validation
      |> add_plan_readiness_errors(organization_id, mission_id, document, opts)
    else
      validation
    end
  end

  defp add_plan_readiness_errors(
         %ValidationResult{} = validation,
         organization_id,
         mission_id,
         %Document{} = document,
         opts
       ) do
    organization_id = document.organization_id || organization_id
    mission_id = document.mission_id || mission_id

    %DashboardResolveResult{} =
      result =
      Engine.plan(
        %DashboardResolveRequest{
          organization_id: organization_id,
          mission_id: mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          document_mode: :draft,
          resolve_mode: :initial
        },
        readiness_plan_opts(organization_id, mission_id, opts)
      )

    result.dashboard_warnings
    |> Enum.reduce(validation, fn warning, acc ->
      cond do
        blocking_warning?(warning) ->
          ValidationResult.add_error(
            acc,
            :unready_publish_source_request,
            warning_details(warning)
          )

        source_health_warning?(warning) ->
          ValidationResult.add_warning(acc, warning.code, warning_details(warning))

        source_evidence_warning?(warning) ->
          ValidationResult.add_warning(acc, warning.code, warning_details(warning))

        true ->
          acc
      end
    end)
  end

  defp readiness_plan_opts(organization_id, mission_id, opts) do
    opts
    |> Keyword.put_new(:runtime_cache, false)
    |> Keyword.put_new(:plan_cache?, false)
    |> put_registry_opts(organization_id, mission_id)
  end

  defp put_registry_opts(opts, organization_id, mission_id) do
    explicit_registry? =
      Keyword.has_key?(opts, :data_sources) or Keyword.has_key?(opts, :data_bindings)

    data_sources =
      Keyword.get_lazy(
        opts,
        :data_sources,
        fn -> DataSources.list_data_sources(organization_id, mission_id) end
      )

    data_bindings =
      Keyword.get_lazy(
        opts,
        :data_bindings,
        fn -> DataSources.list_data_bindings(organization_id, mission_id) end
      )

    cond do
      explicit_registry? ->
        opts
        |> Keyword.put(:data_sources, data_sources)
        |> Keyword.put(:data_bindings, data_bindings)
        |> Keyword.put_new(:source_health_statuses, [])

      data_sources == [] and data_bindings == [] ->
        opts

      true ->
        Keyword.put(opts, :persisted?, true)
    end
  end

  defp blocking_warning?(%ResolveWarning{code: code}) when code in @source_fact_codes, do: true

  defp blocking_warning?(%ResolveWarning{code: code} = warning) when code in @source_health_codes,
    do: connection_test_failed?(warning)

  defp blocking_warning?(_warning), do: false

  # Only health a read actually reported warns: a source nobody has read yet is unknown, and
  # warning on it would flag every new widget (dashboards).
  defp source_health_warning?(%ResolveWarning{code: code, details: details})
       when code in @source_health_codes and is_map(details) do
    details
    |> Map.get(:reasons, [])
    |> Enum.any?(&(&1 in [:source_unavailable, :source_degraded]))
  end

  defp source_health_warning?(_warning), do: false

  defp connection_test_failed?(%ResolveWarning{details: %{} = details}) do
    case Map.get(details, :connection_test_result) do
      nil -> false
      result -> to_string(result) in @failed_connection_tests
    end
  end

  defp connection_test_failed?(_warning), do: false

  defp source_evidence_warning?(%ResolveWarning{code: code}),
    do: code in @source_evidence_warning_codes

  defp source_evidence_warning?(_warning), do: false

  @doc """
  An editor issue's source details for the save sheet (lead 11-14): which source and realm, why
  (`SourceReadiness` reasons) and when its health was seen. nil for an issue that isn't about a
  source.
  """
  @spec source_details(atom(), map()) :: map() | nil
  def source_details(:unready_publish_source_request, details) when is_map(details),
    do: %{
      logical_source: details[:logical_source],
      realm: details[:realm],
      reasons: details[:reasons] || [],
      observed_at: details[:observed_at]
    }

  def source_details(_code, _details), do: nil

  # logical_source, realm, reasons and observed_at sit on top for the save sheet (lead 11-14).
  defp warning_details(%ResolveWarning{} = warning) do
    details = warning.details || %{}

    %{
      source_warning_code: warning.code,
      source_warning_message: warning.message,
      severity: warning.severity,
      placement_id: warning.placement_id,
      logical_source: Map.get(details, :logical_source),
      realm: Map.get(details, :realm),
      reasons: Map.get(details, :reasons),
      observed_at: Map.get(details, :source_health_observed_at),
      details: details
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
