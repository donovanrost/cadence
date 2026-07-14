defmodule CadenceWeb.OpsContactScheduleLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.OpsContactScheduleLive.Components

  alias CadenceWeb.OpsContactScheduleLive.{LiveDeps, OpportunityToken}

  @nonterminal_states [:requesting, :pending, :confirmed, :active, :unknown, :canceling]

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    spacecraft = LiveDeps.list_spacecraft(scope.organization_id, mission.mission_id)
    spacecraft_id = spacecraft |> List.first() |> then(&if(&1, do: &1.spacecraft_id, else: ""))

    socket =
      socket
      |> stream_configure(:opportunities,
        dom_id: fn opportunity ->
          "opportunity-#{opportunity["id"]}"
        end
      )
      |> stream_configure(:provider_reservations,
        dom_id: fn row ->
          "provider-reservation-#{row.reservation.provider_reservation_id}"
        end
      )
      |> assign(:page_title, "Contact Scheduling")
      |> assign(:ops_nav_item, :contacts)
      |> assign(:spacecraft, spacecraft)
      |> assign(:opportunity_count, 0)
      |> assign(:opportunities_empty?, true)
      |> assign(:searching?, false)
      |> assign(:search_ref, nil)
      |> assign(:search_error, nil)
      |> assign(:reservation_busy, MapSet.new())
      |> assign(:refresh_timer, nil)
      |> stream(:opportunities, [])
      |> assign_route_context(spacecraft_id, %{})
      |> refresh_reservations()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"contact_search" => params}, socket) do
    spacecraft_id = Map.get(params, "spacecraft_id", "")

    {:noreply,
     socket
     |> assign(:search_error, nil)
     |> assign_route_context(spacecraft_id, params)}
  end

  def handle_event("search", %{"contact_search" => params}, socket) do
    with {:ok, window} <- search_window(params),
         route_key when is_binary(route_key) and route_key != "" <- params["route_key"] do
      search_ref = System.unique_integer([:positive, :monotonic])
      %{current_scope: scope, current_mission: mission} = socket.assigns

      socket =
        socket
        |> assign(:searching?, true)
        |> assign(:search_ref, search_ref)
        |> assign(:search_error, nil)
        |> start_async({:search_opportunities, search_ref}, fn ->
          LiveDeps.search_opportunities(
            scope.organization_id,
            mission.mission_id,
            route_key,
            window
          )
        end)

      {:noreply, socket}
    else
      nil -> {:noreply, assign(socket, :search_error, "Select a ready downlink route.")}
      "" -> {:noreply, assign(socket, :search_error, "Select a ready downlink route.")}
      {:error, message} -> {:noreply, assign(socket, :search_error, message)}
    end
  end

  def handle_event("reserve", %{"token" => token}, socket) do
    with {:ok, payload} <- OpportunityToken.verify(token),
         :ok <- validate_token_scope(socket, payload),
         {:ok, route} <- resolve_token_route(socket, payload),
         :ok <- validate_token_route(route, payload["route"]),
         opportunity_id when is_binary(opportunity_id) <- payload["opportunity"]["id"],
         false <- MapSet.member?(socket.assigns.reservation_busy, opportunity_id) do
      %{current_scope: scope, current_mission: mission} = socket.assigns
      attrs = reservation_attrs(payload, route)

      socket =
        socket
        |> assign(
          :reservation_busy,
          MapSet.put(socket.assigns.reservation_busy, opportunity_id)
        )
        |> start_async({:reserve_opportunity, opportunity_id}, fn ->
          LiveDeps.reserve(
            scope.organization_id,
            mission.mission_id,
            route.provider_profile_id,
            attrs
          )
        end)

      {:noreply, socket}
    else
      true ->
        {:noreply, socket}

      {:error, :expired} ->
        {:noreply, put_flash(socket, :error, "That opportunity expired. Search again.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That opportunity is no longer valid.")}

      _other ->
        {:noreply, put_flash(socket, :error, "That opportunity could not be reserved.")}
    end
  end

  def handle_event("cancel", %{"reservation-id" => reservation_id}, socket) do
    if MapSet.member?(socket.assigns.reservation_busy, reservation_id) do
      {:noreply, socket}
    else
      %{current_scope: scope, current_mission: mission} = socket.assigns

      socket =
        socket
        |> assign(
          :reservation_busy,
          MapSet.put(socket.assigns.reservation_busy, reservation_id)
        )
        |> start_async({:cancel_reservation, reservation_id}, fn ->
          LiveDeps.cancel(scope.organization_id, mission.mission_id, reservation_id)
        end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(
        {:search_opportunities, search_ref},
        {:ok, {:ok, %{opportunities: opportunities, route: route}}},
        %{assigns: %{search_ref: search_ref}} = socket
      ) do
    signed_opportunities = Enum.map(opportunities, &sign_opportunity(socket, route, &1))

    {:noreply,
     socket
     |> assign(:searching?, false)
     |> assign(:search_error, nil)
     |> assign(:opportunity_count, length(signed_opportunities))
     |> assign(:opportunities_empty?, signed_opportunities == [])
     |> stream(:opportunities, signed_opportunities, reset: true)}
  end

  def handle_async(
        {:search_opportunities, search_ref},
        {:ok, {:error, reason}},
        %{assigns: %{search_ref: search_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:searching?, false)
     |> assign(:search_error, search_error(reason))
     |> assign(:opportunity_count, 0)
     |> assign(:opportunities_empty?, true)
     |> stream(:opportunities, [], reset: true)}
  end

  def handle_async({:search_opportunities, search_ref}, {:exit, reason}, socket) do
    if socket.assigns.search_ref == search_ref do
      {:noreply,
       socket
       |> assign(:searching?, false)
       |> assign(:search_error, search_error(reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:search_opportunities, _stale_ref}, _result, socket), do: {:noreply, socket}

  def handle_async({:reserve_opportunity, opportunity_id}, {:ok, result}, socket) do
    socket = clear_busy(socket, opportunity_id)

    case result do
      {:ok, %{provider_reservation: reservation}} ->
        message =
          if reservation.lifecycle_state in [:confirmed, :active, :completed],
            do: "Contact reserved and scheduled.",
            else: "Reservation recorded; provider confirmation is pending."

        {:noreply, socket |> refresh_reservations() |> put_flash(:info, message)}

      {:error, {:provider_reservation_not_confirmed, _reservation}} ->
        {:noreply,
         socket
         |> refresh_reservations()
         |> put_flash(:error, "Provider outcome is not confirmed; Cadence will reconcile it.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_reservations()
         |> put_flash(:error, "Reservation could not be completed.")}
    end
  end

  def handle_async({:reserve_opportunity, opportunity_id}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> clear_busy(opportunity_id)
     |> refresh_reservations()
     |> put_flash(:error, "Reservation worker stopped unexpectedly; durable state was preserved.")}
  end

  def handle_async({:cancel_reservation, reservation_id}, {:ok, result}, socket) do
    socket = clear_busy(socket, reservation_id)

    case result do
      {:ok, _booking} ->
        {:noreply,
         socket |> refresh_reservations() |> put_flash(:info, "Cancellation confirmed.")}

      {:error, {:provider_reservation_not_confirmed, _reservation}} ->
        {:noreply,
         socket
         |> refresh_reservations()
         |> put_flash(:error, "Cancellation is uncertain; Cadence will reconcile it.")}

      {:error, _reason} ->
        {:noreply, socket |> refresh_reservations() |> put_flash(:error, "Cancellation failed.")}
    end
  end

  def handle_async({:cancel_reservation, reservation_id}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> clear_busy(reservation_id)
     |> refresh_reservations()
     |> put_flash(:error, "Cancellation worker stopped; durable state was preserved.")}
  end

  @impl true
  def handle_info(:refresh_provider_reservations, socket) do
    {:noreply, socket |> assign(:refresh_timer, nil) |> refresh_reservations()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="ops-contacts-page" class="h-full overflow-y-auto bg-base-100">
      <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
        <div class="mx-auto flex max-w-[96rem] flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
              Mission operations / downlink
            </p>
            <h1 class="mt-1 text-2xl font-bold tracking-tight text-base-content">
              Contact window control
            </h1>
            <p class="mt-2 max-w-2xl text-sm text-base-content/60">
              Search provider availability, reserve capacity, and track Cadence contact realization through one durable workflow.
            </p>
          </div>
          <div class="flex items-center gap-4 border-l border-primary/30 pl-4 font-mono text-xs">
            <div>
              <p class="hud-label">Scope</p>
              <p class="mt-1 text-base-content/70">Downlink only</p>
            </div>
            <div>
              <p class="hud-label">Reservations</p>
              <p id="provider-reservation-count" class="mt-1 text-primary">
                {@reservation_count}
              </p>
            </div>
          </div>
        </div>
      </header>

      <div class="mx-auto grid max-w-[96rem] gap-5 p-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(22rem,0.75fr)] lg:p-7">
        <div class="min-w-0 space-y-5">
          <section class="border border-base-300 bg-base-200/35 shadow-sm">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <div>
                <p class="hud-label">01 / Opportunity search</p>
                <p class="mt-1 text-sm text-base-content/60">All times are coordinated universal time.</p>
              </div>
              <.icon name="hero-signal" class="h-5 w-5 text-primary/60" />
            </div>

            <.form
              for={@search_form}
              id="contact-opportunity-search-form"
              phx-change="validate"
              phx-submit="search"
              class="grid gap-4 p-4 md:grid-cols-2 xl:grid-cols-4"
            >
              <.input
                id="contact-spacecraft"
                field={@search_form[:spacecraft_id]}
                type="select"
                label="Spacecraft"
                options={spacecraft_options(@spacecraft)}
              />
              <.input
                id="contact-route"
                field={@search_form[:route_key]}
                type="select"
                label="Downlink route / provider"
                options={route_options(@ready_routes)}
              />
              <.input
                id="contact-window-start"
                field={@search_form[:starts_at]}
                type="datetime-local"
                label="Window starts (UTC)"
              />
              <.input
                id="contact-window-end"
                field={@search_form[:ends_at]}
                type="datetime-local"
                label="Window ends (UTC)"
              />
              <div class="flex items-center gap-3 md:col-span-2 xl:col-span-4">
                <button
                  id="search-contact-opportunities"
                  type="submit"
                  disabled={@searching? or @ready_routes == []}
                  class="btn btn-primary btn-sm min-w-40 font-mono text-xs uppercase tracking-wider disabled:opacity-50"
                >
                  <%= if @searching? do %>
                    Searching provider
                  <% else %>
                    Search opportunities
                  <% end %>
                </button>
                <p :if={@search_error} id="contact-search-error" class="text-sm text-error">
                  {@search_error}
                </p>
              </div>
            </.form>

            <div
              :if={@ready_routes == []}
              id="contact-readiness-empty"
              class="mx-4 mb-4 border-l-2 border-warning bg-warning/5 px-4 py-3"
            >
              <p class="text-sm font-semibold text-warning">No provider-ready downlink route</p>
              <div class="mt-2 space-y-1 text-xs text-base-content/60">
                <p :for={finding <- @readiness_findings}>{finding.message}</p>
              </div>
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing"}
                class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
              >
                Review Comms routing <.icon name="hero-arrow-right" class="h-3 w-3" />
              </.link>
            </div>
          </section>

          <section class="border border-base-300 bg-base-200/20">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <div>
                <p class="hud-label">02 / Provider opportunities</p>
                <p class="mt-1 text-sm text-base-content/60">
                  Select a provider-owned window to create a durable reservation attempt.
                </p>
              </div>
              <span id="contact-opportunity-count" class="font-mono text-sm text-primary">
                {@opportunity_count}
              </span>
            </div>

            <div id="contact-opportunities" phx-update="stream">
              <div id="contact-opportunities-empty" class="hidden only:block px-4 py-12 text-center">
                <.icon name="hero-magnifying-glass" class="mx-auto h-6 w-6 text-base-content/30" />
                <p class="mt-3 text-sm text-base-content/55">Search a UTC window to load provider opportunities.</p>
              </div>
              <.opportunity_row
                :for={{dom_id, opportunity} <- @streams.opportunities}
                id={dom_id}
                opportunity={opportunity}
                busy?={MapSet.member?(@reservation_busy, opportunity["id"])}
              />
            </div>
          </section>
        </div>

        <aside class="min-w-0 border border-base-300 bg-base-200/25 lg:sticky lg:top-0 lg:self-start">
          <div class="border-b border-base-300 px-4 py-3">
            <p class="hud-label">03 / Reservation ledger</p>
            <p class="mt-1 text-sm text-base-content/60">
              Provider truth and Cadence contact state remain visible independently.
            </p>
          </div>
          <div id="provider-reservations" phx-update="stream">
            <div id="provider-reservations-empty" class="hidden only:block px-4 py-12 text-center">
              <.icon name="hero-calendar-days" class="mx-auto h-6 w-6 text-base-content/30" />
              <p class="mt-3 text-sm text-base-content/55">No provider reservations for this mission.</p>
            </div>
            <.reservation_row
              :for={{dom_id, row} <- @streams.provider_reservations}
              id={dom_id}
              row={row}
              busy?={MapSet.member?(
                @reservation_busy,
                row.reservation.provider_reservation_id
              )}
            />
          </div>
        </aside>
      </div>
    </section>
    """
  end

  defp assign_route_context(socket, spacecraft_id, params) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    readiness =
      if spacecraft_id == "" do
        %{routes: [], findings: []}
      else
        case LiveDeps.list_ready_routes(scope.organization_id, mission.mission_id, spacecraft_id) do
          {:ok, readiness} -> readiness
          {:error, _reason} -> %{routes: [], findings: []}
        end
      end

    existing_route = Map.get(params, "route_key", "")

    route_key =
      if Enum.any?(readiness.routes, &(&1.route_key == existing_route)) do
        existing_route
      else
        readiness.routes |> List.first() |> then(&if(&1, do: &1.route_key, else: ""))
      end

    form_params =
      default_search_params(spacecraft_id, route_key)
      |> Map.merge(params)
      |> Map.put("spacecraft_id", spacecraft_id)
      |> Map.put("route_key", route_key)

    socket
    |> assign(:ready_routes, readiness.routes)
    |> assign(:readiness_findings, readiness.findings)
    |> assign(:search_form, to_form(form_params, as: :contact_search))
  end

  defp default_search_params(spacecraft_id, route_key) do
    starts_at = DateTime.utc_now() |> DateTime.add(5 * 60) |> DateTime.truncate(:second)

    %{
      "spacecraft_id" => spacecraft_id,
      "route_key" => route_key,
      "starts_at" => datetime_local(starts_at),
      "ends_at" => starts_at |> DateTime.add(6 * 60 * 60) |> datetime_local()
    }
  end

  defp search_window(params) do
    with {:ok, starts_at} <- parse_datetime_local(params["starts_at"]),
         {:ok, ends_at} <- parse_datetime_local(params["ends_at"]),
         true <- DateTime.before?(starts_at, ends_at) do
      {:ok,
       %{
         "spacecraft_id" => params["spacecraft_id"],
         "starts_at" => DateTime.to_iso8601(starts_at),
         "ends_at" => DateTime.to_iso8601(ends_at)
       }}
    else
      false -> {:error, "Window end must be after its start."}
      {:error, _reason} -> {:error, "Enter a valid UTC start and end time."}
    end
  end

  defp parse_datetime_local(value) when is_binary(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:ok, naive} <- NaiveDateTime.from_iso8601(value),
         {:ok, datetime} <- DateTime.from_naive(naive, "Etc/UTC") do
      {:ok, datetime}
    else
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime_local(_value), do: {:error, :invalid_datetime}

  defp sign_opportunity(socket, route, opportunity) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    payload = %{
      "organization_id" => scope.organization_id,
      "mission_id" => mission.mission_id,
      "spacecraft_id" => route.spacecraft_id,
      "route_key" => route.route_key,
      "route" => token_route(route),
      "opportunity" => Map.drop(opportunity, ["booking_token"])
    }

    Map.put(opportunity, "booking_token", OpportunityToken.sign(payload))
  end

  defp validate_token_scope(socket, payload) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    if payload["organization_id"] == scope.organization_id and
         payload["mission_id"] == mission.mission_id do
      :ok
    else
      {:error, :opportunity_scope_mismatch}
    end
  end

  defp resolve_token_route(socket, payload) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    LiveDeps.resolve_ready_route(
      scope.organization_id,
      mission.mission_id,
      payload["spacecraft_id"],
      payload["route_key"]
    )
  end

  defp validate_token_route(route, signed_route) do
    if token_route(route) == signed_route, do: :ok, else: {:error, :route_changed}
  end

  defp token_route(route) do
    %{
      "provider_profile_id" => route.provider_profile_id,
      "provider_profile_version" => route.provider_profile_version,
      "path_template_id" => route.path_template_id,
      "path_template_version" => route.path_template_version,
      "source_endpoint_id" => route.source_endpoint_id,
      "provider_spacecraft_ref" => route.provider_spacecraft_ref
    }
  end

  defp reservation_attrs(payload, route) do
    opportunity = payload["opportunity"]
    stable_suffix = stable_booking_suffix(payload)

    opportunity
    |> Map.take([
      "opportunity_id",
      "id",
      "run_id",
      "ground_station_id",
      "antenna_id",
      "starts_at",
      "ends_at"
    ])
    |> Map.put("opportunity_id", opportunity["id"])
    |> Map.put("provider_reservation_id", "provider_reservation_#{stable_suffix}")
    |> Map.put("scheduled_contact_id", "scheduled_contact_#{stable_suffix}")
    |> Map.put("idempotency_key", "cadence:contact:#{stable_suffix}")
    |> Map.put("provider_profile_version", route.provider_profile_version)
    |> Map.put("cadence_spacecraft_id", route.spacecraft_id)
    |> Map.put("provider_spacecraft_ref", route.provider_spacecraft_ref)
    |> Map.put("source_endpoint_refs", [route.source_endpoint_id])
    |> Map.put("path_template_ids", [route.path_template_id])
    |> Map.put("path_template_refs", [
      %{
        "path_template_id" => route.path_template_id,
        "version" => route.path_template_version
      }
    ])
  end

  defp stable_booking_suffix(payload) do
    [
      payload["organization_id"],
      payload["mission_id"],
      payload["route_key"],
      payload["opportunity"]["id"]
    ]
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 24)
  end

  defp refresh_reservations(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    rows = LiveDeps.list_reservation_rows(scope.organization_id, mission.mission_id)

    socket =
      socket
      |> assign(:reservation_count, length(rows))
      |> stream(:provider_reservations, rows, reset: true)

    if connected?(socket) and
         Enum.any?(rows, &(&1.reservation.lifecycle_state in @nonterminal_states)) do
      schedule_reservation_refresh(socket)
    else
      socket
    end
  end

  defp schedule_reservation_refresh(%{assigns: %{refresh_timer: nil}} = socket) do
    timer =
      Process.send_after(self(), :refresh_provider_reservations, LiveDeps.refresh_interval_ms())

    assign(socket, :refresh_timer, timer)
  end

  defp schedule_reservation_refresh(socket), do: socket

  defp clear_busy(socket, key) do
    assign(socket, :reservation_busy, MapSet.delete(socket.assigns.reservation_busy, key))
  end

  defp spacecraft_options(spacecraft) do
    Enum.map(spacecraft, &{&1.display_name, &1.spacecraft_id})
  end

  defp route_options(routes) do
    Enum.map(routes, fn route ->
      {"#{route.provider_display_name} / #{route.route_display_name}", route.route_key}
    end)
  end

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")

  defp search_error(:opportunity_window_in_past),
    do: "The search window starts in the past. Choose a future UTC time."

  defp search_error(:opportunity_window_too_large),
    do: "The search horizon is limited to seven days."

  defp search_error(:invalid_opportunity_window),
    do: "Window end must be after its start."

  defp search_error(_reason),
    do: "The provider search failed. Check provider readiness and try again."
end
