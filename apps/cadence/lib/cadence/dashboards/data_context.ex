defmodule Cadence.Dashboards.DataContext do
  @moduledoc """
  Dashboard runtime data-realm and source-selection context.
  """

  @type t :: %__MODULE__{
          realm: atom() | binary() | nil,
          source_mode: atom() | binary() | nil,
          data_source_id: binary() | nil,
          source_binding_id: binary() | nil,
          dataset: binary() | nil,
          view: atom() | binary() | nil,
          source_contexts: map(),
          replay_run_id: binary() | nil,
          validity_state: atom() | binary() | nil,
          allowed_realms: [atom() | binary()] | nil
        }

  defstruct [
    :realm,
    :source_mode,
    :data_source_id,
    :source_binding_id,
    :dataset,
    :view,
    :replay_run_id,
    :validity_state,
    :allowed_realms,
    source_contexts: %{}
  ]

  @valid_realms [
    nil,
    :flight,
    "flight",
    :rehearsal,
    "rehearsal",
    :replay,
    "replay",
    :simulation,
    "simulation"
  ]
  @valid_source_modes [nil, :primary, "primary", :bound, "bound", :specific, "specific"]
  @valid_views [
    nil,
    :canonical,
    "canonical",
    :as_recorded,
    "as_recorded",
    :all_revisions,
    "all_revisions",
    :recomputed,
    "recomputed"
  ]

  @spec resolve(map() | t() | nil, map() | t() | nil, map() | t() | nil) :: t()
  def resolve(runtime_context, default_context, override_context) do
    default_context
    |> merge(runtime_context)
    |> merge(override_context)
    |> from_map()
  end

  @spec from_map(map() | t() | nil) :: t()
  def from_map(%__MODULE__{} = context), do: context
  def from_map(nil), do: %__MODULE__{}

  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      realm: get_attr(attrs, :realm),
      source_mode: get_attr(attrs, :source_mode),
      data_source_id: get_attr(attrs, :data_source_id),
      source_binding_id: get_attr(attrs, :source_binding_id),
      dataset: get_attr(attrs, :dataset),
      view: first_attr(attrs, [:view, :data_view, :selection_view, :data_management_view]),
      source_contexts: normalize_source_contexts(get_attr(attrs, :source_contexts) || %{}),
      replay_run_id: get_attr(attrs, :replay_run_id),
      validity_state: get_attr(attrs, :validity_state),
      allowed_realms: get_attr(attrs, :allowed_realms) || []
    }
  end

  @spec validate(t()) :: [atom()]
  def validate(%__MODULE__{} = context) do
    []
    |> maybe_add(context.realm not in @valid_realms, :unsupported_data_realm)
    |> maybe_add(context.source_mode not in @valid_source_modes, :unsupported_source_mode)
    |> maybe_add(context.view not in @valid_views, :unsupported_data_view)
  end

  @spec source_value(map() | t() | nil, atom() | binary(), atom()) :: term()
  def source_value(context, logical_source, key) when is_atom(key) do
    context = from_map(context)

    case source_context_value(context.source_contexts, logical_source, key) do
      nil -> get_attr(context, key)
      value -> value
    end
  end

  defp merge(left, nil), do: to_known_map(left)

  defp merge(left, right) do
    left = to_known_map(left)
    right = to_known_map(right)

    Map.merge(left, right, fn
      :source_contexts, left_contexts, right_contexts ->
        merge_source_contexts(left_contexts, right_contexts)

      _key, _left_value, right_value ->
        right_value
    end)
  end

  defp to_known_map(%__MODULE__{} = context),
    do: context |> Map.from_struct() |> drop_nil_values()

  defp to_known_map(nil), do: %{}

  defp to_known_map(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_key(key) do
        nil -> acc
        normalized_key -> maybe_put(acc, normalized_key, value)
      end
    end)
  end

  defp normalize_key(key) when key in [:realm, "realm"], do: :realm
  defp normalize_key(key) when key in [:source_mode, "source_mode"], do: :source_mode
  defp normalize_key(key) when key in [:data_source_id, "data_source_id"], do: :data_source_id

  defp normalize_key(key) when key in [:source_binding_id, "source_binding_id"],
    do: :source_binding_id

  defp normalize_key(key) when key in [:binding_id, "binding_id"], do: :source_binding_id
  defp normalize_key(key) when key in [:dataset, "dataset"], do: :dataset
  defp normalize_key(key) when key in [:view, "view"], do: :view
  defp normalize_key(key) when key in [:data_view, "data_view"], do: :view
  defp normalize_key(key) when key in [:selection_view, "selection_view"], do: :view
  defp normalize_key(key) when key in [:data_management_view, "data_management_view"], do: :view
  defp normalize_key(key) when key in [:source_contexts, "source_contexts"], do: :source_contexts
  defp normalize_key(key) when key in [:replay_run_id, "replay_run_id"], do: :replay_run_id
  defp normalize_key(key) when key in [:validity_state, "validity_state"], do: :validity_state
  defp normalize_key(key) when key in [:allowed_realms, "allowed_realms"], do: :allowed_realms
  defp normalize_key(_key), do: nil

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp first_attr(attrs, keys) do
    Enum.find_value(keys, fn key ->
      case get_attr(attrs, key) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end)
  end

  defp normalize_source_contexts(contexts) when is_map(contexts) do
    contexts
    |> Enum.reduce(%{}, fn {logical_source, source_context}, acc ->
      case normalize_logical_source(logical_source) do
        nil -> acc
        logical_source -> Map.put(acc, logical_source, to_known_map(source_context))
      end
    end)
  end

  defp normalize_source_contexts(_contexts), do: %{}

  defp merge_source_contexts(left, right) do
    left = normalize_source_contexts(left)
    right = normalize_source_contexts(right)

    Map.merge(left, right, fn _logical_source, left_context, right_context ->
      Map.merge(left_context, right_context)
    end)
  end

  defp source_context_value(contexts, logical_source, key) do
    contexts
    |> normalize_source_contexts()
    |> Map.get(normalize_logical_source(logical_source), %{})
    |> get_attr(key)
  end

  defp normalize_logical_source(logical_source) when is_atom(logical_source), do: logical_source

  defp normalize_logical_source(logical_source) when is_binary(logical_source) do
    logical_source
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_logical_source(_logical_source), do: nil

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, value), do: Map.put(acc, key, value)

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_add(errors, false, _error), do: errors
  defp maybe_add(errors, true, error), do: errors ++ [error]
end
