defmodule Cadence.Applications.SurfaceDocumentTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.SurfaceDocument

  alias Cadence.Applications.SurfaceElements.{
    Activity,
    ActivityItem,
    Diagnostic,
    Diagnostics,
    GeneratedForm,
    Stat,
    Table
  }

  alias Cadence.Extensions.Presentation.FieldDefinition
  alias Cadence.Listing.Page

  test "accepts a complete bounded document whose form action is surface-declared" do
    assert :ok = SurfaceDocument.validate(valid_document(), ["save_configuration"])
  end

  test "rejects duplicate block DOM identities" do
    document = valid_document()
    activity = %Activity{document.activity | id: document.table.id}

    assert {:error, :invalid_application_surface_document} =
             SurfaceDocument.validate(%SurfaceDocument{document | activity: activity})
  end

  test "rejects duplicate stats and overlong activity projections" do
    document = valid_document()
    duplicate_stat = hd(document.stats)

    assert {:error, :invalid_application_surface_stat} =
             SurfaceDocument.validate(%SurfaceDocument{
               document
               | stats: [duplicate_stat, duplicate_stat]
             })

    items = Enum.map(1..21, &activity_item("event-#{&1}"))

    assert {:error, :invalid_application_surface_activity} =
             SurfaceDocument.validate(%SurfaceDocument{
               document
               | activity: %Activity{document.activity | items: items}
             })
  end

  test "rejects duplicate generated fields" do
    document = valid_document()
    field = hd(document.form.fields)
    form = %GeneratedForm{document.form | fields: [field, field]}

    assert {:error, :invalid_application_surface_form} =
             SurfaceDocument.validate(%SurfaceDocument{document | form: form})
  end

  test "rejects a form action not declared by its surface" do
    assert {:error, :undeclared_application_surface_action} =
             SurfaceDocument.validate(valid_document(), ["inspect_configuration"])
  end

  defp valid_document do
    %SurfaceDocument{
      title: "Application configuration",
      description: "A fully bounded host-rendered document.",
      stats: [
        %Stat{id: "configured", label: "Configured", value: "1", tone: :ready}
      ],
      diagnostics: %Diagnostics{
        id: "configuration-diagnostics",
        title: "Configuration findings",
        items: [
          %Diagnostic{
            id: "advisory",
            code: "configuration.advisory",
            severity: :warning,
            title: "Configuration advisory",
            detail: "Review the selected configuration."
          }
        ],
        total_count: 1
      },
      form: %GeneratedForm{
        id: "configuration-form",
        title: "Configure application",
        action_id: "save_configuration",
        submit_label: "Save configuration",
        success_message: "Configuration saved.",
        fields: [
          %FieldDefinition{field: :name, label: "Name", type: :text, required: true}
        ]
      },
      table: %Table{
        id: "configuration-table",
        title: "Configurations",
        columns: [%{key: :name, label: "Name", mono: false}],
        page: %Page{
          items: [%{id: "configuration-1", name: "Primary"}],
          total_count: 1,
          page: 1,
          page_size: 20
        },
        empty_title: "No configurations"
      },
      activity: %Activity{
        id: "configuration-activity",
        title: "Configuration activity",
        items: [activity_item("event-1")],
        empty_title: "No configuration activity"
      }
    }
  end

  defp activity_item(id) do
    %ActivityItem{
      id: id,
      title: "Configuration saved",
      detail: "The application configuration changed.",
      tone: :info
    }
  end
end
