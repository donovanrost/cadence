defmodule Cadence.Dashboards.AnnotationCompositionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Annotation, AnnotationComposition, AnnotationSpan, WidgetDef}

  test "normalizes explicit layer references from widget options" do
    widget_def = %WidgetDef{
      options: %{
        "annotation_layers" => [
          "mission-contacts",
          %{"layer_id" => "source-status", "enabled" => true},
          %{layer_id: "disabled-layer", enabled: false},
          "mission-contacts"
        ]
      }
    }

    assert AnnotationComposition.layer_ids(widget_def) == ["mission-contacts", "source-status"]
  end

  test "selects only explicitly composed layers and defaults to none" do
    annotations = [
      annotation("contact-1", "mission-contacts"),
      annotation("outage-1", "source-status")
    ]

    assert AnnotationComposition.select(annotations, []) == []

    assert [%Annotation{annotation_id: "outage-1"}] =
             AnnotationComposition.select(annotations, ["source-status"])
  end

  defp annotation(annotation_id, layer_id) do
    %Annotation{
      annotation_id: annotation_id,
      provider_id: "test.provider",
      layer_id: layer_id,
      title: annotation_id,
      span: %AnnotationSpan{kind: :point, starts_at: ~U[2026-08-06 04:00:00Z]}
    }
  end
end
