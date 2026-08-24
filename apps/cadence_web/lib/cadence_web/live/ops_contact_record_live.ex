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
        lifecycle_state = lifecycle_state(scheduled_contact, realized_contact)

        {:ok,
         socket
         |> assign(:page_title, "Contact #{canonical_id}")
         |> assign(:ops_nav_item, :contacts)
         |> assign(
           :contact_record,
           contact_record_dto(
             mission,
             scheduled_contact,
             realized_contact,
             canonical_id,
             lifecycle_state,
             window_start,
             window_end
           )
         )}

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
      <.vue
        id="ops-contact-record-component"
        v-component="OpsContactRecord"
        record={@contact_record}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp contact_record_dto(
         mission,
         scheduled_contact,
         realized_contact,
         canonical_id,
         lifecycle_state,
         window_start,
         window_end
       ) do
    path_rows = paths(scheduled_contact, realized_contact)
    intents = contact_intents(scheduled_contact, realized_contact)
    sources = source_endpoint_refs(scheduled_contact, realized_contact)

    %{
      id: "ops-contact-record-page",
      header: %{
        title: "Mission contact record",
        canonical_id: canonical_id,
        lifecycle: %{
          label: to_string(lifecycle_state),
          class: state_class(lifecycle_state)
        },
        back: %{
          id: "contact-record-back",
          label: "Contact ledger",
          icon: "hero-arrow-left",
          href: ~p"/missions/#{mission.mission_id}/ops/contacts"
        },
        actions: [
          %{
            id: "contact-record-open-timeline",
            label: "Mission Timeline",
            icon: "hero-clock",
            class: "btn btn-sm btn-ghost",
            href:
              ~p"/missions/#{mission.mission_id}/ops/timeline?#{%{category: "operations", scope_kind: "contact", scope_id: canonical_id}}"
          },
          %{
            id: "contact-record-explore-telemetry",
            label: "Explore this window",
            icon: "hero-chart-bar",
            class: "btn btn-sm btn-primary",
            href:
              ~p"/missions/#{mission.mission_id}/ops/explore?#{explore_query(canonical_id, window_start, window_end)}"
          }
        ]
      },
      window: %{
        id: "contact-operational-window",
        eyebrow: "Operational window",
        title: "Planned and realized timing",
        facts: [
          fact_dto("Planned start", scheduled_time(scheduled_contact, :starts_at)),
          fact_dto("Planned end", scheduled_time(scheduled_contact, :ends_at)),
          fact_dto("Realized start", realized_start(realized_contact)),
          fact_dto("Realized end", realized_end(realized_contact))
        ]
      },
      paths: %{
        id: "contact-paths",
        list_id: "contact-path-list",
        eyebrow: "Data paths",
        title: "Contact transport evidence",
        empty: path_rows == [],
        empty_state: %{
          id: "contact-paths-empty",
          message: "No path evidence is attached to this contact record."
        },
        rows: Enum.map(path_rows, &path_dto/1)
      },
      lineage: %{
        id: "contact-identities",
        eyebrow: "Canonical identity",
        title: "Record lineage",
        fields: [
          lineage_field_dto("Scheduled", scheduled_id(scheduled_contact), "break-all font-mono"),
          lineage_field_dto("Realized", realized_id(realized_contact), "break-all font-mono"),
          lineage_field_dto(
            "Provider ref",
            provider_ref(scheduled_contact),
            "break-all font-mono"
          ),
          lineage_field_dto("Schedule rev", schedule_revision(scheduled_contact), "font-mono"),
          lineage_field_dto("Clock mode", clock_mode(realized_contact), "font-mono")
        ]
      },
      context: %{
        id: "contact-operational-context",
        eyebrow: "Operational context",
        title: "Intent and sources",
        intents: %{
          label: "Contact intents",
          empty: intents == [],
          empty_state: "No declared intent",
          values: Enum.map(intents, &humanize/1)
        },
        sources: %{
          label: "Source endpoints",
          empty: sources == [],
          empty_state: "No source endpoint references",
          values: sources
        }
      }
    }
  end

  defp fact_dto(label, value), do: %{label: label, value: format_value(value)}

  defp path_dto(path) do
    %{
      id: "contact-path-#{path.path_id}",
      path_id: path.path_id,
      source_endpoint_ref: path.source_endpoint_ref || "No source endpoint",
      direction: fact_dto("Direction", path.direction),
      selection: fact_dto("Selection", path.selection_role)
    }
  end

  defp lineage_field_dto(label, value, class) do
    %{label: label, value: to_string(value), class: class}
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
