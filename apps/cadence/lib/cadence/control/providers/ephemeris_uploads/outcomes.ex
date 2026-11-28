defmodule Cadence.Control.Providers.EphemerisUploads.Outcomes do
  @moduledoc """
  An ephemeris upload run's outcome bookkeeping (#972): when a pair entered its current outcome
  (`outcome_since`), and whether a run changed anything a read shows, which decides whether it
  publishes `providers` and `attention`.
  """

  # Every stored field a read exposes (the providers read's buckets, the provider_ephemeris
  # items, the member endpoint): a run publishes when any of them changes for any pair, the retry
  # state included, and stays quiet otherwise.
  @shown [
    :status,
    :element_set_id,
    :provider_version,
    :bound_provider_version,
    :provider_spacecraft_ref,
    :reason,
    :attempts,
    :next_retry_at,
    :outcome_since
  ]

  # When the pair entered its current outcome (#972): kept while the outcome and its basis are
  # unchanged (the same status and reason code, for the same element set, bound version and
  # provider-side ref), so an hourly re-check or a retry never makes a stuck pair look new; now
  # when any of them changes.
  @outcome [:status, :reason, :element_set_id, :bound_provider_version, :provider_spacecraft_ref]

  @doc "The state with `outcome_since`: the stored one while the outcome holds, else `now`."
  @spec since(map(), map(), DateTime.t()) :: map()
  def since(state, previous, now) do
    since =
      case Map.get(previous, {state.provider_id, state.spacecraft_id}) do
        %{outcome_since: %DateTime{} = since} = prior ->
          if Map.take(prior, @outcome) == Map.new(@outcome, &{&1, Map.get(state, &1)}),
            do: since,
            else: now

        _new ->
          now
      end

    Map.put(state, :outcome_since, since)
  end

  @doc "Whether a read would show this state differently from the stored one."
  @spec changed?(map(), map()) :: boolean()
  def changed?(state, previous) do
    case Map.get(previous, {state.provider_id, state.spacecraft_id}) do
      nil -> true
      prior -> shown(prior) != shown(state)
    end
  end

  # As stored: attempts default to 0, and times compare by instant, not precision.
  defp shown(state) do
    Map.new(@shown, fn
      :attempts -> {:attempts, Map.get(state, :attempts) || 0}
      key -> {key, instant(Map.get(state, key))}
    end)
  end

  defp instant(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)
  defp instant(value), do: value
end
