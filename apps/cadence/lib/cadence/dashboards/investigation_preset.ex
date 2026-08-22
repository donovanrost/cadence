defmodule Cadence.Dashboards.InvestigationPreset do
  @moduledoc """
  Durable dashboard investigation preset.

  Presets capture enough runtime context and finding metadata for an operator to
  return to a dashboard investigation without relying on transient LiveView
  state. The payload remains versioned so later workflow-specific preset kinds
  can evolve without changing the row identity contract.
  """

  alias Cadence.Ids

  @kinds [:comparison]

  @type kind :: :comparison

  @type t :: %__MODULE__{
          dashboard_investigation_preset_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          dashboard_id: binary(),
          name: binary(),
          description: binary() | nil,
          schema: binary(),
          preset_kind: kind(),
          runtime_query: map(),
          payload: map(),
          primary_data_view: binary() | nil,
          compare_data_view: binary() | nil,
          affected_placement_ids: [binary()],
          created_by: binary() | nil,
          updated_by: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :dashboard_investigation_preset_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :name,
    :description,
    :schema,
    :preset_kind,
    :primary_data_view,
    :compare_data_view,
    :created_by,
    :updated_by,
    :inserted_at,
    :updated_at,
    runtime_query: %{},
    payload: %{},
    affected_placement_ids: []
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    payload = map_attr(attrs, :payload, %{})
    comparison = map_attr(payload, :comparison, %{})

    %__MODULE__{
      dashboard_investigation_preset_id:
        attr(attrs, :dashboard_investigation_preset_id) ||
          Ids.new("dashboard_investigation_preset"),
      organization_id: attr(attrs, :organization_id),
      mission_id: attr(attrs, :mission_id),
      dashboard_id: attr(attrs, :dashboard_id),
      name: attr(attrs, :name),
      description: attr(attrs, :description),
      schema: attr(attrs, :schema) || attr(payload, :schema),
      preset_kind: attrs |> attr(:preset_kind, :comparison) |> normalize_kind(),
      runtime_query: map_attr(attrs, :runtime_query, map_attr(payload, :runtime_query, %{})),
      payload: payload,
      primary_data_view: attr(attrs, :primary_data_view) || attr(comparison, :primary_data_view),
      compare_data_view: attr(attrs, :compare_data_view) || attr(comparison, :compare_data_view),
      affected_placement_ids:
        list_attr(attrs, :affected_placement_ids) || affected_placement_ids(payload),
      created_by: attr(attrs, :created_by),
      updated_by: attr(attrs, :updated_by),
      inserted_at: attr(attrs, :inserted_at),
      updated_at: attr(attrs, :updated_at)
    }
  end

  defp affected_placement_ids(payload) when is_map(payload) do
    payload
    |> map_attr(:groups, [])
    |> Enum.flat_map(&map_attr(&1, :placement_ids, []))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_kind(kind) when kind in @kinds, do: kind

  defp normalize_kind(kind) when is_binary(kind) do
    Enum.find(@kinds, &(Atom.to_string(&1) == kind)) ||
      raise ArgumentError, "unsupported investigation preset kind: #{inspect(kind)}"
  end

  defp normalize_kind(kind) do
    raise ArgumentError, "unsupported investigation preset kind: #{inspect(kind)}"
  end

  defp map_attr(map, key, default) when is_map(map) do
    case attr(map, key, default) do
      value when is_map(value) or is_list(value) -> value
      _other -> default
    end
  end

  defp list_attr(map, key) when is_map(map) do
    case attr(map, key) do
      value when is_list(value) -> value
      _other -> nil
    end
  end

  defp attr(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
