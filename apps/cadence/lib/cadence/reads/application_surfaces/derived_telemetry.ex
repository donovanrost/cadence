defmodule Cadence.Reads.ApplicationSurfaces.DerivedTelemetry do
  @moduledoc "Declarative management projection for the Derived Telemetry application."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, SurfaceDocument, SurfaceQueryRequest}
  alias Cadence.Applications.SurfaceElements.{GeneratedForm, Stat, Table}
  alias Cadence.Auth.Scope
  alias Cadence.Extensions.Presentation.FieldDefinition
  alias Cadence.Governance
  alias Cadence.Reads.ApplicationSurfaces.TablePagination
  alias Cadence.Reads.DerivedTelemetry, as: DerivedTelemetryReads

  @impl true
  def load(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: "derived_telemetry",
          application_version: 1,
          query_id: "cadence.derived_telemetry.manage",
          query_version: 1,
          params: params
        }
      )
      when is_binary(organization_id) do
    definitions = Governance.list_derived_definitions(mission_id)

    latest_values =
      DerivedTelemetryReads.latest_values_for_mission(organization_id, mission_id, [])

    with {:ok, page} <- TablePagination.paginate(definitions, params) do
      {:ok,
       %SurfaceDocument{
         title: "Derived Telemetry",
         description:
           "Define calculated telemetry points from canonical point identifiers and inspect the governed definition set.",
         stats: stats(definitions, latest_values),
         form: definition_form(),
         table: definitions_table(page)
       }}
    end
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp stats(definitions, latest_values) do
    [
      %Stat{
        id: "definition_count",
        label: "Definitions",
        value: Integer.to_string(length(definitions)),
        tone: if(definitions == [], do: :attention, else: :ready)
      },
      %Stat{
        id: "latest_value_count",
        label: "Current values",
        value: Integer.to_string(length(latest_values)),
        tone: if(latest_values == [], do: :info, else: :ready)
      },
      %Stat{
        id: "evaluation_model",
        label: "Evaluation",
        value: "Governed snapshots",
        tone: :info
      }
    ]
  end

  defp definition_form do
    %GeneratedForm{
      id: "derived-telemetry-definition-form",
      title: "Add derived point",
      description:
        "Expressions reference canonical point IDs, for example HK.voltage * HK.current.",
      action_id: "save_definition",
      submit_label: "Save definition",
      success_message: "Derived telemetry definition saved.",
      fields: [
        %FieldDefinition{
          field: :point_id,
          label: "Point ID",
          type: :text,
          required: true,
          placeholder: "DERIVED.bus_power"
        },
        %FieldDefinition{
          field: :point_name,
          label: "Display name",
          type: :text,
          placeholder: "Bus power"
        },
        %FieldDefinition{
          field: :expression,
          label: "Expression",
          type: :textarea,
          required: true,
          placeholder: "HK.voltage * HK.current"
        }
      ]
    }
  end

  defp definitions_table(page) do
    %Table{
      id: "derived-telemetry-definitions",
      title: "Governed definitions",
      description: "The latest immutable version of every derived point definition.",
      columns: [
        %{key: :point, label: "Point", mono: true},
        %{key: :expression, label: "Expression", mono: true},
        %{key: :sources, label: "Sources", mono: true},
        %{key: :version, label: "Version", mono: false}
      ],
      page: %{page | items: Enum.map(page.items, &definition_row/1)},
      empty_title: "No derived points yet",
      empty_description: "Save the first definition to establish the governed configuration."
    }
  end

  defp definition_row(definition) do
    %{
      id: definition.derived_definition_id,
      point: definition.point_id,
      expression: definition.expression,
      sources: Enum.join(definition.source_point_ids, ", "),
      version: "v#{definition.version}"
    }
  end
end
