defmodule Cadence.Reads.PlanCoverageAttention do
  @moduledoc """
  The `plan_coverage` source of the mission attention read (ux U61; design
  docs/apogee/domain/plan-coverage-attention.md): a UTC day, from today to today + 2, whose first
  contact window nears while **nothing is being booked** for it. One item per day, id
  `YYYY-MM-DD`.

  The day and its plan come from `Reads.ContactPlanDays` (the K1 strip's own rule, so the strip
  and Now agree). The plan's state is the derived one (`Control.Contacts.plan_state/5`). A day
  is **covered**, so no item, when that state is `executing`, `unconfirmed`, `partially_reserved`,
  `reserved` or `failed` (unbooked passes have their own items), or `approved` within
  2 minutes of its approval (booking starts in well under a second). It stays open for no plan,
  a draft, a pending plan, an approved plan whose booking hasn't started after that grace, and an
  `interrupted` run.

  Raised at the first window − 24 h (P2, caution), P1 from − 6 h, crit once it opens. Derived on
  every read, so there's nothing to acknowledge. Per-viewer fields (`viewer_can_approve`,
  `viewer_can_book`) are the console's to add.

  `resolved_since/3` derives resolutions from durable times: an approval (`approved`), booking
  starting after the grace or resuming after a gap (`booking_started`, from `approved` or
  `interrupted`), and the end of a day still uncovered (`day_ended`). A day whose needs drop to
  zero just leaves the list: no durable time says when (no `nothing_left` line yet).
  """

  alias Cadence.Accounts
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Platform.ReadMemo
  alias Cadence.Reads.{ContactPlanDays, PlanApproval}

  @source "plan_coverage"
  @grace_s 120
  @raise_s 24 * 3600
  @p1_s 6 * 3600
  @covered [:executing, :unconfirmed, :partially_reserved, :reserved, :failed]

  def source, do: @source

  @doc "Open items, today to today + 2. Option `:now`."
  @spec items(binary(), binary(), keyword()) :: [map()]
  def items(org, mission, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    today = DateTime.to_date(now)

    for day <- days(org, mission, today),
        Date.compare(day.day, today) != :lt,
        day.requirements_count > 0 and day.first_window_at != nil,
        not before?(now, DateTime.add(day.first_window_at, -@raise_s)),
        before?(now, day_end(day.day)),
        coverage = coverage(org, mission, day, now),
        coverage.open? do
      item(org, day, coverage, now)
    end
  end

  @doc """
  Resolutions at or after `since`, for yesterday to today + 2 (yesterday's for its day end; the
  attention read's window is 60 s). Option `:now`.
  """
  @spec resolved_since(binary(), binary(), DateTime.t(), keyword()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    today = DateTime.to_date(now)

    for day <- days(org, mission, today),
        day.requirements_count > 0 and day.first_window_at != nil,
        resolution <- resolutions(org, mission, day, since, now),
        do: resolution
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission), do: %{open: length(items(org, mission)), acknowledged: 0}

  # Yesterday to today + 2, read once per attention load: `Reads.Attention` wraps its load in
  # `ReadMemo.with_memo/1`, so items, resolutions and counts share one read of the plans and the
  # demand (one plan-list read is a query per plan).
  defp days(org, mission, today) do
    key = {__MODULE__, :days, org, mission, today}

    case ReadMemo.fetch(key, fn ->
           ContactPlanDays.load(org, mission, Date.add(today, -1), Date.add(today, 2))
         end) do
      {:ok, days} -> days
      {:error, _invalid} -> []
    end
  end

  # What the day's plan is doing: %{open?, state (wire), plan (ContactPlan | nil), summary,
  # booking}.
  defp coverage(_org, _mission, %{plan: nil}, _now),
    do: %{open?: true, state: nil, plan: nil, summary: nil, booking: nil}

  defp coverage(org, mission, %{plan: summary}, now) do
    {:ok, plan, _version} = ManagementContacts.fetch_plan(org, mission, summary.id)

    derived =
      ControlContacts.plan_state(org, mission, plan.contact_plan_id, summary.state, now: now)

    case derived do
      state when state in @covered ->
        %{open?: false, state: state, plan: plan, summary: summary, booking: nil}

      :approved ->
        started? = not before?(now, DateTime.add(plan.approved_at, @grace_s))
        # #268: the count Now's 'Book N passes' shows (its passes never placed).
        booking = if started?, do: booking(org, mission, plan)
        %{open?: started?, state: :approved, plan: plan, summary: summary, booking: booking}

      :interrupted ->
        booking = booking(org, mission, plan)
        %{open?: true, state: :interrupted, plan: plan, summary: summary, booking: booking}

      other ->
        %{open?: true, state: other, plan: plan, summary: summary, booking: nil}
    end
  end

  defp item(org, day, coverage, now) do
    first = day.first_window_at
    author = author(coverage.summary)

    %{
      id: Date.to_iso8601(day.day),
      source: @source,
      state: "open",
      day: Date.to_iso8601(day.day),
      first_window_at: first,
      due_at: first,
      severity: if(before?(now, first), do: "caution", else: "crit"),
      p1: not before?(now, DateTime.add(first, -@p1_s)),
      requirements_count: day.requirements_count,
      plan: plan_fields(coverage, day, author),
      approvers: approvers(org, author),
      raised_at: raised_at(first, coverage)
    }
  end

  defp plan_fields(%{plan: nil}, _day, _author), do: nil

  defp plan_fields(%{plan: plan, summary: summary, state: state, booking: booking}, day, author) do
    %{
      id: plan.contact_plan_id,
      revision: summary.version,
      state: Atom.to_string(state),
      author: author,
      submitted_at: if(state == :pending_approval, do: plan.lifecycle_changed_at),
      sent_back: if(day.sent_back, do: sent_back(plan, summary)),
      approved_at: if(state in [:approved, :interrupted], do: plan.approved_at),
      booking: booking
    }
  end

  defp sent_back(plan, summary) do
    case PlanApproval.latest(
           plan.organization_id,
           plan.mission_id,
           plan.contact_plan_id,
           summary.version
         ) do
      %{decision: :rejected, actor: actor, at: at, reason: reason} ->
        %{by: Map.take(actor, [:id, :name]), at: at, comment: reason}

      _other ->
        nil
    end
  end

  defp author(%{author: %{} = author}), do: Map.take(author, [:id, :name])
  defp author(_summary), do: nil

  # Who may approve a plan (`:approve_contact_plans`: an organization admin), never its author.
  defp approvers(org, author) do
    author_id = author && Map.get(author, :id)

    for %{membership: membership, user: user} <- Accounts.list_organization_members(org),
        membership.role == :organization_admin,
        user.user_id != author_id,
        do: %{id: user.user_id, name: user.display_name || user.email}
  end

  defp raised_at(first, %{state: :approved, plan: plan}),
    do: latest([DateTime.add(first, -@raise_s), DateTime.add(plan.approved_at, @grace_s)])

  defp raised_at(first, %{state: :interrupted, booking: %{last_progress_at: %DateTime{} = at}}),
    do: latest([DateTime.add(first, -@raise_s), at])

  defp raised_at(first, _coverage), do: DateTime.add(first, -@raise_s)

  # The approved version's items: how many are booked, and the last progress any made.
  defp booking(org, mission, plan) do
    items = execution_items(org, mission, plan)

    %{
      reserved: Enum.count(items, &(&1.lifecycle_state == :reserved)),
      total: length(items),
      # #268 (ux): the passes 'Book N passes' / 'Book the other N' would act on: pending (never
      # sent) or requesting (a write in flight, re-read rather than re-sent). #355 drops those
      # whose booking window closed after the approval (domain).
      bookable: Enum.count(items, &(&1.lifecycle_state in [:pending, :requesting])),
      last_progress_at: items |> progress_times() |> Enum.max(DateTime, fn -> nil end)
    }
  end

  defp execution_items(_org, _mission, %{approved_version: nil}), do: []

  defp execution_items(org, mission, plan),
    do:
      ControlContacts.list_plan_execution(
        org,
        mission,
        plan.contact_plan_id,
        plan.approved_version
      )

  defp progress_times(items),
    do: items |> Enum.flat_map(&[&1.started_at, &1.completed_at]) |> Enum.reject(&is_nil/1)

  defp resolutions(org, mission, day, since, now) do
    day_end = day_end(day.day)
    raised_from = DateTime.add(day.first_window_at, -@raise_s)

    cond do
      before?(now, raised_from) ->
        []

      not before?(now, day_end) ->
        day_ended(org, mission, day, since, now, day_end)

      true ->
        coverage = coverage(org, mission, day, now)
        started(coverage, org, mission, day, %{from: raised_from, since: since, now: now})
    end
  end

  defp day_ended(org, mission, day, since, now, day_end) do
    coverage = coverage(org, mission, day, day_end)

    if coverage.open? and within?(day_end, since, now) do
      [
        resolution(day, "day_ended", %{"kind" => "system"}, day_end, %{
          from_state: coverage.state && Atom.to_string(coverage.state),
          plan_revision: coverage.summary && coverage.summary.version,
          booking: coverage.booking && Map.take(coverage.booking, [:reserved, :total])
        })
      ]
    else
      []
    end
  end

  # A covered day: approved in the window (the normal case), booking that began only after the
  # grace, or booking resumed after a gap longer than it (a second run).
  defp started(%{open?: true}, _org, _mission, _day, _window), do: []
  defp started(%{plan: nil}, _org, _mission, _day, _window), do: []

  defp started(%{plan: plan, summary: summary}, org, mission, day, window) do
    times = org |> execution_items(mission, plan) |> progress_times() |> Enum.sort(DateTime)
    shown? = &(within?(&1, window.since, window.now) and not before?(&1, window.from))
    fields = %{plan_revision: summary.version, booking: nil}

    first_start(plan, times, shown?, day, fields) ++ resumed(times, shown?, day, fields)
  end

  # Approval, or (booking began only after the grace) the late start.
  defp first_start(%{approved_at: nil}, _times, _shown?, _day, _fields), do: []

  defp first_start(plan, times, shown?, day, fields) do
    case late_start(plan.approved_at, times) do
      nil ->
        by = %{"kind" => "user", "id" => plan.approved_by}
        at = plan.approved_at

        if shown?.(at),
          do: [resolution(day, "approved", by, at, fields_from(fields, nil))],
          else: []

      late ->
        if shown?.(late),
          do: [
            resolution(day, "booking_started", system(), late, fields_from(fields, "approved"))
          ],
          else: []
    end
  end

  # A gap in progress longer than the grace: a second run continued the booking.
  defp resumed(times, shown?, day, fields) do
    for [a, b] <- Enum.chunk_every(times, 2, 1, :discard),
        DateTime.diff(b, a) > @grace_s and shown?.(b),
        do: resolution(day, "booking_started", system(), b, fields_from(fields, "interrupted"))
  end

  defp fields_from(fields, from_state), do: Map.put(fields, :from_state, from_state)
  defp system, do: %{"kind" => "system"}

  defp late_start(approved_at, [first | _rest]) do
    if DateTime.diff(first, approved_at) > @grace_s, do: first
  end

  defp late_start(_approved_at, []), do: nil

  defp resolution(day, action, by, at, fields) do
    Map.merge(
      %{
        id: Date.to_iso8601(day.day),
        source: @source,
        day: Date.to_iso8601(day.day),
        action: action,
        resolved_by: by,
        resolved_at: at
      },
      fields
    )
  end

  defp day_end(day), do: DateTime.new!(Date.add(day, 1), ~T[00:00:00.000000], "Etc/UTC")
  defp before?(a, b), do: DateTime.compare(a, b) == :lt
  defp within?(at, since, now), do: not before?(at, since) and not before?(now, at)
  defp latest(times), do: Enum.max(times, DateTime)
end
