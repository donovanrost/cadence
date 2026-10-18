defmodule Cadence.Dashboards.AuthoringWidgetTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{AuthoringWidget, DocumentCodec}

  @fixture Path.expand("../../fixtures/dashboards/value_tile_latest.v1.json", __DIR__)

  setup do
    document = DocumentCodec.load!(@fixture)
    %{document: document, placement: hd(document.placements)}
  end

  test "title-only edits preserve all unedited authored semantics", c do
    placement = %{
      c.placement
      | data_override: %{realm: :rehearsal, source_mode: :primary},
        limit_override: %{semantics_mode: :current},
        overrides: %{future: "retained"},
        widget_def: %{
          c.placement.widget_def
          | binding:
              Map.merge(c.placement.widget_def.binding, %{
                sampling: :decimated,
                value_type: :raw,
                aggregation: %{function: :mean}
              }),
            options: %{"precision" => 4, "show_unit" => false, "future" => "retained"}
        }
    }

    fields = Map.put(AuthoringWidget.fields(placement), "title", "New title")

    assert {:ok, next} =
             AuthoringWidget.build(
               c.document,
               fields,
               AuthoringWidget.observables(placement),
               placement
             )

    assert next == %{placement | widget_def: %{placement.widget_def | title: "New title"}}
  end

  test "edited options replace their string key without erasing other options", c do
    placement = %{
      c.placement
      | widget_def: %{c.placement.widget_def | options: %{"precision" => 4, "show_unit" => false}}
    }

    fields = Map.put(AuthoringWidget.fields(placement), "precision", "3")

    assert {:ok, next} =
             AuthoringWidget.build(
               c.document,
               fields,
               AuthoringWidget.observables(placement),
               placement
             )

    assert next.widget_def.options == %{:precision => 3, "show_unit" => false}
  end

  test "charts retain all selected observables and canonical style choices", c do
    fields =
      Map.merge(AuthoringWidget.defaults(), %{
        "title" => "Power",
        "type" => "time_series",
        "legend_mode" => "hidden",
        "line_width" => "bold"
      })

    observables = Enum.map(1..8, &"point-#{&1}")
    assert {:ok, next} = AuthoringWidget.build(c.document, fields, observables, nil)
    assert next.widget_def.binding.observables == observables
    assert next.widget_def.options.legend_mode == "hidden"
    assert next.widget_def.options.line_width == "bold"

    assert {:error, :invalid_widget} =
             AuthoringWidget.build(c.document, fields, observables ++ ["point-9"], nil)
  end

  test "scope, repeat and layout are retained when only the title changes", c do
    fields =
      Map.merge(AuthoringWidget.defaults(), %{
        "title" => "Fleet",
        "type" => "time_series",
        "mode" => "repeat"
      })

    assert {:ok, placement} = AuthoringWidget.build(c.document, fields, ["battery"], nil)
    fields = Map.put(AuthoringWidget.fields(placement), "title", "Fleet power")
    assert {:ok, next} = AuthoringWidget.build(c.document, fields, ["battery"], placement)
    assert next == %{placement | widget_def: %{placement.widget_def | title: "Fleet power"}}
  end

  test "library references and unsupported versions cannot be converted into embedded edits", c do
    for placement <- [
          %{
            c.placement
            | content_kind: :library,
              library_widget_id: "library",
              library_version: 2
          },
          %{c.placement | widget_def: %{c.placement.widget_def | widget_type_version: 2}}
        ] do
      assert {:error, :unsupported_widget} =
               AuthoringWidget.build(
                 c.document,
                 AuthoringWidget.fields(c.placement),
                 ["battery"],
                 placement
               )
    end
  end

  test "operational observables are checked against the widget's explicit scope, not dashboard defaults",
       c do
    c = %{
      c
      | document: %{
          c.document
          | defaults: %{"scope" => %{"primary" => %{"kind" => "mission", "mode" => "context"}}}
        }
    }

    fields =
      Map.merge(AuthoringWidget.defaults(), %{
        "title" => "RF SNR",
        "binding_source" => "operational_observables",
        "mode" => "scope",
        "scope_kind" => "link",
        "scope_id" => "link-alpha"
      })

    assert {:ok, placement} = AuthoringWidget.build(c.document, fields, ["link.snr_db"], nil)
    edited = Map.put(AuthoringWidget.fields(placement), "title", "Renamed RF SNR")
    assert {:ok, next} = AuthoringWidget.build(c.document, edited, ["link.snr_db"], placement)
    assert next == %{placement | widget_def: %{placement.widget_def | title: "Renamed RF SNR"}}

    invalid = Map.put(fields, "scope_kind", "mission")

    assert {:error, {:invalid_binding, _}} =
             AuthoringWidget.build(c.document, invalid, ["link.snr_db"], nil)
  end

  test "operational repeats use the declared repeat scope", c do
    c = %{
      c
      | document: %{
          c.document
          | defaults: %{"scope" => %{"primary" => %{"kind" => "mission", "mode" => "context"}}}
        }
    }

    fields =
      Map.merge(AuthoringWidget.defaults(), %{
        "title" => "Links",
        "type" => "status_matrix",
        "binding_source" => "operational_observables",
        "mode" => "repeat",
        "repeat_over" => "link"
      })

    assert {:ok, placement} = AuthoringWidget.build(c.document, fields, ["link.snr_db"], nil)
    assert placement.repeat.over == :link
  end
end
