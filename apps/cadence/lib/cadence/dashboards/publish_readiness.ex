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

  @blocking_warning_codes [
    :missing_source_binding,
    :source_binding_interval_ambiguous,
    :missing_data_source,
    :disabled_data_source,
    :invalid_data_source_configuration,
    :source_unavailable,
    :source_connection_failed,
    :source_degraded,
    :unsupported_source_capability,
    :unsupported_observable_scope,
    :invalid_runtime_context
  ]
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

  defp blocking_warning?(%ResolveWarning{code: code}), do: code in @blocking_warning_codes
  defp blocking_warning?(_warning), do: false

  defp source_evidence_warning?(%ResolveWarning{code: code}),
    do: code in @source_evidence_warning_codes

  defp source_evidence_warning?(_warning), do: false

  defp warning_details(%ResolveWarning{} = warning) do
    %{
      source_warning_code: warning.code,
      source_warning_message: warning.message,
      severity: warning.severity,
      placement_id: warning.placement_id,
      details: warning.details || %{}
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
