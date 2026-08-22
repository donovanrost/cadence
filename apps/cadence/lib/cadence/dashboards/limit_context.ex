defmodule Cadence.Dashboards.LimitContext do
  @moduledoc """
  Dashboard runtime limit semantics context.
  """

  @type t :: %__MODULE__{
          semantics_mode: atom() | binary() | nil,
          compare_to: atom() | binary() | nil,
          limit_set_name: binary() | nil
        }

  defstruct [
    :semantics_mode,
    :compare_to,
    :limit_set_name
  ]

  @valid_semantics_modes [
    nil,
    :observed,
    "observed",
    :current,
    "current",
    :recomputed,
    "recomputed",
    :compare,
    "compare"
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
      semantics_mode: get_attr(attrs, :semantics_mode),
      compare_to: get_attr(attrs, :compare_to),
      limit_set_name: get_attr(attrs, :limit_set_name)
    }
  end

  @spec validate(t()) :: [atom()]
  def validate(%__MODULE__{} = context) do
    []
    |> maybe_add(
      context.semantics_mode not in @valid_semantics_modes,
      :unsupported_limit_semantics_mode
    )
  end

  defp merge(left, nil), do: to_known_map(left)
  defp merge(left, right), do: Map.merge(to_known_map(left), to_known_map(right))

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

  defp normalize_key(key) when key in [:semantics_mode, "semantics_mode"], do: :semantics_mode
  defp normalize_key(key) when key in [:compare_to, "compare_to"], do: :compare_to
  defp normalize_key(key) when key in [:limit_set_name, "limit_set_name"], do: :limit_set_name
  defp normalize_key(_key), do: nil

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, value), do: Map.put(acc, key, value)

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_add(errors, false, _error), do: errors
  defp maybe_add(errors, true, error), do: errors ++ [error]
end
