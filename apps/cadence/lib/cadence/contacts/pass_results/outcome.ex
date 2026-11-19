defmodule Cadence.Contacts.PassResults.Outcome do
  @moduledoc """
  Pure derivation of a pass's outcome, cause and owner (S9, DECISIONS #47/#48,
  `docs/apogee/domain/pass-review.md`).

  - Canceled before AOS **at Cadence's request** (an operator or re-plan) is `canceled`, which
    the realization denominator leaves out.
  - Canceled or rejected **by the provider** after booking is `missed`, cause
    `provider_canceled`, owner `provider` (disputable).
  - With a provider result: no acquisition is `missed` (or `failed` when the provider names a
    delivery failure); flown ≥ threshold × planned with something delivered is `realized`;
    otherwise `partial`.
  - No provider result yet is `pending_report` (provisional; out of the denominator).

  Delivered by the provider but nothing received by Cadence is `partial`, cause `not_ingested`,
  owned by `us`. A blocking S7 window over the pass makes a miss `station_unavailable`, owned by whoever
  reported the window (provider → `provider`, operator → `us`). A cause naming weather is owned
  by `weather`.
  """

  @type input :: %{
          required(:lifecycle_state) => atom(),
          required(:cancel_initiator) => :cadence | :provider | nil,
          required(:planned_aos) => DateTime.t(),
          required(:planned_los) => DateTime.t(),
          required(:result) => map() | nil,
          required(:status_reason) => String.t() | nil,
          required(:station_window) => map() | nil,
          required(:threshold) => number(),
          optional(:received_frames) => non_neg_integer() | nil,
          required(:now) => DateTime.t()
        }

  @spec derive(input()) :: map()
  def derive(%{lifecycle_state: state, cancel_initiator: :cadence} = input)
      when state in [:canceled, :canceling] do
    if DateTime.before?(input.now, input.planned_aos),
      do: verdict("canceled", "canceled_by_cadence", "cadence", "us"),
      else: verdict("missed", "canceled_by_cadence", "cadence", "us")
  end

  def derive(%{lifecycle_state: state} = input)
      when state in [:canceled, :rejected, :canceling] do
    cause = if state == :rejected, do: "provider_rejected", else: "provider_canceled"
    verdict("missed", cause, "provider", owner_for_provider(input.status_reason))
  end

  def derive(%{result: %{} = result} = input) do
    flown = flown_seconds(result)
    planned = max(DateTime.diff(input.planned_los, input.planned_aos), 1)
    delivered? = delivered?(result)

    cond do
      is_nil(result["actual_acquisition_at"]) or flown == 0 -> miss(input, result)
      flown < input.threshold * planned or not delivered? -> short(result, delivered?)
      not_ingested?(input, result) -> verdict("partial", "not_ingested", "cadence", "us")
      true -> verdict("realized", nil, nil, "unknown")
    end
  end

  def derive(%{result: nil}), do: verdict("pending_report", nil, nil, "unknown")

  @doc "Seconds flown per the provider's actual AOS/LOS, or 0."
  @spec flown_seconds(map()) :: non_neg_integer()
  def flown_seconds(result) do
    with {:ok, aos, _} <- DateTime.from_iso8601(result["actual_acquisition_at"] || ""),
         {:ok, los, _} <- DateTime.from_iso8601(result["actual_loss_at"] || "") do
      max(DateTime.diff(los, aos), 0)
    else
      _ -> 0
    end
  end

  defp delivered?(result),
    do: (result["bytes_delivered"] || 0) > 0 or (result["frames_delivered"] || 0) > 0

  defp short(result, delivered?) do
    reason = result["provider_failure_reason"] || result["delivery_failure_reason"]
    fallback = if delivered?, do: "short_pass", else: "nothing_delivered"
    verdict("partial", reason || fallback, "provider", owner_for_provider(reason))
  end

  # The provider delivered but Cadence's protocol archive recorded no frames for the contact.
  # Unknown received volume (nil) is not evidence of loss.
  defp not_ingested?(input, result),
    do: delivered?(result) and Map.get(input, :received_frames) == 0

  defp miss(input, result) do
    cond do
      is_binary(result["delivery_failure_reason"]) ->
        verdict("failed", result["delivery_failure_reason"], "delivery", "provider")

      input.station_window ->
        owner = if input.station_window.source == :provider, do: "provider", else: "us"
        verdict("missed", "station_unavailable", "station", owner)

      true ->
        reason = result["provider_failure_reason"]
        verdict("missed", reason || "no_acquisition", "provider", owner_for_provider(reason))
    end
  end

  defp owner_for_provider(reason) when is_binary(reason) do
    if String.contains?(String.downcase(reason), "weather"), do: "weather", else: "provider"
  end

  defp owner_for_provider(_reason), do: "provider"

  defp verdict(outcome, cause, source, owner),
    do: %{
      outcome: outcome,
      cause: cause,
      cause_source: source,
      owner: owner,
      disputable: owner == "provider"
    }
end
