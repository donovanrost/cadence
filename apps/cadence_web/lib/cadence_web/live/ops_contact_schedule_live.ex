defmodule CadenceWeb.OpsContactScheduleLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias CadenceWeb.OpsContactScheduleLive.{LiveDeps, OpportunityToken}
  alias Phoenix.LiveView.JS

  @nonterminal_states [:requesting, :pending, :confirmed, :active, :unknown, :canceling]

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    live_deps = resolve_live_deps(socket)

    spacecraft =
      LiveDeps.list_spacecraft(live_deps, scope.organization_id, mission.mission_id)

    spacecraft_id = spacecraft |> List.first() |> then(&if(&1, do: &1.spacecraft_id, else: ""))

    socket =
      socket
      |> stream_configure(:contact_records,
        dom_id: & &1["__dom_id"]
      )
      |> stream_configure(:opportunities,
        dom_id: & &1["__dom_id"]
      )
      |> stream_configure(:provider_reservations,
        dom_id: & &1["__dom_id"]
      )
      |> assign(:page_title, "Contacts")
      |> assign(:ops_nav_item, :contacts)
      |> assign(:live_deps, live_deps)
      |> assign(:spacecraft, spacecraft)
      |> assign(:contact_record_count, 0)
      |> assign(:opportunity_count, 0)
      |> assign(:opportunities_empty?, true)
      |> assign(:searching?, false)
      |> assign(:search_ref, nil)
      |> assign(:search_error, nil)
      |> assign(:reservation_busy, MapSet.new())
      |> assign(:admin?, organization_admin?(scope))
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
      %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns

      socket =
        socket
        |> assign(:searching?, true)
        |> assign(:search_ref, search_ref)
        |> assign(:search_error, nil)
        |> start_async({:search_opportunities, search_ref}, fn ->
          LiveDeps.search_opportunities(
            live_deps,
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
      %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns
      attrs = reservation_attrs(payload, route)

      socket =
        socket
        |> assign(
          :reservation_busy,
          MapSet.put(socket.assigns.reservation_busy, opportunity_id)
        )
        |> start_async({:reserve_opportunity, opportunity_id}, fn ->
          LiveDeps.reserve(
            live_deps,
            scope.organization_id,
            mission.mission_id,
            route.provider_id,
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
    cond do
      not socket.assigns.admin? ->
        {:noreply,
         put_flash(socket, :error, "Only organization administrators may cancel reservations.")}

      MapSet.member?(socket.assigns.reservation_busy, reservation_id) ->
        {:noreply, socket}

      true ->
        %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns

        socket =
          socket
          |> assign(
            :reservation_busy,
            MapSet.put(socket.assigns.reservation_busy, reservation_id)
          )
          |> start_async({:cancel_reservation, reservation_id}, fn ->
            LiveDeps.cancel(
              live_deps,
              scope.organization_id,
              mission.mission_id,
              reservation_id
            )
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
    signed_opportunities =
      Enum.map(opportunities, fn opportunity ->
        socket
        |> sign_opportunity(route, opportunity)
        |> opportunity_dto()
      end)

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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-schedule-component"
        v-component="OpsContactSchedule"
        page={page_dto(
          @current_mission,
          @contact_record_count,
          @opportunity_count,
          @reservation_count,
          @opportunities_empty?
        )}
        search={search_dto(
          @search_form,
          @spacecraft,
          @ready_routes,
          @searching?,
          @search_error
        )}
        readiness={readiness_dto(@current_mission, @ready_routes, @readiness_findings)}
        busy={busy_dto(@reservation_busy)}
        contact_records={@streams.contact_records}
        opportunities={@streams.opportunities}
        provider_reservations={@streams.provider_reservations}
        v-on:validate={JS.push("validate")}
        v-on:search={JS.push("search")}
        v-on:reserve={JS.push("reserve")}
        v-on:cancel={JS.push("cancel")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto(
         mission,
         contact_record_count,
         opportunity_count,
         reservation_count,
         opportunities_empty?
       ) do
    %{
      id: "ops-contacts-page",
      header: %{
        eyebrow: "Mission operations / contact control",
        title: "Contacts",
        description:
          "Inspect scheduled and realized mission contacts, then plan provider capacity without mixing contact state into telemetry charts.",
        scope: %{label: "Scope", value: "Mission contact truth"},
        contact_count: %{
          id: "contact-record-count",
          label: "Contacts",
          value: contact_record_count
        },
        reservation_count: %{
          id: "provider-reservation-count",
          label: "Reservations",
          value: reservation_count
        }
      },
      contact_ledger: %{
        id: "mission-contact-ledger",
        eyebrow: "Canonical contact ledger",
        title: "Scheduled and realized mission contacts",
        description:
          "Open a record for lifecycle evidence or hand its exact window to Telemetry Explore.",
        timeline_action: %{
          id: "contacts-open-timeline",
          label: "Mission Timeline",
          icon: "hero-clock",
          href: ~p"/missions/#{mission.mission_id}/ops/timeline?#{%{category: "operations"}}"
        },
        rows_id: "contact-records",
        empty: %{
          id: "contact-records-empty",
          icon: "hero-signal-slash",
          copy: "No scheduled or realized contacts for this mission.",
          visible: contact_record_count == 0
        }
      },
      opportunity_search: %{
        eyebrow: "01 / Opportunity search",
        description: "All times are coordinated universal time.",
        icon: "hero-signal"
      },
      opportunities: %{
        eyebrow: "02 / Provider opportunities",
        description: "Select a provider-owned window to create a durable reservation attempt.",
        count: %{id: "contact-opportunity-count", value: opportunity_count},
        rows_id: "contact-opportunities",
        empty: %{
          id: "contact-opportunities-empty",
          icon: "hero-magnifying-glass",
          copy: "Search a UTC window to load provider opportunities.",
          visible: opportunities_empty?
        }
      },
      reservations: %{
        eyebrow: "03 / Reservation ledger",
        description: "Provider truth and Cadence contact state remain visible independently.",
        rows_id: "provider-reservations",
        empty: %{
          id: "provider-reservations-empty",
          icon: "hero-calendar-days",
          copy: "No provider reservations for this mission.",
          visible: reservation_count == 0
        }
      }
    }
  end

  defp search_dto(search_form, spacecraft, ready_routes, searching?, search_error) do
    values =
      Map.take(search_form.params, ["spacecraft_id", "route_key", "starts_at", "ends_at"])

    %{
      id: "contact-opportunity-search-form",
      values: values,
      fields: %{
        spacecraft:
          select_field_dto(
            "contact-spacecraft",
            "contact_search[spacecraft_id]",
            "Spacecraft",
            spacecraft_options(spacecraft)
          ),
        route:
          select_field_dto(
            "contact-route",
            "contact_search[route_key]",
            "Downlink route / provider",
            route_options(ready_routes)
          ),
        starts_at:
          datetime_field_dto(
            "contact-window-start",
            "contact_search[starts_at]",
            "Window starts (UTC)"
          ),
        ends_at:
          datetime_field_dto(
            "contact-window-end",
            "contact_search[ends_at]",
            "Window ends (UTC)"
          )
      },
      submit: %{
        id: "search-contact-opportunities",
        label: if(searching?, do: "Searching provider", else: "Search opportunities"),
        busy: searching?,
        disabled: searching? or ready_routes == []
      },
      error:
        if(search_error,
          do: %{id: "contact-search-error", message: search_error},
          else: nil
        )
    }
  end

  defp select_field_dto(id, name, label, options) do
    %{
      id: id,
      name: name,
      type: "select",
      label: label,
      options:
        Enum.map(options, fn {option_label, value} -> %{label: option_label, value: value} end)
    }
  end

  defp datetime_field_dto(id, name, label) do
    %{id: id, name: name, type: "datetime-local", label: label}
  end

  defp readiness_dto(_mission, ready_routes, _findings) when ready_routes != [], do: nil

  defp readiness_dto(mission, _ready_routes, findings) do
    %{
      id: "contact-readiness-empty",
      title: "No provider-ready downlink route",
      findings: Enum.map(findings, &%{message: &1.message}),
      action: %{
        label: "Review Comms routing",
        icon: "hero-arrow-right",
        href: ~p"/missions/#{mission.mission_id}/comms/routing"
      }
    }
  end

  defp busy_dto(reservation_busy) do
    keys = reservation_busy |> MapSet.to_list() |> Enum.sort()

    %{
      keys: keys,
      actions: Map.new(keys, &{&1, %{busy: true, disabled: true}})
    }
  end

  defp contact_record_dto(row, mission_id) do
    canonical_id = row.canonical_id
    realized? = not is_nil(row.realized_contact)
    state = to_string(row.lifecycle_state)

    %{
      "__dom_id" => "contact-record-#{canonical_id}",
      "id" => canonical_id,
      "kind" => if(realized?, do: "realized", else: "scheduled"),
      "state" => state,
      "status" => %{
        "label" => state,
        "class" => reservation_status_class(row.lifecycle_state)
      },
      "record_kind_label" => if(realized?, do: "Realized contact", else: "Scheduled contact"),
      "window" => %{
        "starts_at" => format_time(row.starts_at),
        "ends_at" => format_time(row.ends_at)
      },
      "intent" => contact_intents(row.contact_intents),
      "source_endpoints" => source_endpoints(row.source_endpoint_refs),
      "inspect_action" => %{
        "id" => "open-contact-record-#{canonical_id}",
        "label" => "Inspect",
        "icon" => "hero-arrow-right",
        "href" => ~p"/missions/#{mission_id}/ops/contacts/records/#{canonical_id}"
      },
      "telemetry_handoff" => %{
        "owner" => "contact_record_detail",
        "window_available" =>
          match?(%DateTime{}, row.starts_at) and match?(%DateTime{}, row.ends_at)
      }
    }
  end

  defp opportunity_dto(opportunity) do
    id = opportunity["id"]

    %{
      "__dom_id" => "opportunity-#{id}",
      "id" => id,
      "provider" => opportunity["provider_display_name"] || "Ground station provider",
      "window" => %{
        "starts_at" => format_time(opportunity["starts_at"]),
        "ends_at" => format_time(opportunity["ends_at"])
      },
      "service_summary" =>
        "#{opportunity["service_display_name"] || opportunity["service_profile_ref"]} · #{opportunity["delivery_operator_summary"] || opportunity["delivery_display_name"]}",
      "delivery" => opportunity["delivery_display_name"] || "Provider managed",
      "antenna" => opportunity["antenna_or_service_pool_ref"] || "Provider assigned",
      "cost" => opportunity_cost(opportunity),
      "reserve_action" => %{
        "id" => "reserve-opportunity-#{id}",
        "label" => "Reserve",
        "busy_label" => "Reserving",
        "busy" => false,
        "disabled" => false,
        "payload" => %{"token" => opportunity["booking_token"]}
      }
    }
  end

  defp opportunity_cost(opportunity) do
    case get_in(opportunity, ["extensions", "cost"]) do
      value when is_number(value) or is_binary(value) -> value
      _missing_or_complex -> nil
    end
  end

  defp reservation_dto(row, mission_id, admin?) do
    reservation = row.reservation
    id = reservation.provider_reservation_id
    state = reservation.lifecycle_state

    %{
      "__dom_id" => "provider-reservation-#{id}",
      "id" => id,
      "state" => to_string(state),
      "status" => %{
        "label" => to_string(state),
        "class" => reservation_status_class(state)
      },
      "provider_status" => reservation.provider_status || "awaiting provider",
      "window" => %{
        "starts_at" => format_time(reservation.starts_at),
        "ends_at" => format_time(reservation.ends_at)
      },
      "cancel_action" => cancel_action_dto(id, state, admin?),
      "detail_action" => %{
        "id" => "open-reservation-#{id}",
        "label" => "Open provider reservation",
        "icon" => "hero-arrow-right",
        "href" => ~p"/missions/#{mission_id}/ops/contacts/#{id}"
      },
      "observations" => [
        observation_dto(
          "reservation-contact-status-#{id}",
          "Contact",
          reservation.provider_status || reservation.lifecycle_state
        ),
        observation_dto("reservation-pass-phase-#{id}", "Pass", reservation.pass_phase),
        observation_dto(
          "reservation-delivery-status-#{id}",
          "Delivery",
          reservation.delivery_state
        )
      ],
      "provider" => %{
        "id" => "reservation-provider-#{id}",
        "label" => "Provider",
        "display" => reservation.metadata["provider_display_name"] || reservation.provider_id,
        "version" => reservation.provider_version
      },
      "transport" => %{
        "id" => "reservation-transport-#{id}",
        "label" => "Transport",
        "display" => reservation.metadata["transport_display_name"] || reservation.transport_id,
        "version" => reservation.transport_version
      },
      "service" => %{
        "id" => "reservation-service-#{id}",
        "label" => "Service",
        "display" =>
          reservation.metadata["service_display_name"] ||
            reference_value(reservation.service_profile_ref, "id"),
        "version" => reference_value(reservation.service_profile_ref, "version")
      },
      "delivery" => %{
        "id" => "reservation-delivery-#{id}",
        "label" => "Delivery",
        "display" =>
          reservation.metadata["delivery_operator_summary"] ||
            reservation.metadata["delivery_display_name"] ||
            reference_value(reservation.delivery_profile_ref, "id"),
        "version" => reference_value(reservation.delivery_profile_ref, "version")
      },
      "uncertain" => state in [:unknown, :canceling],
      "configuration_failure" => configuration_failure?(reservation),
      "diagnostics" => diagnostics_dto(row, admin?)
    }
  end

  defp cancel_action_dto(id, state, true)
       when state in [:pending, :confirmed, :active, :unknown] do
    %{
      "id" => "cancel-reservation-#{id}",
      "label" => "Cancel",
      "confirm" => "Cancel this provider reservation?",
      "busy" => false,
      "disabled" => false,
      "payload" => %{"reservation-id" => id}
    }
  end

  defp cancel_action_dto(_id, _state, _admin?), do: nil

  defp observation_dto(id, label, value) do
    %{"id" => id, "label" => label, "value" => json_display_value(value)}
  end

  defp diagnostics_dto(_row, false), do: nil

  defp diagnostics_dto(row, true) do
    reservation = row.reservation

    %{
      "id" => "reservation-diagnostics-#{reservation.provider_reservation_id}",
      "title" => "Administrator diagnostics",
      "rows" => [
        %{
          "label" => "Provider contact",
          "value" => reservation.provider_contact_ref || "not assigned"
        },
        %{"label" => "Cadence contact", "value" => contact_state(row.scheduled_contact)},
        %{
          "label" => "Transport ref",
          "value" => "#{reservation.transport_id}:v#{reservation.transport_version}"
        },
        %{
          "label" => "Descriptor",
          "value" => descriptor_state(reservation.delivery_descriptor_document)
        }
      ]
    }
  end

  defp reference_value(reference, key) when is_map(reference), do: reference[key]
  defp reference_value(_reference, _key), do: nil

  defp json_display_value(value) when is_atom(value), do: Atom.to_string(value)

  defp json_display_value(value) when is_binary(value) or is_number(value) or is_nil(value),
    do: value

  defp json_display_value(value), do: to_string(value)

  defp reservation_status_class(state) when state in [:confirmed, :active, :completed],
    do:
      "inline-flex items-center rounded-sm border px-2 py-0.5 font-mono text-[0.62rem] font-bold uppercase tracking-wider border-success/40 bg-success/10 text-success"

  defp reservation_status_class(state) when state in [:rejected, :failed, :canceled],
    do:
      "inline-flex items-center rounded-sm border px-2 py-0.5 font-mono text-[0.62rem] font-bold uppercase tracking-wider border-error/40 bg-error/10 text-error"

  defp reservation_status_class(state) when state in [:unknown, :canceling],
    do:
      "inline-flex items-center rounded-sm border px-2 py-0.5 font-mono text-[0.62rem] font-bold uppercase tracking-wider border-warning/40 bg-warning/10 text-warning"

  defp reservation_status_class(_state),
    do:
      "inline-flex items-center rounded-sm border px-2 py-0.5 font-mono text-[0.62rem] font-bold uppercase tracking-wider border-info/40 bg-info/10 text-info"

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

  defp contact_intents(intents) do
    Enum.map_join(intents, " · ", fn value ->
      value |> to_string() |> String.replace("_", " ")
    end)
  end

  defp source_endpoints([]), do: "No source endpoint"
  defp source_endpoints(refs), do: Enum.join(refs, " · ")

  defp assign_route_context(socket, spacecraft_id, params) do
    %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns

    readiness =
      if spacecraft_id == "" do
        %{routes: [], findings: []}
      else
        case LiveDeps.list_ready_routes(
               live_deps,
               scope.organization_id,
               mission.mission_id,
               spacecraft_id
             ) do
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

    opportunity
    |> Map.put("provider_display_name", route.provider_display_name)
    |> Map.put("service_display_name", route.service_display_name)
    |> Map.put("delivery_display_name", route.delivery_display_name)
    |> Map.put("delivery_operator_summary", route.delivery_operator_summary)
    |> Map.put("transport_display_name", route.transport_display_name)
    |> Map.put("booking_token", OpportunityToken.sign(payload))
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
    %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns

    LiveDeps.resolve_ready_route(
      live_deps,
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
      "provider_id" => route.provider_id,
      "provider_version" => route.provider_version,
      "transport_id" => route.transport_id,
      "transport_version" => route.transport_version,
      "provider_profile_id" => route.provider_profile_id,
      "provider_profile_version" => route.provider_profile_version,
      "routing_rule_id" => route.routing_rule_id,
      "path_template_id" => route.path_template_id,
      "path_template_version" => route.path_template_version,
      "source_endpoint_id" => route.source_endpoint_id,
      "provider_spacecraft_ref" => route.provider_spacecraft_ref,
      "service_profile_ref" => route.service_profile_ref,
      "delivery_profile_ref" => route.delivery_profile_ref
    }
  end

  defp reservation_attrs(payload, route) do
    opportunity = payload["opportunity"]
    stable_suffix = stable_booking_suffix(payload)

    opportunity
    |> Map.take([
      "id",
      "ground_station_ref",
      "antenna_or_service_pool_ref",
      "starts_at",
      "ends_at"
    ])
    |> Map.put("opportunity_ref", opportunity["id"])
    |> Map.put("provider_reservation_id", "provider_reservation_#{stable_suffix}")
    |> Map.put("scheduled_contact_id", "scheduled_contact_#{stable_suffix}")
    |> Map.put("idempotency_key", "cadence:contact:#{stable_suffix}")
    |> Map.put("provider_version", route.provider_version)
    |> Map.put("transport_id", route.transport_id)
    |> Map.put("transport_version", route.transport_version)
    |> Map.put("service_profile_ref", route.service_profile_ref)
    |> Map.put("delivery_profile_ref", route.delivery_profile_ref)
    |> Map.put("provider_profile_id", route.provider_profile_id)
    |> Map.put("provider_profile_version", route.provider_profile_version)
    |> Map.put("routing_rule_id", route.routing_rule_id)
    |> Map.put("transport_display_name", route.transport_display_name)
    |> Map.put("service_display_name", route.service_display_name)
    |> Map.put("delivery_display_name", route.delivery_display_name)
    |> Map.put("delivery_operator_summary", route.delivery_operator_summary)
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
    %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns

    rows =
      LiveDeps.list_reservation_rows(live_deps, scope.organization_id, mission.mission_id)

    reservation_rows =
      Enum.map(rows, &reservation_dto(&1, mission.mission_id, socket.assigns.admin?))

    socket =
      socket
      |> refresh_contact_records()
      |> assign(:reservation_count, length(rows))
      |> stream(:provider_reservations, reservation_rows, reset: true)

    if connected?(socket) and
         Enum.any?(rows, &(&1.reservation.lifecycle_state in @nonterminal_states)) do
      schedule_reservation_refresh(socket)
    else
      socket
    end
  end

  defp refresh_contact_records(socket) do
    %{current_scope: scope, current_mission: mission, live_deps: live_deps} = socket.assigns

    rows = LiveDeps.list_contact_records(live_deps, scope.organization_id, mission.mission_id)

    contact_rows = Enum.map(rows, &contact_record_dto(&1, mission.mission_id))

    socket
    |> assign(:contact_record_count, length(rows))
    |> stream(:contact_records, contact_rows, reset: true)
  end

  defp schedule_reservation_refresh(%{assigns: %{refresh_timer: nil}} = socket) do
    timer =
      Process.send_after(
        self(),
        :refresh_provider_reservations,
        LiveDeps.refresh_interval_ms(socket.assigns.live_deps)
      )

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
      {"#{route.provider_display_name} / #{route.delivery_operator_summary} / #{route.route_display_name}",
       route.route_key}
    end)
  end

  defp resolve_live_deps(socket) do
    case Phoenix.LiveView.get_connect_params(socket) do
      %{ops_contact_schedule_live_deps: %LiveDeps{} = live_deps} -> live_deps
      _default -> LiveDeps.from_config()
    end
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

  defp organization_admin?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end
end
