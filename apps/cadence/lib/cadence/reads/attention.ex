defmodule Cadence.Reads.Attention do
  @moduledoc """
  A mission's "needs acknowledgment" items (DECISIONS #54), across sources: `pass_resolution`
  (booking-resolution conflicts, #53), `uplink_blocked` (a blocked pass holding command
  groups back, #58), `pass_release` (a pass whose cancel failed, so it may still be booked) and
  `contact_settlement` (an ended contact whose telemetry isn't stored yet, #71) and
  `mission_runtime` (the active generation isn't applied; 2026-11-12). Other
  mission-level sources (provider changes, for example) join by implementing the same four
  functions:
  `source/0`, `items/2`, `resolved_since/3` and `counts/2`.

  Every item carries `id` and `source`; `{source, id}` is unique. Updates publish
  `:attention_changed` on the mission's read-updates topic.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.BookingResolutions.Attention, as: PassResolutions
  alias Cadence.Contacts.ContactSettlementAttention, as: ContactSettlement
  alias Cadence.Contacts.PassReleaseAttention, as: PassRelease
  alias Cadence.Control.UplinkReadiness.Attention, as: UplinkBlocked
  alias Cadence.Reads.MissionRuntimeAttention, as: MissionRuntime

  @sources [PassResolutions, UplinkBlocked, PassRelease, ContactSettlement, MissionRuntime]
  @resolved_window_s 60

  @doc """
  `{items, resolved, counts}`: open and acknowledged items, those resolved in the last 60 s
  (for the fade-out) and `%{open, acknowledged}`. Option `:now`.
  """
  @spec load(Scope.t(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(%Scope{} = scope, mission_id, opts \\ []) do
    with :ok <- authorize(scope, mission_id) do
      org = scope.organization_id
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      since = DateTime.add(now, -@resolved_window_s, :second)

      {:ok,
       %{
         items: Enum.flat_map(@sources, & &1.items(org, mission_id)),
         resolved: Enum.flat_map(@sources, & &1.resolved_since(org, mission_id, since)),
         counts: counts(org, mission_id)
       }}
    end
  end

  @doc "Open and acknowledged counts across sources; cheap enough for `/counts`."
  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: non_neg_integer()}
  def counts(org, mission_id) do
    Enum.reduce(@sources, %{open: 0, acknowledged: 0}, fn source, acc ->
      Map.merge(acc, source.counts(org, mission_id), fn _key, a, b -> a + b end)
    end)
  end

  defp authorize(scope, mission_id),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })
end
