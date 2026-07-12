defmodule Cadence.Dashboards.SourceProbePolicy do
  @moduledoc """
  Normalized scheduling policy for physical data-source probes.

  Source metadata may carry a `probe_policy` map. The scheduler uses it to
  suppress automatic probes or tighten/relax source-health freshness for a
  specific physical backend without changing the global scheduler cadence.
  """

  alias Cadence.Dashboards.DataSource

  @default_policy_id "default"

  @type t :: %{
          required(:policy_id) => binary(),
          required(:enabled?) => boolean(),
          required(:stale_after_ms) => pos_integer() | nil
        }

  @spec from_data_source(DataSource.t()) :: t()
  def from_data_source(%DataSource{} = source) do
    policy =
      source.metadata
      |> normalize_map()
      |> value(:probe_policy)
      |> normalize_map()

    %{
      policy_id: policy_id(policy),
      enabled?: enabled?(policy),
      stale_after_ms: positive_integer(value(policy, :stale_after_ms))
    }
  end

  @spec source_health_opts(t(), keyword()) :: keyword()
  def source_health_opts(%{stale_after_ms: nil}, opts), do: opts

  def source_health_opts(%{stale_after_ms: stale_after_ms}, opts) do
    Keyword.put(opts, :source_health_freshness, default_max_age_ms: stale_after_ms)
  end

  @spec stale_after_ms_text(t()) :: binary()
  def stale_after_ms_text(%{stale_after_ms: stale_after_ms}) when is_integer(stale_after_ms),
    do: Integer.to_string(stale_after_ms)

  def stale_after_ms_text(_policy), do: "default"

  defp policy_id(policy) do
    policy
    |> value(:id)
    |> fallback(value(policy, :policy_id))
    |> case do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _other -> @default_policy_id
    end
  end

  defp enabled?(policy) do
    case value(policy, :enabled?) |> fallback(value(policy, :enabled)) do
      false -> false
      "false" -> false
      _other -> true
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp value(_other, _key), do: nil

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}
end
