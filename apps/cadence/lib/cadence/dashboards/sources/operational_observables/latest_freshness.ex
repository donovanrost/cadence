defmodule Cadence.Dashboards.Sources.OperationalObservables.LatestFreshness do
  @moduledoc """
  Annotates latest operational-observable rows with shared freshness state.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, SourceFreshness}

  @spec annotate([map()], PlannedSourceRequest.t(), keyword()) :: [map()]
  def annotate(rows, %PlannedSourceRequest{} = request, opts) do
    Enum.map(rows, &put_freshness(&1, request, opts))
  end

  defp put_freshness(row, request, opts) when is_map(row) do
    observed_at = row_observed_at(row)
    freshness = freshness(observed_at, request, opts)

    row
    |> Map.put(:observed_at, observed_at)
    |> Map.put(:freshness_state, freshness.state)
    |> Map.put(:age_ms, freshness.age_ms)
    |> Map.put(:freshness_policy, freshness.policy)
    |> Map.put(:freshness_checked_at, freshness.checked_at)
  end

  defp row_observed_at(row) do
    case attr(row, :observed_at) || attr(row, :time) do
      %DateTime{} = observed_at -> observed_at
      _other -> nil
    end
  end

  defp freshness(observed_at, request, opts) do
    policy =
      SourceFreshness.resolve_policy([
        Keyword.get(opts, :freshness_policy),
        attr(request.sampling, :freshness_policy),
        attr(request.data_context, :freshness_policy)
      ])

    checked_at = Keyword.get_lazy(opts, :freshness_now, &DateTime.utc_now/0)
    age_ms = age_ms(observed_at, checked_at)

    %{
      state: freshness_state(observed_at, age_ms, policy),
      age_ms: age_ms,
      policy: policy,
      checked_at: checked_at
    }
  end

  defp age_ms(%DateTime{} = observed_at, %DateTime{} = checked_at) do
    max(DateTime.diff(checked_at, observed_at, :millisecond), 0)
  end

  defp age_ms(_observed_at, _checked_at), do: nil

  defp freshness_state(nil, _age_ms, _policy), do: :missing

  defp freshness_state(_observed_at, age_ms, %{stale_after_ms: stale_after_ms})
       when is_integer(age_ms) and is_integer(stale_after_ms) and stale_after_ms >= 0 and
              age_ms > stale_after_ms,
       do: :stale

  defp freshness_state(_observed_at, _age_ms, _policy), do: :fresh

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
