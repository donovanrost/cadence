defmodule Cadence.Dashboards.ScopeContext do
  @moduledoc """
  Dashboard runtime operational scope context.
  """

  @type scope_selector :: %{
          optional(:kind) => atom() | binary(),
          optional(:mode) => atom() | binary(),
          optional(:ids) => [binary()]
        }

  @type t :: %__MODULE__{
          primary: scope_selector() | nil,
          mission_id: binary() | nil,
          spacecraft_id: binary() | nil,
          contact_id: binary() | nil,
          ground_station_id: binary() | nil,
          source_endpoint_id: binary() | nil,
          transport_id: binary() | nil,
          link_id: binary() | nil,
          filters: map() | nil
        }

  defstruct [
    :primary,
    :mission_id,
    :spacecraft_id,
    :contact_id,
    :ground_station_id,
    :source_endpoint_id,
    :transport_id,
    :link_id,
    :filters
  ]

  @valid_kinds [
    nil,
    :mission,
    "mission",
    :spacecraft,
    "spacecraft",
    :contact,
    "contact",
    :ground_station,
    "ground_station",
    :source_endpoint,
    "source_endpoint",
    :transport,
    "transport",
    :link,
    "link"
  ]
  @valid_modes [
    nil,
    :context,
    "context",
    :one,
    "one",
    :many,
    "many",
    :all,
    "all",
    :each,
    "each"
  ]
  @scope_fields %{
    :mission => :mission_id,
    "mission" => :mission_id,
    :spacecraft => :spacecraft_id,
    "spacecraft" => :spacecraft_id,
    :contact => :contact_id,
    "contact" => :contact_id,
    :ground_station => :ground_station_id,
    "ground_station" => :ground_station_id,
    :source_endpoint => :source_endpoint_id,
    "source_endpoint" => :source_endpoint_id,
    :transport => :transport_id,
    "transport" => :transport_id,
    :link => :link_id,
    "link" => :link_id
  }
  @scope_filter_fields %{
    :mission => :mission_ids,
    "mission" => :mission_ids,
    :spacecraft => :spacecraft_ids,
    "spacecraft" => :spacecraft_ids,
    :contact => :contact_ids,
    "contact" => :contact_ids,
    :ground_station => :ground_station_ids,
    "ground_station" => :ground_station_ids,
    :source_endpoint => :source_endpoint_ids,
    "source_endpoint" => :source_endpoint_ids,
    :transport => :transport_ids,
    "transport" => :transport_ids,
    :link => :link_ids,
    "link" => :link_ids
  }
  @single_id_modes [nil, :context, "context", :one, "one"]

  @spec resolve(map() | t() | nil, map() | t() | nil, map() | t() | nil) :: t()
  def resolve(runtime_context, default_context, override_context) do
    default_context
    |> merge(runtime_context)
    |> merge(override_context)
    |> from_map()
  end

  @spec from_map(map() | t() | nil) :: t()
  def from_map(%__MODULE__{} = context), do: put_primary_scope_id(context)
  def from_map(nil), do: %__MODULE__{}

  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      primary: normalize_selector(get_attr(attrs, :primary)),
      mission_id: get_attr(attrs, :mission_id),
      spacecraft_id: get_attr(attrs, :spacecraft_id),
      contact_id: get_attr(attrs, :contact_id),
      ground_station_id: get_attr(attrs, :ground_station_id),
      source_endpoint_id: get_attr(attrs, :source_endpoint_id),
      transport_id: get_attr(attrs, :transport_id),
      link_id: get_attr(attrs, :link_id),
      filters: get_attr(attrs, :filters) || %{}
    }
    |> put_primary_scope_id()
  end

  @spec validate(t()) :: [atom()]
  def validate(%__MODULE__{} = context) do
    primary = context.primary || %{}

    []
    |> maybe_add(Map.get(primary, :kind) not in @valid_kinds, :unsupported_scope_kind)
    |> maybe_add(Map.get(primary, :mode) not in @valid_modes, :unsupported_scope_mode)
  end

  @spec scope_id(t() | map() | nil, atom() | binary()) :: binary() | nil
  def scope_id(context, kind) when is_atom(kind) or is_binary(kind) do
    context = from_map(context)
    field = Map.get(@scope_fields, kind)

    typed_scope_id(context, field) || primary_scope_id(context, kind)
  end

  @spec scope_ids(t() | map() | nil, atom() | binary()) :: [binary()]
  def scope_ids(context, kind) when is_atom(kind) or is_binary(kind) do
    context = from_map(context)
    field = Map.get(@scope_fields, kind)

    (List.wrap(typed_scope_id(context, field)) ++
       primary_scope_ids(context, kind) ++ filter_scope_ids(context, kind))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec primary_kind(t() | map() | nil) :: atom() | binary() | nil
  def primary_kind(context) do
    context
    |> primary_selector()
    |> selector_attr(:kind)
  end

  @spec primary_ids(t() | map() | nil) :: [binary()]
  def primary_ids(context) do
    context
    |> primary_selector()
    |> selector_attr(:ids)
    |> normalize_ids()
  end

  defp merge(left, nil), do: to_known_map(left)
  defp merge(left, right), do: merge_known_maps(to_known_map(left), to_known_map(right))

  defp to_known_map(%__MODULE__{} = context),
    do: context |> Map.from_struct() |> put_primary_scope_filter() |> drop_nil_values()

  defp to_known_map(nil), do: %{}

  defp to_known_map(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_key(key) do
        nil -> acc
        :primary -> maybe_put(acc, :primary, normalize_selector(value))
        normalized_key -> maybe_put(acc, normalized_key, value)
      end
    end)
    |> put_primary_scope_filter()
  end

  defp merge_known_maps(left, right) when is_map(left) and is_map(right) do
    filters =
      Map.merge(
        normalize_filters(Map.get(left, :filters)),
        normalize_filters(Map.get(right, :filters))
      )

    left
    |> Map.merge(right)
    |> Map.put(:filters, filters)
    |> drop_empty_values()
  end

  defp normalize_key(key) when key in [:primary, "primary"], do: :primary
  defp normalize_key(key) when key in [:mission_id, "mission_id"], do: :mission_id
  defp normalize_key(key) when key in [:spacecraft_id, "spacecraft_id"], do: :spacecraft_id
  defp normalize_key(key) when key in [:contact_id, "contact_id"], do: :contact_id

  defp normalize_key(key) when key in [:ground_station_id, "ground_station_id"],
    do: :ground_station_id

  defp normalize_key(key) when key in [:source_endpoint_id, "source_endpoint_id"],
    do: :source_endpoint_id

  defp normalize_key(key) when key in [:transport_id, "transport_id"], do: :transport_id
  defp normalize_key(key) when key in [:link_id, "link_id"], do: :link_id
  defp normalize_key(key) when key in [:filters, "filters"], do: :filters
  defp normalize_key(_key), do: nil

  defp normalize_selector(nil), do: nil

  defp normalize_selector(selector) when is_map(selector) do
    %{
      kind: get_attr(selector, :kind),
      mode: get_attr(selector, :mode),
      ids: normalize_ids(get_attr(selector, :ids))
    }
  end

  defp put_primary_scope_id(%__MODULE__{primary: primary} = context) when is_map(primary) do
    field = primary |> Map.get(:kind) |> scope_field()
    id = single_primary_id(primary)

    if not is_nil(field) and is_binary(id) and is_nil(Map.get(context, field)) do
      Map.put(context, field, id)
    else
      context
    end
  end

  defp put_primary_scope_id(%__MODULE__{} = context), do: context

  defp primary_selector(%__MODULE__{primary: primary}), do: primary
  defp primary_selector(context) when is_map(context), do: get_attr(context, :primary)
  defp primary_selector(_context), do: nil

  defp primary_scope_id(%__MODULE__{primary: primary}, kind) when is_map(primary) do
    if same_scope_kind?(Map.get(primary, :kind), kind), do: single_primary_id(primary)
  end

  defp primary_scope_id(_context, _kind), do: nil

  defp primary_scope_ids(%__MODULE__{primary: primary}, kind) when is_map(primary) do
    if same_scope_kind?(Map.get(primary, :kind), kind) do
      primary
      |> Map.get(:ids)
      |> normalize_ids()
    else
      []
    end
  end

  defp primary_scope_ids(_context, _kind), do: []

  defp filter_scope_ids(%__MODULE__{filters: filters}, kind) do
    filters
    |> filter_scope_ids_from_filters(kind)
  end

  defp typed_scope_id(context, field) when is_atom(field) and not is_nil(field) do
    case Map.get(context, field) do
      id when is_binary(id) and id != "" -> id
      _other -> nil
    end
  end

  defp typed_scope_id(_context, nil), do: nil

  defp single_primary_id(primary) when is_map(primary) do
    mode = Map.get(primary, :mode)

    if mode in @single_id_modes do
      primary
      |> Map.get(:ids)
      |> normalize_ids()
      |> List.first()
    end
  end

  defp same_scope_kind?(left, right) when is_atom(left) and is_atom(right), do: left == right
  defp same_scope_kind?(left, right), do: to_string(left) == to_string(right)

  defp scope_field(kind), do: Map.get(@scope_fields, kind)

  defp filter_scope_ids_from_filters(filters, kind) when is_map(filters) do
    filters
    |> get_attr(scope_filter_field(kind))
    |> normalize_ids()
  end

  defp filter_scope_ids_from_filters(_filters, _kind), do: []

  defp scope_filter_field(kind), do: Map.get(@scope_filter_fields, kind)

  defp put_primary_scope_filter(%{primary: primary} = context) when is_map(primary) do
    ids = primary |> Map.get(:ids) |> normalize_ids()

    case {scope_filter_field(Map.get(primary, :kind)), ids} do
      {field, [_id | _rest]} when is_atom(field) ->
        filters =
          context
          |> Map.get(:filters)
          |> normalize_filters()
          |> Map.put_new(field, ids)

        Map.put(context, :filters, filters)

      _other ->
        context
    end
  end

  defp put_primary_scope_filter(context), do: context

  defp selector_attr(selector, key) when is_map(selector), do: get_attr(selector, key)
  defp selector_attr(_selector, _key), do: nil

  defp normalize_filters(filters) when is_map(filters) do
    Map.new(filters, fn {key, value} -> {normalize_filter_key(key), normalize_ids(value)} end)
    |> drop_empty_values()
  end

  defp normalize_filters(_filters), do: %{}

  defp normalize_filter_key(key) when is_atom(key), do: key

  defp normalize_filter_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> key
  end

  defp normalize_filter_key(key), do: key

  defp normalize_ids(ids) when is_list(ids) do
    Enum.filter(ids, fn id -> is_binary(id) and id != "" end)
  end

  defp normalize_ids(id) when is_binary(id) and id != "", do: [id]
  defp normalize_ids(_ids), do: []

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, value), do: Map.put(acc, key, value)

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp drop_empty_values(map) do
    Map.reject(map, fn {_key, value} -> value in [nil, "", [], %{}] end)
  end

  defp maybe_add(errors, false, _error), do: errors
  defp maybe_add(errors, true, error), do: errors ++ [error]
end
