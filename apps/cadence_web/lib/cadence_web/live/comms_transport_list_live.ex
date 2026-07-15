defmodule CadenceWeb.CommsTransportListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportKind
  alias CadenceWeb.ListParams

  # Search/sort/paginate happen in memory: TransportStore dedupes latest
  # versions in Elixir, and transports number in the tens per mission.
  # Move to DB-side paging (the list_spacecraft_page pattern) only if
  # transports ever stop fitting comfortably in one query.
  @page_size 50
  @sortable ~w(display_name)

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    transports = Cadence.list_transports(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Transports")
     |> assign(:nav_item, :comms_transports)
     |> assign(:transports, transports)
     |> assign(:transport_count, length(transports))
     |> assign(:transports_empty?, transports == [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    list = ListParams.parse(params, sortable: @sortable, default_sort: "display_name")
    {visible, total} = filter_transports(socket.assigns.transports, list)

    {:noreply,
     socket
     |> assign(:list, list)
     |> assign(:filtered_count, total)
     |> stream(:transports, visible, reset: true, dom_id: &"transport-#{&1.transport_id}")}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, patch_list(socket, %{socket.assigns.list | q: q, page: 1})}
  end

  @impl true
  def handle_event("sort", %{"sort" => key}, socket) when key in @sortable do
    {:noreply, patch_list(socket, ListParams.toggle_sort(socket.assigns.list, key))}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    list = %{socket.assigns.list | page: ListParams.parse(%{"page" => page}, sortable: []).page}
    {:noreply, patch_list(socket, list)}
  end

  defp patch_list(socket, list) do
    mission_id = socket.assigns.current_mission.mission_id
    query = ListParams.to_query(list)
    push_patch(socket, to: ~p"/missions/#{mission_id}/comms/transports?#{query}")
  end

  defp filter_transports(transports, %ListParams{} = list) do
    matching =
      transports
      |> Enum.filter(&matches_query?(&1, list.q))
      |> Enum.sort_by(&String.downcase(&1.display_name), list.dir)

    last_page = max(ceil(length(matching) / @page_size), 1)
    page = min(list.page, last_page)
    visible = Enum.slice(matching, (page - 1) * @page_size, @page_size)
    {visible, length(matching)}
  end

  defp matches_query?(_transport, nil), do: true

  defp matches_query?(transport, q) do
    String.contains?(String.downcase(transport.display_name), String.downcase(q))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-transports-page" class="space-y-6">
      <.page_header
        title="Transports"
        subtitle="Durable byte-moving capabilities Cadence can use for inbound, outbound, or bidirectional spacecraft traffic."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Transports", nil}
        ]}
      >
        <:title_suffix>{@transport_count} configured</:title_suffix>
        <:actions>
          <.button
            id="new-transport-link"
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New Transport
          </.button>
        </:actions>
      </.page_header>

      <%= if @transports_empty? do %>
        <.empty_state
          title="No transports"
          description="Create a transport to describe an external capability for moving bytes."
          action_label="Create the first transport"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
        />
      <% else %>
        <.card padding={:none}>
          <.toolbar id="transports-toolbar" search={@list.q} placeholder="Search transports" />
          <.table
            id="transports-table"
            body_id="transports"
            rows={@streams.transports}
            sort_by={@list.sort}
            sort_dir={@list.dir}
          >
            <:col :let={transport} label="Name" sort="display_name" class="font-medium">
              <.link
                navigate={
                  ~p"/missions/#{@current_mission.mission_id}/comms/transports/#{transport.transport_id}"
                }
                class="text-primary hover:underline"
              >
                {transport.display_name}
              </.link>
            </:col>
            <:col :let={transport} label="Origin">
              <span id={"transport-origin-#{transport.transport_id}"} class="font-mono text-xs uppercase">
                {origin_label(transport.origin)}
              </span>
            </:col>
            <:col :let={transport} label="Provider">
              <span id={"transport-provider-#{transport.transport_id}"}>
                {provider_label(transport)}
              </span>
            </:col>
            <:col :let={transport} label="Delivery">
              <div id={"transport-operator-summary-#{transport.transport_id}"}>
                {operator_summary(transport)}
              </div>
              <div class="mt-1 font-mono text-xs text-base-content/50">
                {transport_summary(transport).endpoint}
              </div>
            </:col>
            <:col :let={transport} label="Readiness">
              <.status_badge
                status={readiness_status(transport)}
                label={readiness_label(transport)}
                id={"transport-readiness-#{transport.transport_id}"}
              />
            </:col>
            <:col :let={transport} label="Version" mono class="text-base-content/70">
              v{transport.version}
            </:col>
          </.table>
          <p :if={@filtered_count == 0} class="py-6 text-center text-sm text-base-content/70">
            No transports match the current search.
          </p>
          <.pagination
            id="transports-pagination"
            page={@list.page}
            page_size={50}
            total_count={@filtered_count}
          />
        </.card>
      <% end %>
    </div>
    """
  end

  defp transport_summary(transport) do
    {:ok, entry} = TransportKind.fetch(transport.transport_kind)
    entry.module.display_summary(transport.configuration)
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end

  defp origin_label(:provider_managed), do: "Provider managed"
  defp origin_label(:direct), do: "Direct"

  defp provider_label(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["provider", "display_name"]) ||
      transport.mission_provider_id
  end

  defp provider_label(_transport), do: "Cadence"

  defp operator_summary(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["delivery_profile", "operator_summary"]) ||
      "Provider-managed delivery"
  end

  defp operator_summary(transport), do: "Direct #{human_atom(transport.transport_kind)}"

  defp readiness_status(%{origin: :provider_managed} = transport) do
    if get_in(transport.provider_configuration_snapshot, ["delivery_profile", "state"]) == "ready",
      do: :ready,
      else: :attention
  end

  defp readiness_status(_transport), do: :info

  defp readiness_label(%{origin: :provider_managed} = transport) do
    if readiness_status(transport) == :ready, do: "Ready", else: "Profile drift"
  end

  defp readiness_label(_transport), do: "Configured"
end
