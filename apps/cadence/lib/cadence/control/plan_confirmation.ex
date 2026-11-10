defmodule Cadence.Control.PlanConfirmation do
  @moduledoc """
  The bookings of an approved plan that the provider hasn't confirmed within the confirmation
  window (DECISIONS #52, ux U30): execution items still `uncertain` and placed (`started_at`)
  longer ago than `:provider_confirmation_window_ms`. Plan detail carries it, so the console can
  say which passes wait on which provider instead of guessing from reservation states.
  """

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.GroundNetworks.MissionProviders
  alias Cadence.Management.Contacts, as: ManagementContacts

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
  `%{unconfirmed: unconfirmed/4's value, execution: execution summary | nil}`.
  """
  @spec detail(binary(), binary(), binary(), keyword()) :: %{
          unconfirmed: map() | nil,
          execution: map() | nil
        }
  def detail(organization_id, mission_id, plan_id, opts \\ []) do
    case ManagementContacts.fetch_approved_plan(organization_id, mission_id, plan_id) do
      {:ok, approved} ->
        items =
          ControlContacts.list_plan_execution(
            organization_id,
            mission_id,
            plan_id,
            approved.contact_plan_version
          )

        %{
          unconfirmed: unconfirmed_of(organization_id, mission_id, items, opts),
          execution: execution(items)
        }

      _not_approved ->
        %{unconfirmed: nil, execution: nil}
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
    placed? = &(is_binary(&1.provider_reservation_id) and &1.provider_reservation_id != "")
    count = fn state -> Enum.count(items, &(&1.lifecycle_state == state)) end
    failed = Enum.count(items, &(&1.lifecycle_state == :failed and placed?.(&1)))

    summary = %{
      requested: length(items),
      confirmed: count.(:reserved),
      uncertain: count.(:uncertain),
      rejected: count.(:rejected),
      failed: failed
    }

    sent = summary.confirmed + summary.uncertain + summary.rejected + failed
    Map.merge(summary, %{sent: sent, never_sent: summary.requested - sent})
  end

  defp unconfirmed_of(organization_id, mission_id, items, opts) do
    window = Keyword.get_lazy(opts, :window_ms, &window_ms/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    cutoff = DateTime.add(now, -window, :millisecond)

    case Enum.filter(items, &late?(&1, cutoff)) do
      [] ->
        nil

      late ->
        %{
          window_ms: window,
          booked: Enum.count(items, &(&1.lifecycle_state == :reserved)),
          passes: passes(organization_id, mission_id, late)
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

  defp passes(organization_id, mission_id, items) do
    providers =
      organization_id
      |> MissionProviders.list_providers(mission_id)
      |> Map.new(&{&1.provider_id, &1.display_name})

    items
    |> Enum.map(fn item ->
      reservation =
        case ControlContacts.fetch_provider_reservation(
               organization_id,
               mission_id,
               item.provider_reservation_id
             ) do
          {:ok, reservation} -> reservation
          _missing -> nil
        end

      {reservation && reservation.starts_at,
       %{
         snapshot_id: item.contact_opportunity_snapshot_id,
         item_id: item.contact_plan_execution_item_id,
         provider:
           reservation &&
             %{id: reservation.provider_id, name: Map.get(providers, reservation.provider_id)},
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
