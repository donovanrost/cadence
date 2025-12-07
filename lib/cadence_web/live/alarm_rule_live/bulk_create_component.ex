defmodule CadenceWeb.AlarmRuleLive.BulkCreateComponent do
  @moduledoc """
  Modal component for bulk creating alarm rules from suggested rules.

  Shows a table of suggested rules with checkboxes, allowing operators to:
  - Select/deselect individual rules
  - Filter by severity (critical/warning/both)
  - Choose rule scope (mission-wide or target-specific)
  - Review and create selected rules in bulk
  """

  use CadenceWeb, :live_component

  alias Cadence.Alarms.RuleSuggester

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Create Suggested Alarm Rules
        <:subtitle>
          Select rules to create for uncovered parameters
        </:subtitle>
      </.header>

      <%= if @loading do %>
        <div class="flex items-center justify-center py-8">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        </div>
      <% else %>
        <%= if @error do %>
          <div class="rounded-md bg-red-50 p-4 mt-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Error Loading Suggestions</h3>
                <p class="mt-1 text-sm text-red-700">
                  {@error}
                </p>
              </div>
            </div>
          </div>
        <% else %>
          <div class="mt-6 space-y-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-4">
                <label class="text-sm font-medium text-zinc-700">Filter by severity:</label>
                <div class="flex gap-2">
                  <button
                    phx-click="filter_severity"
                    phx-target={@myself}
                    phx-value-filter="both"
                    class={[
                      "px-3 py-1 text-sm rounded-full transition-colors",
                      @severity_filter == :both && "bg-zinc-900 text-white",
                      @severity_filter != :both && "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                    ]}
                  >
                    Both
                  </button>
                  <button
                    phx-click="filter_severity"
                    phx-target={@myself}
                    phx-value-filter="critical"
                    class={[
                      "px-3 py-1 text-sm rounded-full transition-colors",
                      @severity_filter == :critical && "bg-red-600 text-white",
                      @severity_filter != :critical && "bg-red-50 text-red-700 hover:bg-red-100"
                    ]}
                  >
                    Critical Only
                  </button>
                  <button
                    phx-click="filter_severity"
                    phx-target={@myself}
                    phx-value-filter="warning"
                    class={[
                      "px-3 py-1 text-sm rounded-full transition-colors",
                      @severity_filter == :warning && "bg-yellow-600 text-white",
                      @severity_filter != :warning &&
                        "bg-yellow-50 text-yellow-700 hover:bg-yellow-100"
                    ]}
                  >
                    Warning Only
                  </button>
                </div>
              </div>

              <div class="flex items-center gap-2">
                <button
                  phx-click="select_all"
                  phx-target={@myself}
                  class="text-sm text-blue-600 hover:text-blue-800"
                >
                  Select All
                </button>
                <span class="text-zinc-300">|</span>
                <button
                  phx-click="select_none"
                  phx-target={@myself}
                  class="text-sm text-blue-600 hover:text-blue-800"
                >
                  Select None
                </button>
              </div>
            </div>
            
    <!-- Rule Scope Selection -->
            <div class="flex items-center gap-4 p-3 bg-zinc-50 rounded-lg border border-zinc-200">
              <span class="text-sm font-medium text-zinc-700">Rule Scope:</span>
              <div class="flex items-center gap-4">
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="rule_scope"
                    value="mission"
                    checked={@rule_scope == :mission}
                    phx-click="set_rule_scope"
                    phx-target={@myself}
                    phx-value-scope="mission"
                    class="text-blue-600 focus:ring-blue-500"
                  />
                  <span class="text-sm text-zinc-700">Mission-wide</span>
                  <span class="text-xs text-zinc-500">(applies to all targets)</span>
                </label>
                <%= if @target_id do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name="rule_scope"
                      value="target"
                      checked={@rule_scope == :target}
                      phx-click="set_rule_scope"
                      phx-target={@myself}
                      phx-value-scope="target"
                      class="text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm text-zinc-700">Target-specific</span>
                    <span class="text-xs text-zinc-500">({@target_identifier})</span>
                  </label>
                <% end %>
              </div>
            </div>

            <div class="overflow-hidden rounded-lg border border-zinc-200 max-h-96 overflow-y-auto">
              <table class="min-w-full divide-y divide-zinc-200">
                <thead class="bg-zinc-50 sticky top-0">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider w-10">
                      <input
                        type="checkbox"
                        checked={all_visible_selected?(@filtered_suggestions, @selected)}
                        phx-click="toggle_all"
                        phx-target={@myself}
                        class="rounded border-zinc-300 text-blue-600 focus:ring-blue-500"
                      />
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Rule Name
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Severity
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Message Preview
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Rationale
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-zinc-100">
                  <%= for suggestion <- @filtered_suggestions do %>
                    <tr class="hover:bg-zinc-50">
                      <td class="px-4 py-2">
                        <input
                          type="checkbox"
                          checked={MapSet.member?(@selected, suggestion.name)}
                          phx-click="toggle_selection"
                          phx-target={@myself}
                          phx-value-name={suggestion.name}
                          class="rounded border-zinc-300 text-blue-600 focus:ring-blue-500"
                        />
                      </td>
                      <td class="px-4 py-2 text-sm font-medium text-zinc-900">
                        {suggestion.name}
                      </td>
                      <td class="px-4 py-2">
                        <span class={[
                          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
                          suggestion.severity == :critical &&
                            "bg-red-50 text-red-700 ring-red-600/20",
                          suggestion.severity == :warning &&
                            "bg-yellow-50 text-yellow-700 ring-yellow-600/20",
                          suggestion.severity == :info && "bg-blue-50 text-blue-700 ring-blue-600/20"
                        ]}>
                          {suggestion.severity}
                        </span>
                      </td>
                      <td
                        class="px-4 py-2 text-sm text-zinc-600 truncate max-w-xs"
                        title={suggestion.message_template}
                      >
                        {truncate(suggestion.message_template, 50)}
                      </td>
                      <td class="px-4 py-2 text-xs text-zinc-500 italic">
                        {suggestion[:rationale] || "-"}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <%= if Enum.empty?(@filtered_suggestions) do %>
              <div class="text-center py-8 text-zinc-500">
                No suggestions match the current filter.
              </div>
            <% end %>

            <div class="flex items-center justify-between pt-4 border-t border-zinc-200">
              <span class="text-sm text-zinc-600">
                {MapSet.size(@selected)} of {length(@filtered_suggestions)} rules selected
              </span>
              <div class="flex gap-3">
                <.button
                  phx-click="cancel"
                  phx-target={@myself}
                  type="button"
                  class="bg-white text-zinc-700 border border-zinc-300 hover:bg-zinc-50"
                >
                  Cancel
                </.button>
                <.button
                  phx-click="create_rules"
                  phx-target={@myself}
                  phx-disable-with="Creating..."
                  disabled={MapSet.size(@selected) == 0}
                >
                  Create {MapSet.size(@selected)} {ngettext("Rule", "Rules", MapSet.size(@selected))}
                </.button>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(%{mission: mission, definition_set_id: definition_set_id} = assigns, socket) do
    # Only fetch suggestions on initial mount or when parameters change
    parameters = Map.get(assigns, :parameters, nil)
    target_id = Map.get(assigns, :target_id)

    # Look up target identifier if target_id is provided
    target_identifier = if target_id, do: get_target_identifier(target_id), else: nil

    # Default rule scope: target-specific if target_id provided, else mission-wide
    default_rule_scope = if target_id, do: :target, else: :mission

    socket =
      socket
      |> assign(assigns)
      |> assign(:severity_filter, :both)
      |> assign(:parameters, parameters)
      |> assign(:definition_set_id, definition_set_id)
      |> assign(:target_id, target_id)
      |> assign(:target_identifier, target_identifier)
      |> assign(:rule_scope, default_rule_scope)
      |> load_suggestions(definition_set_id, mission.id, parameters, target_id)

    {:ok, socket}
  end

  def update(%{mission: _mission} = assigns, socket) do
    # No definition_set_id - show error
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:loading, false)
     |> assign(:error, "No active database. Publish a telemetry database first.")
     |> assign(:suggestions, [])
     |> assign(:filtered_suggestions, [])
     |> assign(:selected, MapSet.new())
     |> assign(:target_id, nil)
     |> assign(:target_identifier, nil)
     |> assign(:rule_scope, :mission)}
  end

  defp get_target_identifier(target_id) do
    case Cadence.Repo.get(Cadence.Targets.Target, target_id) do
      nil -> nil
      target -> target.identifier
    end
  end

  @impl true
  def handle_event("filter_severity", %{"filter" => filter}, socket) do
    severity_filter = String.to_existing_atom(filter)
    filtered = filter_by_severity(socket.assigns.suggestions, severity_filter)

    # Keep only selections that are still visible
    new_selected =
      Enum.filter(socket.assigns.selected, fn name ->
        Enum.any?(filtered, &(&1.name == name))
      end)
      |> MapSet.new()

    {:noreply,
     socket
     |> assign(:severity_filter, severity_filter)
     |> assign(:filtered_suggestions, filtered)
     |> assign(:selected, new_selected)}
  end

  def handle_event("toggle_selection", %{"name" => name}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, name) do
        MapSet.delete(socket.assigns.selected, name)
      else
        MapSet.put(socket.assigns.selected, name)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    visible_names = Enum.map(socket.assigns.filtered_suggestions, & &1.name) |> MapSet.new()

    selected =
      if all_visible_selected?(socket.assigns.filtered_suggestions, socket.assigns.selected) do
        MapSet.difference(socket.assigns.selected, visible_names)
      else
        MapSet.union(socket.assigns.selected, visible_names)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_all", _params, socket) do
    visible_names = Enum.map(socket.assigns.filtered_suggestions, & &1.name) |> MapSet.new()
    {:noreply, assign(socket, :selected, MapSet.union(socket.assigns.selected, visible_names))}
  end

  def handle_event("select_none", _params, socket) do
    visible_names = Enum.map(socket.assigns.filtered_suggestions, & &1.name) |> MapSet.new()

    {:noreply,
     assign(socket, :selected, MapSet.difference(socket.assigns.selected, visible_names))}
  end

  def handle_event("cancel", _params, socket) do
    send(self(), {__MODULE__, :cancelled})
    {:noreply, socket}
  end

  def handle_event("set_rule_scope", %{"scope" => scope}, socket) do
    rule_scope = String.to_existing_atom(scope)
    {:noreply, assign(socket, :rule_scope, rule_scope)}
  end

  def handle_event("create_rules", _params, socket) do
    selected_names = socket.assigns.selected

    # Find the parameters for selected suggestions
    selected_params =
      socket.assigns.suggestions
      |> Enum.filter(&MapSet.member?(selected_names, &1.name))
      |> Enum.map(& &1.parameter.qualified_name)
      |> Enum.uniq()

    # Determine severity filter if not "both"
    severity_filter =
      case socket.assigns.severity_filter do
        :both -> nil
        other -> [other]
      end

    # Determine target_id based on rule scope
    target_id = if socket.assigns.rule_scope == :target, do: socket.assigns.target_id

    opts = [parameters: selected_params]

    opts =
      if severity_filter, do: Keyword.put(opts, :severity_filter, severity_filter), else: opts

    opts = if target_id, do: Keyword.put(opts, :target_id, target_id), else: opts

    definition_set_id = socket.assigns.definition_set_id

    case RuleSuggester.create_suggested_rules(definition_set_id, socket.assigns.mission.id, opts) do
      {:ok, created_rules} ->
        send(self(), {__MODULE__, {:created, created_rules}})
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to create rules: #{inspect(reason)}")}
    end
  end

  defp load_suggestions(socket, definition_set_id, mission_id, parameters, target_id) do
    opts = if parameters, do: [parameters: parameters], else: []
    opts = if target_id, do: Keyword.put(opts, :target_id, target_id), else: opts

    case RuleSuggester.suggest(definition_set_id, mission_id, opts) do
      {:ok, suggestions} ->
        # Select all by default
        selected = Enum.map(suggestions, & &1.name) |> MapSet.new()

        socket
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> assign(:suggestions, suggestions)
        |> assign(:filtered_suggestions, suggestions)
        |> assign(:selected, selected)

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, "Failed to load suggestions: #{inspect(reason)}")
        |> assign(:suggestions, [])
        |> assign(:filtered_suggestions, [])
        |> assign(:selected, MapSet.new())
    end
  end

  defp filter_by_severity(suggestions, :both), do: suggestions

  defp filter_by_severity(suggestions, severity),
    do: Enum.filter(suggestions, &(&1.severity == severity))

  defp all_visible_selected?(filtered, selected) do
    visible_names = Enum.map(filtered, & &1.name) |> MapSet.new()
    not Enum.empty?(filtered) and MapSet.subset?(visible_names, selected)
  end

  defp truncate(string, max_length) when byte_size(string) <= max_length, do: string
  defp truncate(string, max_length), do: String.slice(string, 0, max_length) <> "..."
end
