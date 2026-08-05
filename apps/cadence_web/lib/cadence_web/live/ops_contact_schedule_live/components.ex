defmodule CadenceWeb.OpsContactScheduleLive.Components do
  @moduledoc false

  use CadenceWeb, :html

  attr :id, :string, required: true
  attr :opportunity, :map, required: true
  attr :busy?, :boolean, default: false

  def opportunity_row(assigns) do
    ~H"""
    <article id={@id} class="group grid gap-4 border-b border-base-300/70 px-4 py-4 transition-colors hover:bg-primary/[0.035] xl:grid-cols-[minmax(0,1.2fr)_minmax(11rem,0.7fr)_8rem] xl:items-center">
      <div class="min-w-0">
        <div class="mb-1 flex items-center gap-2">
          <span class="h-1.5 w-1.5 rounded-full bg-success shadow-[0_0_8px_currentColor]"></span>
          <span class="font-mono text-[0.65rem] uppercase tracking-[0.18em] text-base-content/50">
            {@opportunity["provider_display_name"] || "Ground station provider"}
          </span>
        </div>
        <p class="truncate text-sm font-semibold text-base-content">
          {format_time(@opportunity["starts_at"])} — {format_time(@opportunity["ends_at"])}
        </p>
        <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
          {@opportunity["service_display_name"] || @opportunity["service_profile_ref"]} · {@opportunity["delivery_operator_summary"] || @opportunity["delivery_display_name"]}
        </p>
      </div>

      <div class="border-l border-base-300/70 pl-4">
        <p class="hud-label">Delivery / antenna</p>
        <p class="mt-1 truncate font-mono text-xs text-base-content/70">
          {@opportunity["delivery_display_name"] || "Provider managed"}
        </p>
        <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/40">
          {@opportunity["antenna_or_service_pool_ref"] || "Provider assigned"}
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
  attr :mission_id, :string, required: true

  def contact_record_row(assigns) do
    ~H"""
    <article
      id={@id}
      class="grid gap-3 border-b border-base-300/70 px-4 py-4 transition-colors hover:bg-primary/[0.035] lg:grid-cols-[minmax(15rem,1.25fr)_minmax(10rem,0.7fr)_minmax(12rem,0.9fr)_auto] lg:items-center"
      data-contact-record-kind={if(@row.realized_contact, do: "realized", else: "scheduled")}
      data-contact-record-state={@row.lifecycle_state}
    >
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <.reservation_status state={@row.lifecycle_state} />
          <span class="font-mono text-[0.62rem] uppercase tracking-[0.14em] text-base-content/45">
            {if(@row.realized_contact, do: "Realized contact", else: "Scheduled contact")}
          </span>
        </div>
        <p class="mt-2 truncate font-mono text-xs font-semibold text-base-content/80">
          {@row.canonical_id}
        </p>
      </div>

      <div>
        <p class="hud-label">Operational window</p>
        <p class="mt-1 font-mono text-xs text-base-content/70">
          {format_time(@row.starts_at)}
        </p>
        <p class="mt-0.5 font-mono text-[0.66rem] text-base-content/45">
          to {format_time(@row.ends_at)}
        </p>
      </div>

      <div class="min-w-0">
        <p class="hud-label">Intent / source</p>
        <p class="mt-1 truncate text-xs text-base-content/70">
          {contact_intents(@row.contact_intents)}
        </p>
        <p class="mt-0.5 truncate font-mono text-[0.66rem] text-base-content/45">
          {source_endpoints(@row.source_endpoint_refs)}
        </p>
      </div>

      <.link
        id={"open-contact-record-#{@row.canonical_id}"}
        navigate={~p"/missions/#{@mission_id}/ops/contacts/records/#{@row.canonical_id}"}
        class="btn btn-sm btn-outline justify-self-start lg:justify-self-end"
      >
        Inspect <.icon name="hero-arrow-right" class="h-3.5 w-3.5" />
      </.link>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :busy?, :boolean, default: false
  attr :mission_id, :string, required: true
  attr :admin?, :boolean, default: false

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

      <.link
        id={"open-reservation-#{@reservation.provider_reservation_id}"}
        navigate={~p"/missions/#{@mission_id}/ops/contacts/#{@reservation.provider_reservation_id}"}
        class="mt-3 inline-flex items-center gap-1 font-mono text-[0.66rem] font-semibold uppercase tracking-[0.14em] text-primary hover:underline"
      >
        Open provider reservation <.icon name="hero-arrow-right" class="h-3 w-3" />
      </.link>

      <div class="mt-3 grid grid-cols-3 gap-px border border-base-300/60 bg-base-300/60 text-xs">
        <.observation_cell
          id={"reservation-contact-status-#{@reservation.provider_reservation_id}"}
          label="Contact"
          value={@reservation.provider_status || @reservation.lifecycle_state}
        />
        <.observation_cell
          id={"reservation-pass-phase-#{@reservation.provider_reservation_id}"}
          label="Pass"
          value={@reservation.pass_phase}
        />
        <.observation_cell
          id={"reservation-delivery-status-#{@reservation.provider_reservation_id}"}
          label="Delivery"
          value={@reservation.delivery_state}
        />
      </div>

      <div class="mt-3 grid gap-3 border-t border-base-300/60 pt-3 text-xs sm:grid-cols-2">
        <div id={"reservation-provider-#{@reservation.provider_reservation_id}"}>
          <p class="hud-label">Provider</p>
          <p class="mt-1 truncate text-base-content/70">
            {@reservation.metadata["provider_display_name"] || @reservation.provider_id}
            <span class="font-mono text-base-content/40">v{@reservation.provider_version}</span>
          </p>
        </div>
        <div id={"reservation-transport-#{@reservation.provider_reservation_id}"}>
          <p class="hud-label">Transport</p>
          <p class="mt-1 truncate text-base-content/70">
            {@reservation.metadata["transport_display_name"] || @reservation.transport_id}
            <span class="font-mono text-base-content/40">v{@reservation.transport_version}</span>
          </p>
        </div>
        <div id={"reservation-service-#{@reservation.provider_reservation_id}"}>
          <p class="hud-label">Service</p>
          <p class="mt-1 truncate text-base-content/70">
            {@reservation.metadata["service_display_name"] || @reservation.service_profile_ref["id"]}
            <span class="font-mono text-base-content/40">v{@reservation.service_profile_ref["version"]}</span>
          </p>
        </div>
        <div id={"reservation-delivery-#{@reservation.provider_reservation_id}"}>
          <p class="hud-label">Delivery</p>
          <p class="mt-1 truncate text-base-content/70">
            {@reservation.metadata["delivery_operator_summary"] || @reservation.metadata["delivery_display_name"] || @reservation.delivery_profile_ref["id"]}
            <span class="font-mono text-base-content/40">v{@reservation.delivery_profile_ref["version"]}</span>
          </p>
        </div>
      </div>

      <div :if={@reservation.lifecycle_state in [:unknown, :canceling]} class="mt-3 border-l-2 border-warning/70 pl-3">
        <p class="text-xs text-warning/80">Provider state is uncertain; reconciliation will retry.</p>
      </div>

      <div :if={configuration_failure?(@reservation)} class="mt-3 border-l-2 border-error/70 bg-error/5 px-3 py-2">
        <p class="text-xs font-semibold text-error">Provider delivery conflicts with approved setup.</p>
        <p class="mt-1 text-xs text-base-content/55">The reservation remains durable; Cadence will not use the unapproved descriptor.</p>
      </div>

      <details
        :if={@admin?}
        id={"reservation-diagnostics-#{@reservation.provider_reservation_id}"}
        class="mt-3 border-t border-base-300/60 pt-3"
      >
        <summary class="cursor-pointer font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45 hover:text-primary">
          Administrator diagnostics
        </summary>
        <dl class="mt-3 grid gap-2 font-mono text-[0.65rem] text-base-content/55">
          <div><dt class="inline text-base-content/35">Provider contact </dt><dd class="inline">{@reservation.provider_contact_ref || "not assigned"}</dd></div>
          <div><dt class="inline text-base-content/35">Cadence contact </dt><dd class="inline">{contact_state(@row.scheduled_contact)}</dd></div>
          <div><dt class="inline text-base-content/35">Transport ref </dt><dd class="inline">{@reservation.transport_id}:v{@reservation.transport_version}</dd></div>
          <div><dt class="inline text-base-content/35">Descriptor </dt><dd class="inline">{descriptor_state(@reservation.delivery_descriptor_document)}</dd></div>
        </dl>
      </details>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true

  def observation_cell(assigns) do
    ~H"""
    <div id={@id} class="bg-base-200/70 px-3 py-2">
      <p class="hud-label">{@label}</p>
      <p class="mt-1 font-mono text-[0.68rem] font-semibold uppercase text-base-content/70">{@value}</p>
    </div>
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

  defp configuration_failure?(reservation) do
    reservation.last_error_document["category"] == "provider_configuration_failure"
  end

  defp contact_state(nil), do: "not materialized"
  defp contact_state(contact), do: Atom.to_string(contact.lifecycle_state)

  defp descriptor_state(document) when document == %{}, do: "not observed"
  defp descriptor_state(_document), do: "validated immutable snapshot"

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%MZ")

  defp format_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_time(datetime)
      _error -> value
    end
  end

  defp format_time(_value), do: "Time unavailable"

  defp contact_intents([]), do: "No declared intent"
  defp contact_intents(intents), do: Enum.map_join(intents, " · ", &humanize/1)

  defp source_endpoints([]), do: "No source endpoint"
  defp source_endpoints(refs), do: Enum.join(refs, " · ")

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
  end
end
