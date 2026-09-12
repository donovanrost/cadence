defmodule Cadence.Applications.ApplicationPreflights.TelemetryDecom do
  @moduledoc "Activation checks backed by Telemetry Decom's governed configuration and compiler."

  @behaviour Cadence.Applications.ApplicationPreflights.Provider

  alias Cadence.Applications.{ApplicationDefinition, HostContext, PreflightCheck}
  alias Cadence.Applications.TelemetryDecom, as: TelemetryDecomApplication
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Auth.Scope
  alias Cadence.{Catalog, MissionModels}

  @impl true
  def checks(
        %Scope{organization_id: organization_id},
        %HostContext{
          placement: :spacecraft,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        },
        %ApplicationDefinition{
          application_key: "telemetry_decom",
          version: 1,
          preflight_query_id: "cadence.telemetry_decom.activation_preflight"
        }
      )
      when is_binary(organization_id) do
    config = fetch_config(organization_id, mission_id, spacecraft_id)

    {:ok,
     [
       configuration_check(config),
       resource_check(config),
       mission_model_check(organization_id, mission_id, config),
       compilation_check(organization_id, mission_id, config)
     ]}
  end

  def checks(%Scope{}, %HostContext{}, %ApplicationDefinition{}),
    do: {:error, :unsupported_application_preflight_context}

  defp fetch_config(organization_id, mission_id, spacecraft_id) do
    case TelemetryDecomApplication.fetch_config(organization_id, mission_id, spacecraft_id) do
      {:ok, config} -> config
      {:error, :not_configured} -> nil
    end
  end

  defp configuration_check(nil) do
    check(
      "configuration",
      :configuration,
      :blocked,
      "Configuration required",
      "Select a catalog revision and packet APIDs before requesting mission changes."
    )
  end

  defp configuration_check(%Config{enabled: false, configuration_version: version}) do
    check(
      "configuration",
      :configuration,
      :attention,
      "Configuration disabled",
      "Activation will publish removal of this spacecraft's packet claims.",
      "v#{version}"
    )
  end

  defp configuration_check(%Config{configuration_version: version}) do
    check(
      "configuration",
      :configuration,
      :ready,
      "Configuration versioned",
      "The saved spacecraft configuration is available to the activation compiler.",
      "v#{version}"
    )
  end

  defp resource_check(nil) do
    check(
      "packet-apid-binding",
      :resource,
      :blocked,
      "Packet binding unavailable",
      "No APIDs are declared because the application is not configured."
    )
  end

  defp resource_check(%Config{enabled: false}) do
    check(
      "packet-apid-binding",
      :resource,
      :ready,
      "Packet binding disabled",
      "The disabled configuration contributes no packet bindings to the next mission basis.",
      "0 APIDs"
    )
  end

  defp resource_check(%Config{handled_apids: []}) do
    check(
      "packet-apid-binding",
      :resource,
      :blocked,
      "Packet binding empty",
      "Select at least one compatible packet before requesting mission changes.",
      "0 APIDs"
    )
  end

  defp resource_check(%Config{} = config) do
    count = length(config.handled_apids)

    check(
      "packet-apid-binding",
      :resource,
      :ready,
      "Shared packet input ready",
      "Every selected APID resolves packet-model input for this application; other applications may read the same packet.",
      "#{count} #{pluralize(count, "APID", "APIDs")}"
    )
  end

  defp mission_model_check(_organization_id, _mission_id, nil) do
    mission_model_result(:unavailable)
  end

  defp mission_model_check(organization_id, mission_id, config) do
    enabled =
      organization_id
      |> TelemetryDecomApplication.list_configs(mission_id)
      |> Enum.filter(& &1.enabled)

    configs = if enabled == [], do: [config], else: enabled

    configs
    |> Enum.map(& &1.catalog_revision_id)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, models} ->
      with {:ok, revision} <- Catalog.fetch_revision(organization_id, mission_id, id),
           {:ok, model} <-
             MissionModels.fetch_revision(
               organization_id,
               mission_id,
               revision.mission_model_revision_id
             ) do
        {:cont, {:ok, [{model.revision_id, model.status} | models]}}
      else
        _ -> {:halt, :unavailable}
      end
    end)
    |> mission_model_result()
  end

  defp mission_model_result({:ok, models}) do
    case Enum.uniq(models) do
      [{_id, :approved}] ->
        check(
          "mission-model-approval",
          :configuration,
          :ready,
          "Mission model approved",
          "The mission configuration basis uses one approved mission model revision."
        )

      [{_id, _status}] ->
        check(
          "mission-model-approval",
          :configuration,
          :blocked,
          "Mission model approval required",
          "Approve the mission model revision in Catalog before requesting mission changes."
        )

      _ ->
        check(
          "mission-model-approval",
          :configuration,
          :blocked,
          "Mission model revisions differ",
          "Enabled configurations must use one mission model revision before requesting mission changes."
        )
    end
  end

  defp mission_model_result(:unavailable) do
    check(
      "mission-model-approval",
      :configuration,
      :blocked,
      "Mission model review unavailable",
      "Save a configuration with an available mission model revision before requesting mission changes."
    )
  end

  defp compilation_check(_organization_id, _mission_id, nil) do
    check(
      "runtime-compilation",
      :compilation,
      :blocked,
      "Compilation unavailable",
      "A saved configuration is required before runtime artifacts can be compiled."
    )
  end

  defp compilation_check(_organization_id, _mission_id, %Config{enabled: false}) do
    check(
      "runtime-compilation",
      :compilation,
      :ready,
      "Removal compiles cleanly",
      "The disabled configuration is excluded from the next mission binding set."
    )
  end

  defp compilation_check(organization_id, mission_id, %Config{} = config) do
    case TelemetryDecomApplication.preview(organization_id, mission_id, config) do
      {:ok, preview} -> compilation_result(preview)
      {:error, _reason} -> compilation_unavailable()
    end
  end

  defp compilation_result(preview) do
    diagnostics = preview.compilation.compiler_result.diagnostics
    error_count = Enum.count(diagnostics, &(&1.severity == :error))
    warning_count = Enum.count(diagnostics, &(&1.severity == :warning))
    definition_count = length(preview.compilation.compiler_result.packet_definitions)

    cond do
      error_count > 0 ->
        check(
          "runtime-compilation",
          :compilation,
          :blocked,
          "Compilation blocked",
          "The selected packet set produced #{error_count} compiler errors.",
          "#{definition_count} definitions"
        )

      warning_count > 0 ->
        check(
          "runtime-compilation",
          :compilation,
          :attention,
          "Compilation has advisories",
          "Runtime artifacts compiled with #{warning_count} warnings for operator review.",
          "#{definition_count} definitions"
        )

      true ->
        check(
          "runtime-compilation",
          :compilation,
          :ready,
          "Runtime artifacts compiled",
          "The selected packet set produced a bounded runtime definition set.",
          "#{definition_count} definitions"
        )
    end
  end

  defp compilation_unavailable do
    check(
      "runtime-compilation",
      :compilation,
      :blocked,
      "Compilation failed",
      "Cadence could not resolve and compile the configured catalog revision."
    )
  end

  defp check(id, category, state, title, detail, value \\ nil) do
    %PreflightCheck{
      id: id,
      category: category,
      state: state,
      title: title,
      detail: detail,
      value: value
    }
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
