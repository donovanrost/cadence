defmodule Cadence.Reads.Attention do
  @moduledoc """
  A mission's "needs acknowledgment" items (DECISIONS #54), across sources: `pass_resolution`
  (booking-resolution conflicts, #53), `uplink_blocked` (a blocked pass holding command
  groups back, #58), `pass_release` (a pass whose cancel failed, so it may still be booked) and
  `contact_settlement` (an ended contact whose telemetry isn't stored yet, #71),
  `mission_runtime` (the active generation isn't applied; 2026-11-12) and `activation_apply` (an
  approved activation whose apply failed or stalled, to retry; 2026-11-13) and `provider_change`
  (a provider changed a booked pass: approve, reject or acknowledge; §11 L14) and
  `ingress_backpressure` (a contact's ingest buffer filling, or frames dropped; #83),
  `archive_quarantine` (archive entries that can never be indexed; #88), `listener_refusal`
  (connections refused on a pass's shared listener; #87, U50), `expired_group` (a command group
  whose deadline passed before all its members went out; U75, #97) and `plan_coverage` (a day
  nearing its first window with nothing being booked; U61). While an
  `activation_apply` item is open it carries the cause, so `mission_runtime` stays out of the list
  and those items say `runtime_not_applied: true` instead (fe-ops: one row for one cause). Other
  mission-level sources (provider changes, for example) join by implementing the same four
  functions:
  `source/0`, `items/2`, `resolved_since/3` and `counts/2`.

  Every item carries `id` and `source`; `{source, id}` is unique. Updates publish
  `:attention_changed` on the mission's read-updates topic.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Commanding.Groups.ExpiredGroupAttention, as: ExpiredGroup
  alias Cadence.Contacts.ArchiveQuarantineAttention, as: ArchiveQuarantine
  alias Cadence.Contacts.BookingResolutions.Attention, as: PassResolutions
  alias Cadence.Contacts.ContactSettlementAttention, as: ContactSettlement
  alias Cadence.Contacts.ContactStartAttention, as: ContactStart
  alias Cadence.Contacts.IngressBackpressureAttention, as: IngressBackpressure
  alias Cadence.Contacts.JobOutcomeUnknownAttention, as: JobOutcomeUnknown
  alias Cadence.Contacts.ListenerRefusalAttention, as: ListenerRefusal
  alias Cadence.Contacts.PassReleaseAttention, as: PassRelease
  alias Cadence.Contacts.ProviderChangeAttention, as: ProviderChange
  alias Cadence.Contacts.ScidMismatchAttention, as: ScidMismatch
  alias Cadence.Control.Activations.ApplyAttention, as: ActivationApply
  alias Cadence.Control.UplinkReadiness.Attention, as: UplinkBlocked
  alias Cadence.Platform.ReadMemo
  alias Cadence.Reads.MissionRuntimeAttention, as: MissionRuntime
  alias Cadence.Reads.PlanCoverageAttention, as: PlanCoverage

  @sources [
    PassResolutions,
    UplinkBlocked,
    PassRelease,
    ContactSettlement,
    ContactStart,
    MissionRuntime,
    ActivationApply,
    ProviderChange,
    IngressBackpressure,
    ArchiveQuarantine,
    JobOutcomeUnknown,
    ListenerRefusal,
    ExpiredGroup,
    PlanCoverage,
    ScidMismatch
  ]
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

      # One memo per load, so a source (plan_coverage) reads once for its items, resolutions and
      # counts. Nothing here writes.
      ReadMemo.with_memo(fn ->
        {:ok,
         %{
           items: @sources |> Enum.flat_map(& &1.items(org, mission_id)) |> one_row_per_cause(),
           resolved: Enum.flat_map(@sources, & &1.resolved_since(org, mission_id, since)),
           counts: counts(org, mission_id)
         }}
      end)
    end
  end

  @doc "Open and acknowledged counts across sources; cheap enough for `/counts`."
  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: non_neg_integer()}
  def counts(org, mission_id) do
    by_source = ReadMemo.with_memo(fn -> Map.new(@sources, &{&1, &1.counts(org, mission_id)}) end)

    by_source
    |> Map.drop(if by_source[ActivationApply].open > 0, do: [MissionRuntime], else: [])
    |> Map.values()
    |> Enum.reduce(%{open: 0, acknowledged: 0}, fn counts, acc ->
      Map.merge(acc, counts, fn _key, a, b -> a + b end)
    end)
  end

  @doc false
  def one_row_per_cause(items) do
    runtime = MissionRuntime.source()
    apply = ActivationApply.source()

    if Enum.any?(items, &(&1.source == apply)) do
      runtime_not_applied? = Enum.any?(items, &(&1.source == runtime))

      items
      |> Enum.reject(&(&1.source == runtime))
      |> Enum.map(&flag_runtime(&1, apply, runtime_not_applied?))
    else
      items
    end
  end

  defp flag_runtime(%{source: source} = item, source, runtime_not_applied?),
    do: Map.put(item, :runtime_not_applied, runtime_not_applied?)

  defp flag_runtime(item, _apply, _runtime_not_applied?), do: item

  defp authorize(scope, mission_id),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })
end
