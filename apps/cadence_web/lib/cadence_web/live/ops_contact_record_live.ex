defmodule CadenceWeb.OpsContactRecordLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Contacts

  @impl true
  def mount(%{"contact_id" => contact_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case fetch_record(scope.organization_id, mission.mission_id, contact_id) do
      {:ok, scheduled_contact, realized_contact} ->
        window_start = contact_start(scheduled_contact, realized_contact)
        window_end = contact_end(scheduled_contact, realized_contact, window_start)
        canonical_id = canonical_id(scheduled_contact, realized_contact)

        {:ok,
         socket
         |> assign(:page_title, "Contact #{canonical_id}")
         |> assign(:ops_nav_item, :contacts)
         |> assign(:canonical_id, canonical_id)
         |> assign(:scheduled_contact, scheduled_contact)
         |> assign(:realized_contact, realized_contact)
         |> assign(:lifecycle_state, lifecycle_state(scheduled_contact, realized_contact))
         |> assign(:window_start, window_start)
         |> assign(:window_end, window_end)
         |> assign(
           :source_endpoint_refs,
           source_endpoint_refs(scheduled_contact, realized_contact)
         )
         |> assign(:contact_intents, contact_intents(scheduled_contact, realized_contact))
         |> assign(:paths, paths(scheduled_contact, realized_contact))
         |> assign(:explore_query, explore_query(canonical_id, window_start, window_end))}

      {:error, :contact_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That contact record is not available in this mission.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/contacts")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="ops-contact-record-page" class="min-h-0 flex-1 overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[90rem] flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div class="min-w-0">
              <.link
                id="contact-record-back"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/contacts"}
                class="inline-flex items-center gap-1 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-primary/70 hover:text-primary"
              >
                <.icon name="hero-arrow-left" class="h-3 w-3" /> Contact ledger
              </.link>
              <div class="mt-3 flex flex-wrap items-center gap-3">
                <h1 class="text-2xl font-bold tracking-tight">Mission contact record</h1>
                <span class={[
                  "border px-2 py-1 font-mono text-[0.65rem] font-bold uppercase tracking-[0.14em]",
                  state_class(@lifecycle_state)
                ]}>
                  {@lifecycle_state}
                </span>
              </div>
              <p id="contact-record-id" class="mt-2 break-all font-mono text-xs text-base-content/50">
                {@canonical_id}
              </p>
            </div>

            <div class="flex flex-wrap gap-2">
              <.link
                id="contact-record-open-timeline"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/timeline?#{%{category: "operations", scope_kind: "contact", scope_id: @canonical_id}}"}
                class="btn btn-sm btn-ghost"
              >
                <.icon name="hero-clock" class="h-4 w-4" /> Mission Timeline
              </.link>
              <.link
                id="contact-record-explore-telemetry"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/explore?#{@explore_query}"}
                class="btn btn-sm btn-primary"
              >
                <.icon name="hero-chart-bar" class="h-4 w-4" /> Explore this window
              </.link>
            </div>
          </div>
        </header>

        <div class="mx-auto grid max-w-[90rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)] lg:p-7">
          <div class="min-w-0 space-y-5">
            <section id="contact-operational-window" class="border border-base-300 bg-base-200/25">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Operational window</p>
                <h2 class="mt-1 text-base font-semibold">Planned and realized timing</h2>
              </div>
              <div class="grid gap-px bg-base-300 sm:grid-cols-2 xl:grid-cols-4">
                <.fact label="Planned start" value={scheduled_time(@scheduled_contact, :starts_at)} />
                <.fact label="Planned end" value={scheduled_time(@scheduled_contact, :ends_at)} />
                <.fact label="Realized start" value={realized_start(@realized_contact)} />
                <.fact label="Realized end" value={realized_end(@realized_contact)} />
              </div>
            </section>

            <section id="contact-paths" class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Data paths</p>
                <h2 class="mt-1 text-base font-semibold">Contact transport evidence</h2>
              </div>
              <div id="contact-path-list" class="divide-y divide-base-300">
                <div :if={@paths == []} id="contact-paths-empty" class="px-4 py-8 text-sm text-base-content/50">
                  No path evidence is attached to this contact record.
                </div>
                <article :for={path <- @paths} id={"contact-path-#{path.path_id}"} class="grid gap-3 px-4 py-4 md:grid-cols-[minmax(12rem,1fr)_9rem_9rem]">
                  <div class="min-w-0">
                    <p class="font-mono text-xs font-semibold">{path.path_id}</p>
                    <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
                      {path.source_endpoint_ref || "No source endpoint"}
                    </p>
                  </div>
                  <.fact_inline label="Direction" value={path.direction} />
                  <.fact_inline label="Selection" value={path.selection_role} />
                </article>
              </div>
            </section>
          </div>

          <aside class="min-w-0 space-y-5">
            <section id="contact-identities" class="border border-base-300 bg-base-200/25">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Canonical identity</p>
                <h2 class="mt-1 text-base font-semibold">Record lineage</h2>
              </div>
              <dl class="grid grid-cols-[8rem_minmax(0,1fr)] gap-x-3 gap-y-3 p-4 text-xs">
                <dt class="text-base-content/45">Scheduled</dt>
                <dd class="break-all font-mono">{scheduled_id(@scheduled_contact)}</dd>
                <dt class="text-base-content/45">Realized</dt>
                <dd class="break-all font-mono">{realized_id(@realized_contact)}</dd>
                <dt class="text-base-content/45">Provider ref</dt>
                <dd class="break-all font-mono">{provider_ref(@scheduled_contact)}</dd>
                <dt class="text-base-content/45">Schedule rev</dt>
                <dd class="font-mono">{schedule_revision(@scheduled_contact)}</dd>
                <dt class="text-base-content/45">Clock mode</dt>
                <dd class="font-mono">{clock_mode(@realized_contact)}</dd>
              </dl>
            </section>

            <section id="contact-operational-context" class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Operational context</p>
                <h2 class="mt-1 text-base font-semibold">Intent and sources</h2>
              </div>
              <div class="space-y-4 p-4 text-xs">
                <div>
                  <p class="hud-label">Contact intents</p>
                  <div class="mt-2 flex flex-wrap gap-1.5">
                    <span :for={intent <- @contact_intents} class="border border-primary/25 bg-primary/5 px-2 py-1 font-mono text-[0.65rem]">
                      {humanize(intent)}
                    </span>
                    <span :if={@contact_intents == []} class="text-base-content/45">No declared intent</span>
                  </div>
                </div>
                <div>
                  <p class="hud-label">Source endpoints</p>
                  <ul class="mt-2 space-y-1.5 font-mono text-[0.68rem] text-base-content/65">
                    <li :for={source_endpoint_ref <- @source_endpoint_refs}>{source_endpoint_ref}</li>
                    <li :if={@source_endpoint_refs == []} class="font-sans text-base-content/45">No source endpoint references</li>
                  </ul>
                </div>
              </div>
            </section>
          </aside>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp fact(assigns) do
    ~H"""
    <div class="bg-base-100 px-4 py-4">
      <p class="hud-label">{@label}</p>
      <p class="mt-2 font-mono text-xs text-base-content/75">{format_value(@value)}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp fact_inline(assigns) do
    ~H"""
    <div>
      <p class="hud-label">{@label}</p>
      <p class="mt-1 font-mono text-xs text-base-content/70">{format_value(@value)}</p>
    </div>
    """
  end

  defp fetch_record(organization_id, mission_id, contact_id) do
    case Contacts.fetch_realized_contact(organization_id, mission_id, contact_id) do
      {:ok, realized_contact} ->
        {:ok, fetch_scheduled(organization_id, mission_id, realized_contact.scheduled_contact_id),
         realized_contact}

      {:error, :realized_contact_not_found} ->
        case Contacts.fetch_scheduled_contact(organization_id, mission_id, contact_id) do
          {:ok, scheduled_contact} ->
            {:ok, scheduled_contact,
             fetch_realized(organization_id, mission_id, scheduled_contact)}

          {:error, :scheduled_contact_not_found} ->
            {:error, :contact_not_found}
        end
    end
  end

  defp fetch_scheduled(_organization_id, _mission_id, nil), do: nil

  defp fetch_scheduled(organization_id, mission_id, scheduled_contact_id) do
    case Contacts.fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id) do
      {:ok, scheduled_contact} -> scheduled_contact
      {:error, :scheduled_contact_not_found} -> nil
    end
  end

  defp fetch_realized(organization_id, mission_id, scheduled_contact) do
    by_reference =
      case scheduled_contact.realized_contact_id do
        realized_contact_id when is_binary(realized_contact_id) ->
          case Contacts.fetch_realized_contact(organization_id, mission_id, realized_contact_id) do
            {:ok, realized_contact} -> realized_contact
            {:error, :realized_contact_not_found} -> nil
          end

        _missing ->
          nil
      end

    by_reference ||
      organization_id
      |> Contacts.list_realized_contacts(mission_id)
      |> Enum.find(&(&1.scheduled_contact_id == scheduled_contact.scheduled_contact_id))
  end

  defp canonical_id(_scheduled_contact, realized_contact) when not is_nil(realized_contact),
    do: realized_contact.realized_contact_id

  defp canonical_id(scheduled_contact, nil), do: scheduled_contact.scheduled_contact_id

  defp lifecycle_state(_scheduled_contact, realized_contact) when not is_nil(realized_contact),
    do: realized_contact.lifecycle_state

  defp lifecycle_state(scheduled_contact, nil), do: scheduled_contact.lifecycle_state

  defp contact_start(scheduled_contact, realized_contact) do
    (realized_contact && (realized_contact.realized_at || realized_contact.initial_time)) ||
      (scheduled_contact && scheduled_contact.starts_at) || DateTime.utc_now()
  end

  defp contact_end(scheduled_contact, realized_contact, window_start) do
    realized_end_datetime(realized_contact) ||
      (scheduled_contact && scheduled_contact.ends_at) ||
      DateTime.add(window_start, 2 * 60 * 60, :second)
  end

  defp source_endpoint_refs(scheduled_contact, realized_contact) do
    ((scheduled_contact && scheduled_contact.source_endpoint_refs) || [])
    |> Kernel.++((realized_contact && realized_contact.source_endpoint_refs) || [])
    |> Enum.uniq()
  end

  defp contact_intents(scheduled_contact, realized_contact) do
    ((scheduled_contact && scheduled_contact.contact_intents) || [])
    |> Kernel.++((realized_contact && realized_contact.contact_intents) || [])
    |> Enum.uniq()
  end

  defp paths(_scheduled_contact, %{paths: paths}) when paths != [], do: paths
  defp paths(%{paths: paths}, _realized_contact), do: paths
  defp paths(_scheduled_contact, _realized_contact), do: []

  defp explore_query(canonical_id, window_start, window_end) do
    %{
      "logical_source" => "telemetry",
      "scope_kind" => "contact",
      "scope_id" => canonical_id,
      "time_mode" => "archive",
      "from" => window_start |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "to" => window_end |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp scheduled_time(nil, _field), do: nil
  defp scheduled_time(scheduled_contact, field), do: Map.get(scheduled_contact, field)
  defp realized_start(nil), do: nil

  defp realized_start(realized_contact),
    do: realized_contact.realized_at || realized_contact.initial_time

  defp realized_end(realized_contact), do: realized_end_datetime(realized_contact)

  defp realized_end_datetime(nil), do: nil

  defp realized_end_datetime(realized_contact) do
    metadata = realized_contact.metadata

    (metadata["completed_at"] || metadata["stopped_at"] || metadata["ended_at"])
    |> parse_datetime()
  end

  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp scheduled_id(nil), do: "Not linked"
  defp scheduled_id(scheduled_contact), do: scheduled_contact.scheduled_contact_id
  defp realized_id(nil), do: "Not realized"
  defp realized_id(realized_contact), do: realized_contact.realized_contact_id
  defp provider_ref(nil), do: "Not linked"
  defp provider_ref(scheduled_contact), do: scheduled_contact.provider_contact_ref || "Not linked"
  defp schedule_revision(nil), do: "—"
  defp schedule_revision(scheduled_contact), do: scheduled_contact.current_revision
  defp clock_mode(nil), do: "Not realized"
  defp clock_mode(realized_contact), do: realized_contact.clock_mode

  defp format_value(nil), do: "Not recorded"
  defp format_value(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%SZ")
  defp format_value(value) when is_atom(value), do: humanize(value)
  defp format_value(value), do: to_string(value)

  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp state_class(state) when state in [:active, :realized, :completed, :stopped],
    do: "border-success/40 bg-success/10 text-success"

  defp state_class(state) when state in [:expired, :canceled],
    do: "border-error/40 bg-error/10 text-error"

  defp state_class(_state), do: "border-info/40 bg-info/10 text-info"
end
