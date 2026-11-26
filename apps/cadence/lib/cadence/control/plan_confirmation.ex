defmodule Cadence.Control.PlanConfirmation do
  @moduledoc """
  The bookings of an approved plan that the provider hasn't confirmed within the confirmation
  window (DECISIONS #52, ux U30): execution items still `uncertain` and placed (`started_at`)
  longer ago than `:provider_confirmation_window_ms`. Plan detail carries it, so the console can
  say which passes wait on which provider instead of guessing from reservation states.
  """

  alias Cadence.ContactPlanning.ContactPlanExecutions
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.Control.ActorRef
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.GroundNetworks.MissionProviders
  alias Cadence.Management.Contacts, as: ManagementContacts

  # No resolvers looked up: everyone reads unnamed (ActorRef.names/2's shape).
  @no_names %{users: %{}, user_ids: MapSet.new(), services: %{}, service_ids: MapSet.new()}

  @type pass :: %{
          snapshot_id: binary(),
          item_id: binary(),
          provider: %{id: binary(), name: binary() | nil} | nil,
          sent_at: DateTime.t()
        }

  @doc "The confirmation window in milliseconds (default 10 minutes)."
  @spec window_ms() :: pos_integer()
  def window_ms,
    do: Application.get_env(:cadence, :provider_confirmation_window_ms, :timer.minutes(10))

  @doc """
  Plan detail's execution fields from one read of the approved version's items:
  `%{unconfirmed: unconfirmed/4's value, execution: execution summary | nil, bookings:
  bookings/1's map}` (`bookings` is `%{}` before the plan is approved).
  """
  @spec detail(binary(), binary(), binary(), keyword()) :: %{
          unconfirmed: map() | nil,
          execution: map() | nil,
          bookings: %{binary() => map()}
        }
  def detail(organization_id, mission_id, plan_id, opts \\ []) do
    case ManagementContacts.fetch_approved_plan(organization_id, mission_id, plan_id) do
      {:ok, approved} ->
        {items, counts} =
          ContactPlanExecutions.list_with_counts(
            organization_id,
            mission_id,
            plan_id,
            approved.contact_plan_version
          )

        display = booking_display(organization_id, mission_id, items)

        %{
          unconfirmed: unconfirmed_of(items, counts, display, opts),
          execution: execution_summary(counts, display.provider_names),
          bookings: bookings(items, resolver_names(organization_id, items))
        }

      _not_approved ->
        %{unconfirmed: nil, execution: nil, bookings: %{}}
    end
  end

  @doc """
  `%{window_ms, booked, passes}` while some placed booking is unconfirmed past the window
  (`booked` counts reserved items; `passes` come soonest first), else `nil`.
  Options: `:now`, `:window_ms`.
  """
  @spec unconfirmed(binary(), binary(), binary(), keyword()) ::
          %{window_ms: pos_integer(), booked: non_neg_integer(), passes: [pass()]} | nil
  def unconfirmed(organization_id, mission_id, plan_id, opts \\ []),
    do: detail(organization_id, mission_id, plan_id, opts).unconfirmed

  @doc """
  Counts of an approved plan's bookings by how far they got (lead, K1/K2), `nil` before it has
  any. `requested` is every pass the plan books, and `requested = sent + never_sent`. `sent`
  reached the provider: `confirmed + uncertain + rejected + failed`. `never_sent` is still
  waiting (or was interrupted before the provider call), or failed before it (`failed` counts
  only bookings the provider failed or lost).
  """
  @spec execution([struct()]) :: map() | nil
  def execution([]), do: nil

  def execution(items) do
    count = fn state -> Enum.count(items, &(&1.lifecycle_state == state)) end
    failed = Enum.count(items, &(&1.lifecycle_state == :failed and placed?(&1)))

    summary = %{
      requested: length(items),
      confirmed: count.(:reserved),
      uncertain: count.(:uncertain),
      rejected: count.(:rejected),
      failed: failed
    }

    with_sent(summary)
  end

  defp execution_summary(nil, _names), do: nil

  defp execution_summary(counts, names),
    do: counts |> with_sent() |> Map.put(:provider_names, names)

  defp with_sent(counts) do
    sent = counts.confirmed + counts.uncertain + counts.rejected + counts.failed
    Map.merge(counts, %{sent: sent, never_sent: counts.requested - sent})
  end

  @doc """
  Each pass's booking, by snapshot id (lead, K1 8e): `%{state, reason, at, detail, retryable,
  retry_after_seconds, resolved}`. `state` adds up to
  `execution/1`'s counts: `confirmed` (reserved), `uncertain`, `rejected`, `failed` (the
  provider failed or lost a placed booking), else `never_sent` (waiting, sending, or failed
  before the provider call). `reason` is `sending` while the provider call is in flight, else
  a short code from the last error (`nil` when there is none). `at` is when it last changed.
  `detail`, `retryable` and `retry_after_seconds` are the provider's, when its error said
  (ux ScheduleFlow f05d68e9). `resolved` is `%{by, at}` for an operator's resolution (U29), from
  `resolved_by` / `resolved_at` on the error document, the resolver named through `ActorRef`
  (`names`, from `ActorRef.names/2` over the plan's organization, #468): an active member by
  their display name (or nil), the organization's own service by its name (api on #503), anyone
  else with id and name nil, never an email.
  """
  @spec bookings([struct()], ActorRef.names()) :: %{binary() => map()}
  def bookings(items, names \\ @no_names),
    do: Map.new(items, &{&1.contact_opportunity_snapshot_id, booking(&1, names)})

  defp booking(item, names) do
    error = error_document(item)
    provider = provider_error(error)

    %{
      state: booking_state(item),
      reason: booking_reason(item),
      at: item.completed_at || item.started_at || item.updated_at,
      detail: text(provider["detail"] || error["detail"]),
      retryable: boolean(provider["retryable"]),
      retry_after_seconds: positive(provider["retry_after_seconds"]),
      resolved: resolved(item.last_error_document || %{}, names)
    }
  end

  # A reserved item's document is evidence (an operator's "Mark booked"), not an error: it gives
  # `resolved`, never a reason or detail.
  defp error_document(%{lifecycle_state: :reserved}), do: %{}
  defp error_document(%{last_error_document: %{} = error}), do: error
  defp error_document(_item), do: %{}

  # ProviderError.to_map nests under `reason`.
  defp provider_error(%{"reason" => %{"category" => _} = provider}), do: provider
  defp provider_error(_error), do: %{}

  # Who and when, both or neither (U29): a resolver ActorRef can't read gives no `resolved`.
  defp resolved(%{"resolved_by" => %{} = by, "resolved_at" => at}, names) do
    case ActorRef.document(by, names) do
      nil -> nil
      named -> %{by: named, at: at}
    end
  end

  defp resolved(_error, _names), do: nil

  # #146 (#468): one batched lookup over every resolver; never by a stored name or an email.
  defp resolver_names(organization_id, items) do
    docs =
      for item <- items,
          %{"resolved_by" => %{} = by} <- [item.last_error_document],
          do: by

    ActorRef.names(organization_id, docs)
  end

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil
  defp boolean(value) when is_boolean(value), do: value
  defp boolean(_value), do: nil
  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp booking_state(%{lifecycle_state: :reserved}), do: "confirmed"
  defp booking_state(%{lifecycle_state: :uncertain}), do: "uncertain"
  defp booking_state(%{lifecycle_state: :rejected}), do: "rejected"

  defp booking_state(%{lifecycle_state: :failed} = item),
    do: if(placed?(item), do: "failed", else: "never_sent")

  defp booking_state(_pending_or_requesting), do: "never_sent"

  defp booking_reason(%{lifecycle_state: :requesting}), do: "sending"
  defp booking_reason(%{lifecycle_state: :reserved}), do: nil
  defp booking_reason(%{last_error_document: %{} = error}), do: error_code(error)
  defp booking_reason(_item), do: nil

  # Error documents differ by source: executions write `code`, reservation validation
  # `category`, attempt resolution a string `reason`, and a provider error (ProviderError.to_map)
  # its normalized category under `reason.category` (no_capacity, conflict, …).
  defp error_code(error) do
    nested = with %{"category" => category} <- error["reason"], do: category

    Enum.find(
      [error["code"], error["category"], nested, error["reason"]],
      &(is_binary(&1) and &1 != "")
    )
  end

  defp placed?(item),
    do: is_binary(item.provider_reservation_id) and item.provider_reservation_id != ""

  defp unconfirmed_of(items, counts, display, opts) do
    window = Keyword.get_lazy(opts, :window_ms, &window_ms/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    cutoff = DateTime.add(now, -window, :millisecond)

    case Enum.filter(items, &late?(&1, cutoff)) do
      [] ->
        nil

      late ->
        %{
          window_ms: window,
          booked: counts.confirmed,
          passes: passes(late, display)
        }
    end
  end

  @doc "The execution item of an approved plan's pass (for #53 resolve)."
  @spec item(binary(), binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, :booking_not_found}
  def item(organization_id, mission_id, plan_id, snapshot_id) do
    with {:ok, approved} <-
           ManagementContacts.fetch_approved_plan(organization_id, mission_id, plan_id),
         %{} = item <-
           organization_id
           |> ControlContacts.list_plan_execution(
             mission_id,
             plan_id,
             approved.contact_plan_version
           )
           |> Enum.find(&(&1.contact_opportunity_snapshot_id == snapshot_id)) do
      {:ok, item}
    else
      _missing -> {:error, :booking_not_found}
    end
  end

  defp late?(%{lifecycle_state: :uncertain, started_at: %DateTime{} = at}, cutoff),
    do: DateTime.compare(at, cutoff) == :lt

  defp late?(_item, _cutoff), do: false

  defp booking_display(org, mission, items) do
    ids =
      for item <- items,
          booking_state(item) != "never_sent",
          placed?(item),
          do: item.provider_reservation_id

    reservations = ProviderReservations.booking_display_fields(org, mission, ids)

    providers =
      if map_size(reservations) == 0 do
        %{}
      else
        org
        |> MissionProviders.list_providers(mission)
        |> Map.new(&{&1.provider_id, &1.display_name})
      end

    names =
      for {_id, reservation} <- reservations,
          name = providers[reservation.provider_id],
          uniq: true,
          do: name

    %{reservations: reservations, providers: providers, provider_names: Enum.sort(names)}
  end

  defp passes(items, display) do
    items
    |> Enum.map(fn item ->
      reservation = display.reservations[item.provider_reservation_id]

      {reservation && reservation.starts_at,
       %{
         snapshot_id: item.contact_opportunity_snapshot_id,
         item_id: item.contact_plan_execution_item_id,
         provider:
           reservation &&
             %{
               id: reservation.provider_id,
               name: Map.get(display.providers, reservation.provider_id)
             },
         sent_at: item.started_at
       }}
    end)
    |> Enum.sort_by(fn {starts_at, _pass} -> starts_at end, &soonest/2)
    |> Enum.map(fn {_starts_at, pass} -> pass end)
  end

  defp soonest(nil, _b), do: false
  defp soonest(_a, nil), do: true
  defp soonest(a, b), do: DateTime.compare(a, b) != :gt
end
