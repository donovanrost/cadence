defmodule Cadence.Reads.ProviderEphemerisAttention do
  @moduledoc """
  The `provider_ephemeris` source of the mission attention read (#972): a provider that can't use
  some spacecraft's current orbit, grouped by cause (`Cadence.GroundNetworks.EphemerisFindings`).
  `conflict` is the cause:

    * `norad_id_missing`: a lookup provider, current element sets without a NORAD id;
    * `failed`: an upload provider, the latest upload failing (retried with backoff), per failure
      `reason` code;
    * `not_ready`: bound, but no route to the provider is ready, per refusal `reason` code.

  One item per group, id `<provider_id>:norad_id_missing`, `<provider_id>:failed:<reason>` or
  `<provider_id>:not_ready:<reason>`. It carries `provider_id`, `spacecraft_ids` (a sample of at
  most 10, named as the queue row's `spacecraft`), `spacecraft_count`, `reason` (a closed code,
  `EphemerisReasons`; `failed` and `not_ready`), `next_retry_at` (the earliest retry; `failed`
  and `not_ready`) and `since`, when the earliest member entered this outcome. The whole list is
  paged by `GET /missions/:mission_id/providers/:provider_id/ephemeris/spacecraft`.

  Derived on every read, like `model_approval_withdrawn`: there's nothing to acknowledge, and an
  item leaves when no spacecraft is in its group any more. Upload runs publish
  `:attention_changed` when an outcome changes.
  """

  alias Cadence.GroundNetworks.EphemerisFindings

  @source "provider_ephemeris"

  def source, do: @source

  @doc "Open items, one per (provider, cause[, reason]) group."
  @spec items(binary(), binary()) :: [map()]
  def items(org, mission), do: org |> EphemerisFindings.groups(mission) |> Enum.map(&item/1)

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(_org, _mission, _since), do: []

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission),
    do: %{open: length(EphemerisFindings.groups(org, mission)), acknowledged: 0}

  @doc "The item id of a group: `<provider_id>:<cause>`, or `…:<cause>:<reason>` when coded."
  @spec item_id(map()) :: binary()
  def item_id(%{provider_id: provider, cause: cause, reason: reason})
      when cause in ["failed", "not_ready"],
      do: "#{provider}:#{cause}:#{reason}"

  def item_id(%{provider_id: provider, cause: cause}), do: "#{provider}:#{cause}"

  defp item(group) do
    %{
      id: item_id(group),
      source: @source,
      conflict: group.cause,
      state: "open",
      provider_id: group.provider_id,
      spacecraft_ids: group.spacecraft_ids,
      spacecraft_count: group.spacecraft_count,
      reason: group.reason,
      next_retry_at: group.next_retry_at,
      raised_at: group.since,
      since: group.since,
      acknowledged_by: nil,
      resolution: nil
    }
  end
end
