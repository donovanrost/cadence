defmodule CadenceWeb.OpsContactScheduleLive.Components do
  @moduledoc false

  use CadenceWeb, :html

  attr :id, :string, required: true
  attr :opportunity, :map, required: true
  attr :busy?, :boolean, default: false

  def opportunity_row(assigns) do
    ~H"""
    <article id={@id} class="group grid gap-4 border-b border-base-300/70 px-4 py-4 transition-colors hover:bg-primary/[0.035] xl:grid-cols-[minmax(0,1fr)_11rem_8rem] xl:items-center">
      <div class="min-w-0">
        <div class="mb-1 flex items-center gap-2">
          <span class="h-1.5 w-1.5 rounded-full bg-success shadow-[0_0_8px_currentColor]"></span>
          <span class="font-mono text-[0.65rem] uppercase tracking-[0.18em] text-base-content/50">
            {@opportunity["ground_station_id"] || "Ground station"}
          </span>
        </div>
        <p class="truncate text-sm font-semibold text-base-content">
          {format_time(@opportunity["starts_at"])} — {format_time(@opportunity["ends_at"])}
        </p>
        <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
          {@opportunity["id"]}
        </p>
      </div>

      <div class="border-l border-base-300/70 pl-4">
        <p class="hud-label">Antenna</p>
        <p class="mt-1 truncate font-mono text-xs text-base-content/70">
          {@opportunity["antenna_id"] || "Provider assigned"}
        </p>
      </div>

      <button
        id={"reserve-opportunity-#{@opportunity["id"]}"}
        type="button"
        phx-click="reserve"
        phx-value-token={@opportunity["booking_token"]}
        disabled={@busy?}
        class="btn btn-primary btn-sm w-full font-mono text-[0.7rem] uppercase tracking-wider disabled:opacity-50"
      >
        <%= if @busy? do %>
          Reserving
        <% else %>
          Reserve
        <% end %>
      </button>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :busy?, :boolean, default: false

  def reservation_row(assigns) do
    reservation = assigns.row.reservation
    assigns = assign(assigns, :reservation, reservation)

    ~H"""
    <article id={@id} class="border-b border-base-300/70 px-4 py-4">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <.reservation_status state={@reservation.lifecycle_state} />
            <span class="font-mono text-[0.62rem] uppercase tracking-wider text-base-content/45">
              {@reservation.provider_status || "awaiting provider"}
            </span>
          </div>
          <p class="mt-2 text-sm font-semibold">
            {format_time(@reservation.starts_at)} — {format_time(@reservation.ends_at)}
          </p>
          <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
            {@reservation.provider_reservation_id}
          </p>
        </div>

        <button
          :if={cancelable?(@reservation.lifecycle_state)}
          id={"cancel-reservation-#{@reservation.provider_reservation_id}"}
          type="button"
          phx-click="cancel"
          phx-value-reservation-id={@reservation.provider_reservation_id}
          disabled={@busy?}
          class="btn btn-ghost btn-xs text-error disabled:opacity-50"
        >
          Cancel
        </button>
      </div>

      <div class="mt-3 grid grid-cols-2 gap-3 border-t border-base-300/60 pt-3 text-xs">
        <div>
          <p class="hud-label">Provider contact</p>
          <p class="mt-1 truncate font-mono text-base-content/65">
            {@reservation.provider_contact_ref || "Not confirmed"}
          </p>
        </div>
        <div>
          <p class="hud-label">Cadence contact</p>
          <p class="mt-1 truncate font-mono text-base-content/65">
            <%= if @row.scheduled_contact do %>
              {@row.scheduled_contact.lifecycle_state}
            <% else %>
              Not materialized
            <% end %>
          </p>
        </div>
      </div>

      <div :if={@reservation.lifecycle_state in [:unknown, :canceling]} class="mt-3 border-l-2 border-warning/70 pl-3">
        <p class="text-xs text-warning/80">Provider state is uncertain; reconciliation will retry.</p>
      </div>
    </article>
    """
  end

  attr :state, :atom, required: true

  def reservation_status(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-sm border px-2 py-0.5 font-mono text-[0.62rem] font-bold uppercase tracking-wider",
      status_class(@state)
    ]}>
      {@state}
    </span>
    """
  end

  defp status_class(state) when state in [:confirmed, :active, :completed],
    do: "border-success/40 bg-success/10 text-success"

  defp status_class(state) when state in [:rejected, :failed, :canceled],
    do: "border-error/40 bg-error/10 text-error"

  defp status_class(state) when state in [:unknown, :canceling],
    do: "border-warning/40 bg-warning/10 text-warning"

  defp status_class(_state), do: "border-info/40 bg-info/10 text-info"

  defp cancelable?(state), do: state in [:pending, :confirmed, :active, :unknown]

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%MZ")

  defp format_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_time(datetime)
      _error -> value
    end
  end

  defp format_time(_value), do: "Time unavailable"
end
