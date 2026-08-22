defmodule Cadence.Dashboards.DocumentMigration do
  @moduledoc """
  Migration boundary for persisted dashboard document maps.

  Migrations operate on raw decoded JSON maps before they become
  `Cadence.Dashboards.Document` structs. That keeps schema evolution explicit and
  lets the store record a migration snapshot when persisted JSON changes.
  """

  alias Cadence.Dashboards.Document

  @current_schema_version 1

  defmodule Result do
    @moduledoc """
    Result of migrating a raw dashboard document map.
    """

    @type t :: %__MODULE__{
            document: Document.t(),
            changed?: boolean(),
            migrations: [binary()],
            source_schema_version: non_neg_integer() | nil,
            target_schema_version: pos_integer()
          }

    defstruct [
      :document,
      changed?: false,
      migrations: [],
      source_schema_version: nil,
      target_schema_version: 1
    ]
  end

  @type result :: {:ok, Result.t()} | {:error, term()}

  @spec current_schema_version() :: pos_integer()
  def current_schema_version, do: @current_schema_version

  @spec migrate_map(map()) :: result()
  def migrate_map(attrs) when is_map(attrs) do
    with {:ok, source_schema_version} <- source_schema_version(attrs),
         {:ok, migrated_attrs, migrations} <- migrate_attrs(attrs, source_schema_version) do
      {:ok,
       %Result{
         document: Document.from_map(migrated_attrs),
         changed?: migrations != [],
         migrations: migrations,
         source_schema_version: source_schema_version,
         target_schema_version: @current_schema_version
       }}
    end
  end

  @spec migrate_document(Document.t()) :: {:ok, Result.t()}
  def migrate_document(%Document{} = document) do
    {:ok,
     %Result{
       document: document,
       changed?: false,
       migrations: [],
       source_schema_version: document.schema_version,
       target_schema_version: @current_schema_version
     }}
  end

  defp source_schema_version(attrs) do
    case get_attr(attrs, :schema_version) do
      nil -> {:ok, 0}
      version when is_integer(version) and version >= 0 -> {:ok, version}
      version when is_binary(version) -> parse_schema_version(version)
      version -> {:error, {:invalid_dashboard_document_schema_version, version}}
    end
  end

  defp parse_schema_version(version) do
    case Integer.parse(version) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _invalid -> {:error, {:invalid_dashboard_document_schema_version, version}}
    end
  end

  defp migrate_attrs(attrs, @current_schema_version), do: {:ok, attrs, []}

  defp migrate_attrs(attrs, 0) do
    attrs
    |> put_schema_version()
    |> migrate_legacy_widgets()
    |> then(fn {migrated_attrs, migrations} ->
      {:ok, migrated_attrs, ["dashboard_document.v0_to_v1" | migrations]}
    end)
  end

  defp migrate_attrs(_attrs, version) when version > @current_schema_version do
    {:error, {:unsupported_dashboard_document_schema_version, version}}
  end

  defp put_schema_version(attrs) do
    Map.put(attrs, "schema_version", @current_schema_version)
  end

  defp migrate_legacy_widgets(attrs) do
    widgets = get_attr(attrs, :widgets)
    placements = get_attr(attrs, :placements)

    if is_list(widgets) and empty_placements?(placements) do
      migrated_attrs =
        attrs
        |> Map.put("placements", widgets_to_placements(widgets))
        |> Map.delete("widgets")
        |> Map.delete(:widgets)

      {migrated_attrs, ["dashboard_document.legacy_widgets_to_placements"]}
    else
      {attrs, []}
    end
  end

  defp empty_placements?(nil), do: true
  defp empty_placements?([]), do: true
  defp empty_placements?(_placements), do: false

  defp widgets_to_placements(widgets) do
    widgets
    |> Enum.with_index(1)
    |> Enum.map(fn {widget, index} -> widget_to_placement(widget, index) end)
  end

  defp widget_to_placement(widget, index) when is_map(widget) do
    widget_type_id =
      legacy_widget_type_id(get_attr(widget, :type) || get_attr(widget, :widget_type_id))

    %{
      "placement_id" =>
        get_attr(widget, :placement_id) || get_attr(widget, :widget_id) ||
          "legacy_widget_#{index}",
      "layout" => legacy_layout(widget),
      "content" => %{
        "kind" => "embedded",
        "widget_def" => %{
          "widget_type_id" => widget_type_id,
          "widget_type_version" => get_attr(widget, :widget_type_version) || 1,
          "title" => get_attr(widget, :title) || widget_type_id,
          "binding" => legacy_binding(widget, widget_type_id),
          "options" => get_attr(widget, :options) || %{}
        }
      }
    }
  end

  defp widget_to_placement(_widget, index) do
    %{
      "placement_id" => "legacy_widget_#{index}",
      "layout" => %{"x" => nil, "y" => nil, "w" => 4, "h" => 2},
      "content" => %{
        "kind" => "embedded",
        "widget_def" => %{
          "widget_type_id" => "cadence.unknown",
          "widget_type_version" => 1,
          "title" => "Legacy widget #{index}",
          "binding" => %{},
          "options" => %{}
        }
      }
    }
  end

  defp legacy_widget_type_id(value) when value in [:value_tile, "value_tile"],
    do: "cadence.value_tile"

  defp legacy_widget_type_id(value) when value in [:time_series, "time_series"],
    do: "cadence.time_series"

  defp legacy_widget_type_id(value) when value in [:constellation_health, "constellation_health"],
    do: "cadence.constellation_health"

  defp legacy_widget_type_id(value) when is_binary(value), do: value
  defp legacy_widget_type_id(_value), do: "cadence.unknown"

  defp legacy_layout(widget) do
    layout = get_attr(widget, :layout) || %{}

    %{
      "x" => legacy_layout_value(widget, layout, :x, nil),
      "y" => legacy_layout_value(widget, layout, :y, nil),
      "w" => legacy_layout_value(widget, layout, :w, 4),
      "h" => legacy_layout_value(widget, layout, :h, 2)
    }
  end

  defp legacy_layout_value(widget, layout, key, default) do
    get_attr(layout, key) || get_attr(widget, key) || default
  end

  defp legacy_binding(widget, widget_type_id) do
    binding = get_attr(widget, :binding)

    cond do
      is_map(binding) ->
        binding

      widget_type_id == "cadence.constellation_health" ->
        %{
          "observables" => [],
          "scope_mode" => "repeat",
          "data_mode" => "context",
          "value_type" => "engineering",
          "sampling" => "constellation_health",
          "overlays" => ["limits"]
        }

      true ->
        observable = get_attr(widget, :point_id) || get_attr(widget, :observable_id)
        mode = legacy_scope_mode(get_attr(widget, :mode))

        %{
          "observables" => List.wrap(observable),
          "scope_mode" => mode,
          "data_mode" => mode,
          "value_type" => "engineering",
          "sampling" => legacy_sampling(widget_type_id),
          "overlays" => List.wrap(get_attr(widget, :overlays) || ["limits", "quality"])
        }
    end
  end

  defp legacy_scope_mode(value) when value in [:fixed, "fixed", :override, "override"],
    do: "override"

  defp legacy_scope_mode(_value), do: "context"

  defp legacy_sampling("cadence.time_series"), do: "raw_series"
  defp legacy_sampling(_widget_type_id), do: "latest"

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
