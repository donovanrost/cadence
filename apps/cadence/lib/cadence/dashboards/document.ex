defmodule Cadence.Dashboards.Document do
  @moduledoc """
  Versioned dashboard document consumed by the dashboard engine.

  This is the in-memory contract for the new `Cadence.Dashboards` bounded
  context. Persistence rows, draft/published pointers, and LiveView state wrap
  this document; they are not part of the document itself.
  """

  alias Cadence.Dashboards.{
    DataContext,
    LimitContext,
    Placement,
    ScopeContext,
    TimeContext,
    ValidationResult,
    WidgetFrameContract,
    WidgetRegistry
  }

  @default_grid_columns 12
  @default_max_rows 24

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          dashboard_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          name: binary(),
          description: binary() | nil,
          defaults: map(),
          grid: map(),
          placements: [Placement.t()],
          metadata: map()
        }

  defstruct [
    :dashboard_id,
    :organization_id,
    :mission_id,
    :name,
    :description,
    schema_version: 1,
    defaults: %{},
    grid: %{columns: 12, row_height_px: 64, gap_px: 8},
    placements: [],
    metadata: %{}
  ]

  @supported_schema_versions [1]

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      schema_version: get_attr(attrs, :schema_version) || 1,
      dashboard_id: get_attr(attrs, :dashboard_id),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      name: get_attr(attrs, :name),
      description: get_attr(attrs, :description),
      defaults: get_attr(attrs, :defaults) || %{},
      grid: normalize_grid(get_attr(attrs, :grid) || %{}),
      placements:
        attrs
        |> get_attr(:placements)
        |> List.wrap()
        |> Enum.map(&Placement.from_map/1),
      metadata: get_attr(attrs, :metadata) || %{}
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = document) do
    %{
      schema_version: document.schema_version,
      dashboard_id: document.dashboard_id,
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      name: document.name,
      description: document.description,
      defaults: document.defaults,
      grid: document.grid,
      placements: Enum.map(document.placements, &Placement.to_map/1),
      metadata: document.metadata || %{}
    }
  end

  @spec version(t()) :: pos_integer() | nil
  def version(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    get_attr(metadata, :version) || get_attr(metadata, :dashboard_version)
  end

  @spec put_version(t(), pos_integer()) :: t()
  def put_version(%__MODULE__{} = document, version)
      when is_integer(version) and version > 0 do
    metadata =
      document.metadata
      |> ensure_metadata()
      |> Map.delete("version")
      |> Map.delete(:dashboard_version)
      |> Map.delete("dashboard_version")
      |> Map.put(:version, version)

    %__MODULE__{document | metadata: metadata}
  end

  @spec replace_placements(t(), [Placement.t()]) :: t()
  def replace_placements(%__MODULE__{} = document, placements) when is_list(placements) do
    %__MODULE__{document | placements: placements}
  end

  @spec put_placement(t(), Placement.t()) :: t()
  def put_placement(%__MODULE__{} = document, %Placement{} = placement) do
    replace_placements(document, put_placement_in_list(document.placements, placement))
  end

  @spec remove_placement(t(), binary()) :: t()
  def remove_placement(%__MODULE__{} = document, placement_id) when is_binary(placement_id) do
    placements = Enum.reject(document.placements, &(&1.placement_id == placement_id))
    replace_placements(document, placements)
  end

  @spec apply_layouts(t(), [map()]) :: t()
  def apply_layouts(%__MODULE__{} = document, layouts) when is_list(layouts) do
    layouts_by_placement_id =
      layouts
      |> Enum.flat_map(&layout_entry/1)
      |> Map.new()

    placements =
      Enum.map(document.placements, fn %Placement{} = placement ->
        case Map.get(layouts_by_placement_id, placement.placement_id) do
          nil -> placement
          layout -> apply_layout(document, placement, layout)
        end
      end)

    replace_placements(document, placements)
  end

  @spec validate(t()) :: ValidationResult.t()
  def validate(%__MODULE__{} = document) do
    %ValidationResult{}
    |> validate_schema_version(document)
    |> validate_required_fields(document)
    |> validate_runtime_defaults(document)
    |> validate_grid(document)
    |> validate_placements(document)
  end

  defp validate_schema_version(result, %__MODULE__{schema_version: version}) do
    if version in @supported_schema_versions do
      result
    else
      ValidationResult.add_error(result, :unsupported_schema_version, %{
        schema_version: version
      })
    end
  end

  defp validate_required_fields(result, document) do
    [
      {:dashboard_id, document.dashboard_id},
      {:organization_id, document.organization_id},
      {:mission_id, document.mission_id},
      {:name, document.name}
    ]
    |> Enum.reduce(result, fn {field, value}, acc ->
      if present_string?(value) do
        acc
      else
        ValidationResult.add_error(acc, :missing_required_field, %{field: field})
      end
    end)
  end

  defp validate_runtime_defaults(result, %__MODULE__{defaults: defaults}) when is_map(defaults) do
    result
    |> validate_default_context(:time, TimeContext, get_attr(defaults, :time))
    |> validate_default_context(:scope, ScopeContext, get_attr(defaults, :scope))
    |> validate_default_context(:data, DataContext, get_attr(defaults, :data))
    |> validate_default_context(:limits, LimitContext, get_attr(defaults, :limits))
  end

  defp validate_runtime_defaults(result, %__MODULE__{}) do
    ValidationResult.add_error(result, :invalid_runtime_defaults, %{
      field: :defaults,
      reason: :not_a_map
    })
  end

  defp validate_default_context(result, _context, _module, nil), do: result

  defp validate_default_context(result, context, module, attrs) when is_map(attrs) do
    attrs
    |> module.from_map()
    |> module.validate()
    |> case do
      [] ->
        result

      errors ->
        ValidationResult.add_error(result, :invalid_runtime_default_context, %{
          context: context,
          errors: errors
        })
    end
  end

  defp validate_default_context(result, context, _module, _attrs) do
    ValidationResult.add_error(result, :invalid_runtime_default_context, %{
      context: context,
      errors: [:not_a_map]
    })
  end

  defp ensure_metadata(metadata) when is_map(metadata), do: metadata
  defp ensure_metadata(_metadata), do: %{}

  defp put_placement_in_list([], %Placement{} = placement), do: [placement]

  defp put_placement_in_list(
         [%Placement{placement_id: placement_id} | rest],
         %Placement{placement_id: placement_id} = placement
       ) do
    [placement | rest]
  end

  defp put_placement_in_list([existing | rest], %Placement{} = placement) do
    [existing | put_placement_in_list(rest, placement)]
  end

  defp layout_entry(%{} = attrs) do
    with placement_id when is_binary(placement_id) <- layout_placement_id(attrs),
         x when is_integer(x) <- get_attr(attrs, :x),
         y when is_integer(y) <- get_attr(attrs, :y),
         w when is_integer(w) <- get_attr(attrs, :w),
         h when is_integer(h) <- get_attr(attrs, :h) do
      [{placement_id, %{x: x, y: y, w: w, h: h}}]
    else
      _malformed -> []
    end
  end

  defp layout_entry(_attrs), do: []

  defp layout_placement_id(attrs) do
    get_attr(attrs, :placement_id) || get_attr(attrs, :widget_id)
  end

  defp apply_layout(%__MODULE__{} = document, %Placement{} = placement, layout) do
    columns = grid_columns(document)
    minimum = minimum_layout(placement)

    w = layout |> Map.fetch!(:w) |> min(columns) |> max(minimum.w)
    h = layout |> Map.fetch!(:h) |> min(@default_max_rows) |> max(minimum.h)

    next_layout =
      placement.layout
      |> Map.merge(%{
        x: layout |> Map.fetch!(:x) |> max(0) |> min(columns - w),
        y: layout |> Map.fetch!(:y) |> max(0) |> min(@default_max_rows - 1),
        w: w,
        h: h
      })

    %Placement{placement | layout: next_layout}
  end

  defp grid_columns(%__MODULE__{grid: grid}) when is_map(grid) do
    case get_attr(grid, :columns) do
      columns when is_integer(columns) and columns > 0 -> columns
      _missing -> @default_grid_columns
    end
  end

  defp minimum_layout(%Placement{widget_def: %Cadence.Dashboards.WidgetDef{} = widget_def}) do
    case WidgetRegistry.fetch_type(widget_def.widget_type_id, widget_def.widget_type_version) do
      {:ok, widget_type} ->
        %{w: widget_type.layout_contract.min_w, h: widget_type.layout_contract.min_h}

      {:error, _reason} ->
        %{w: 1, h: 1}
    end
  end

  defp minimum_layout(%Placement{}), do: %{w: 1, h: 1}

  defp validate_grid(result, %__MODULE__{grid: grid}) do
    columns = Map.get(grid, :columns)
    row_height_px = Map.get(grid, :row_height_px)
    gap_px = Map.get(grid, :gap_px)

    cond do
      not positive_integer?(columns) ->
        ValidationResult.add_error(result, :invalid_grid, %{field: :columns})

      not positive_integer?(row_height_px) ->
        ValidationResult.add_error(result, :invalid_grid, %{field: :row_height_px})

      not non_negative_integer?(gap_px) ->
        ValidationResult.add_error(result, :invalid_grid, %{field: :gap_px})

      true ->
        result
    end
  end

  defp validate_placements(result, %__MODULE__{placements: placements, grid: grid}) do
    result
    |> validate_unique_placement_ids(placements)
    |> then(fn acc ->
      Enum.reduce(placements, acc, &validate_placement(&2, &1, grid))
    end)
  end

  defp validate_unique_placement_ids(result, placements) do
    ids = Enum.map(placements, & &1.placement_id)

    if Enum.any?(ids, &is_nil/1) or length(ids) != length(Enum.uniq(ids)) do
      ValidationResult.add_error(result, :duplicate_placement_ids, %{})
    else
      result
    end
  end

  defp validate_placement(result, %Placement{} = placement, grid) do
    result
    |> validate_layout(placement, grid)
    |> validate_widget(placement)
    |> validate_repeat(placement)
  end

  defp validate_layout(result, %Placement{layout: layout, placement_id: placement_id}, grid) do
    columns = Map.get(grid, :columns)
    x = Map.get(layout, :x)
    y = Map.get(layout, :y)
    w = Map.get(layout, :w)
    h = Map.get(layout, :h)

    cond do
      not Enum.all?([w, h], &positive_integer?/1) ->
        ValidationResult.add_error(result, :invalid_placement_layout, %{
          placement_id: placement_id,
          field: :size
        })

      auto_position?(x, y) ->
        result

      not Enum.all?([x, y], &non_negative_integer?/1) ->
        ValidationResult.add_error(result, :invalid_placement_layout, %{
          placement_id: placement_id,
          field: :position
        })

      x + w > columns ->
        ValidationResult.add_error(result, :placement_outside_grid, %{
          placement_id: placement_id,
          columns: columns
        })

      true ->
        result
    end
  end

  defp auto_position?(nil, nil), do: true
  defp auto_position?(_x, _y), do: false

  defp validate_widget(result, %Placement{widget_def: nil, placement_id: placement_id}) do
    ValidationResult.add_error(result, :missing_widget_def, %{placement_id: placement_id})
  end

  defp validate_widget(result, %Placement{widget_def: widget_def} = placement) do
    case WidgetRegistry.fetch_type(widget_def.widget_type_id, widget_def.widget_type_version) do
      {:ok, widget_type} ->
        result
        |> validate_widget_layout(placement, widget_type)
        |> validate_widget_binding(placement, widget_type)

      {:error, reason} ->
        ValidationResult.add_warning(result, reason, %{
          placement_id: placement.placement_id,
          widget_type_id: widget_def.widget_type_id,
          widget_type_version: widget_def.widget_type_version
        })
    end
  end

  defp validate_widget_layout(result, %Placement{} = placement, widget_type) do
    layout = placement.layout
    contract = widget_type.layout_contract

    if Map.get(layout, :w) < contract.min_w or Map.get(layout, :h) < contract.min_h do
      ValidationResult.add_error(result, :placement_below_widget_minimum, %{
        placement_id: placement.placement_id,
        widget_type_id: placement.widget_def.widget_type_id,
        minimum: %{w: contract.min_w, h: contract.min_h}
      })
    else
      result
    end
  end

  defp validate_widget_binding(result, %Placement{} = placement, widget_type) do
    binding = placement.widget_def.binding
    schema = widget_type.binding_schema
    observables = Map.get(binding, :observables, [])
    count = length(observables)

    cond do
      count < schema.min_observables or count > schema.max_observables ->
        ValidationResult.add_error(result, :invalid_observable_count, %{
          placement_id: placement.placement_id,
          widget_type_id: placement.widget_def.widget_type_id,
          count: count,
          allowed: %{min: schema.min_observables, max: schema.max_observables}
        })

      Map.get(binding, :scope_mode) not in schema.scope_modes ->
        ValidationResult.add_error(result, :unsupported_scope_mode, %{
          placement_id: placement.placement_id,
          scope_mode: Map.get(binding, :scope_mode)
        })

      Map.get(binding, :sampling) not in schema.sampling_modes ->
        ValidationResult.add_error(result, :unsupported_sampling_mode, %{
          placement_id: placement.placement_id,
          sampling: Map.get(binding, :sampling)
        })

      true ->
        validate_widget_frame_contract(result, placement, widget_type)
    end
  end

  defp validate_widget_frame_contract(result, %Placement{} = placement, widget_type) do
    case WidgetFrameContract.primary_frame_specs(widget_type, placement.widget_def.binding) do
      {:ok, _frame_specs} ->
        result

      {:error, details} ->
        ValidationResult.add_error(
          result,
          :unsupported_widget_frame_contract,
          Map.put(details, :placement_id, placement.placement_id)
        )
    end
  end

  defp validate_repeat(result, %Placement{repeat: nil}), do: result

  defp validate_repeat(result, %Placement{repeat: repeat, placement_id: placement_id}) do
    cond do
      Map.get(repeat, :axis) != :scope ->
        ValidationResult.add_error(result, :unsupported_repeat_axis, %{placement_id: placement_id})

      Map.get(repeat, :over) not in [:spacecraft, :contact, :ground_station, :transport, :link] ->
        ValidationResult.add_error(result, :unsupported_repeat_scope, %{
          placement_id: placement_id
        })

      not positive_integer?(Map.get(repeat, :max_instances)) ->
        ValidationResult.add_error(result, :invalid_repeat_max_instances, %{
          placement_id: placement_id
        })

      Map.get(repeat, :max_instances) > 24 ->
        ValidationResult.add_error(result, :repeat_instance_limit_exceeded, %{
          placement_id: placement_id,
          max_instances: Map.get(repeat, :max_instances)
        })

      true ->
        result
    end
  end

  defp normalize_grid(grid) do
    %{
      columns: get_attr(grid, :columns) || 12,
      row_height_px: get_attr(grid, :row_height_px) || 64,
      gap_px: get_attr(grid, :gap_px) || 8,
      density: normalize_density(get_attr(grid, :density)),
      responsive_policy: normalize_responsive_policy(get_attr(grid, :responsive_policy))
    }
  end

  defp normalize_density(nil), do: :comfortable
  defp normalize_density("comfortable"), do: :comfortable
  defp normalize_density("compact"), do: :compact
  defp normalize_density(value) when value in [:comfortable, :compact], do: value
  defp normalize_density(_value), do: :comfortable

  defp normalize_responsive_policy(nil), do: :single_layout_collapse
  defp normalize_responsive_policy("single_layout_collapse"), do: :single_layout_collapse
  defp normalize_responsive_policy(:single_layout_collapse), do: :single_layout_collapse
  defp normalize_responsive_policy(_value), do: :single_layout_collapse

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
