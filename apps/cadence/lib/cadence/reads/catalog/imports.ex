defmodule Cadence.Reads.Catalog.Imports do
  @moduledoc false

  import Cadence.Reads.Catalog.Presentation

  alias Cadence.Catalog

  def catalog_import_run_show(organization_id, mission_id, params) do
    with {:ok, run_id} <- subject_id(params, "import_run_id"),
         {:ok, run} <- Catalog.fetch_import_run(organization_id, mission_id, run_id) do
      summary = Map.get(run.result_document || %{}, "mission_model")

      {:ok,
       %{
         "navigation" => %{
           "breadcrumbs" => [
             %{"label" => "Mission", "href" => mission_href(mission_id)},
             %{"label" => "Catalog", "href" => "/missions/#{mission_id}/catalog"},
             %{
               "label" => "Artifact",
               "href" => "/missions/#{mission_id}/catalog/artifacts/#{run.artifact_id}"
             },
             %{"label" => "Import run", "href" => nil}
           ]
         },
         "status" => %{
           "label" => import_status_label(run.status),
           "tone" => import_status_tone(run.status)
         },
         "run_details" => %{
           "importer" => %{
             "id" => "catalog-importer-version",
             "label" => "#{run.importer_key} v#{run.importer_version}"
           },
           "started_at" => format_datetime(run.started_at),
           "completed_at" => format_datetime(run.completed_at)
         },
         "mission_model" => mission_model_run(summary),
         "diagnostic_groups" => diagnostic_groups(run.diagnostics),
         "failure_reason" => failure_reason(run)
       }}
    end
  end

  defp mission_model_run(nil), do: nil

  defp mission_model_run(summary) when is_map(summary),
    do: %{
      "id" => "catalog-import-mission-model",
      "revision_id" => Map.get(summary, "revision_id"),
      "declaration_count" => Map.get(summary, "declaration_count"),
      "plan_count" => map_size(Map.get(summary, "plans") || %{})
    }

  defp diagnostic_groups(diagnostics) do
    [:error, :warning, :info]
    |> Enum.flat_map(fn severity ->
      items = Enum.filter(diagnostics || [], &(Map.get(&1, :severity) == severity))

      if items == [],
        do: [],
        else: [
          %{
            "title" => "#{severity_label(severity)} (#{length(items)})",
            "items" => Enum.map(items, &diagnostic_row/1)
          }
        ]
    end)
  end

  defp severity_label(:error), do: "Errors"
  defp severity_label(:warning), do: "Warnings"
  defp severity_label(:info), do: "Info"

  defp diagnostic_row(diagnostic) do
    metadata = Map.get(diagnostic, :metadata, %{}) || %{}

    detail =
      [
        metadata_value(metadata, "consumption_summary", "Built-in telemetry"),
        metadata_value(metadata, "consumption_status", "Status"),
        metadata_value(metadata, "packet_name", "Packet"),
        metadata_value(metadata, "entry_name", "Entry"),
        metadata_value(metadata, "point_name", "Point"),
        metadata_value(metadata, "type_name", "Type"),
        metadata_value(metadata, "base_type", "Base type"),
        metadata_value(metadata, "point_id", "Point ID"),
        metadata_value(metadata, "type_id", "Type ID")
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        values -> Enum.join(values, " | ")
      end

    %{
      "code" => diagnostic.code,
      "message" => diagnostic.message,
      "detail" => detail,
      "path" => if(diagnostic.path == [], do: nil, else: Enum.join(diagnostic.path, " / "))
    }
  end

  defp metadata_value(metadata, key, label) do
    case Map.get(metadata, key) do
      value when is_binary(value) and value != "" -> "#{label}: #{value}"
      _ -> nil
    end
  end

  defp failure_reason(%{status: :failed, failure_reason: {:exception, message}})
       when is_binary(message), do: message

  defp failure_reason(%{status: :failed, failure_reason: {kind, reason}}) when is_atom(kind),
    do: "#{kind}: #{inspect(reason)}"

  defp failure_reason(%{status: :failed, failure_reason: reason}) when not is_nil(reason),
    do: inspect(reason)

  defp failure_reason(_run), do: nil
end
