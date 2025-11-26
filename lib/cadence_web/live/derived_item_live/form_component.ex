defmodule CadenceWeb.DerivedItemLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.Telemetry.Database.DerivedItem
  alias Cadence.Telemetry.Database.DefinitionSet
  alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>
          Derived items are computed values calculated from other telemetry items.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="derived-item-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="e.g., TEMP_AVG" />

        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          placeholder="Optional description of what this derived item calculates"
        />

        <div class="space-y-2">
          <.input
            field={@form[:expression]}
            type="textarea"
            label="Expression"
            placeholder="e.g., (HEALTH.TEMP1 + HEALTH.TEMP2) / 2"
            phx-debounce="300"
            rows="3"
            id="derived_item_expression"
            phx-hook="InsertText"
          />
          <p class="text-xs text-zinc-600">
            Use qualified names: PACKET.ITEM (e.g., HEALTH.battery_voltage, POWER.bus_current).
            Click an item below to insert it.
          </p>

          <div :if={@expression_validation} class="text-sm">
            <%= if @expression_validation.valid do %>
              <div class="flex items-center gap-2 text-green-600">
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Expression is valid
              </div>
            <% else %>
              <div class="flex items-center gap-2 text-red-600">
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
                <%= @expression_validation.error %>
              </div>
            <% end %>
          </div>

          <div :if={@source_items != []} class="mt-2">
            <span class="text-sm font-medium text-zinc-700">Source items: </span>
            <div class="flex flex-wrap gap-1 mt-1">
              <%= for item <- @source_items do %>
                <span class={[
                  "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
                  item_exists?(item, @available_items) && "bg-green-50 text-green-700 ring-green-600/20",
                  !item_exists?(item, @available_items) && "bg-yellow-50 text-yellow-700 ring-yellow-600/20"
                ]}>
                  <%= item %>
                  <span :if={!item_exists?(item, @available_items)} class="ml-1" title="Item not found in active database">
                    ?
                  </span>
                </span>
              <% end %>
            </div>
          </div>

          <details :if={@available_items != []} class="mt-3">
            <summary class="text-sm font-medium text-zinc-700 cursor-pointer hover:text-zinc-900">
              Available items from active database (<%= length(@available_items) %>)
            </summary>
            <div class="mt-2 max-h-48 overflow-y-auto border border-zinc-200 rounded-md p-2 bg-zinc-50">
              <div class="grid grid-cols-2 gap-1 text-xs">
                <%= for item <- @available_items do %>
                  <button
                    type="button"
                    class="text-left px-2 py-1 rounded hover:bg-zinc-200 font-mono truncate"
                    phx-click="insert_item"
                    phx-value-item={item}
                    phx-target={@myself}
                    title={item}
                  >
                    <%= item %>
                  </button>
                <% end %>
              </div>
            </div>
          </details>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:units]}
            type="text"
            label="Units"
            placeholder="e.g., °C, m/s"
          />

          <.input
            field={@form[:data_type]}
            type="select"
            label="Data Type"
            options={[
              {"Float", "float"},
              {"Integer", "int"},
              {"Unsigned Integer", "uint"},
              {"String", "string"},
              {"Boolean", "boolean"}
            ]}
          />
        </div>

        <.input
          field={@form[:enabled]}
          type="checkbox"
          label="Enabled"
        />
        <p class="text-sm text-gray-600 -mt-4 ml-6">
          Disabled items are not computed in the telemetry pipeline.
        </p>

        <:actions>
          <.button phx-disable-with="Saving..." type="submit">
            <%= if @action == :new, do: "Create Derived Item", else: "Save Changes" %>
          </.button>
        </:actions>
      </.simple_form>

      <div :if={@action == :edit} class="mt-8 pt-6 border-t border-zinc-200">
        <.button
          phx-click="delete"
          phx-target={@myself}
          data-confirm="Are you sure you want to delete this derived item?"
          class="bg-red-600 hover:bg-red-700"
        >
          Delete Derived Item
        </.button>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{derived_item: derived_item} = assigns, socket) do
    # Load available items from active DefinitionSet
    available_items = load_available_items(assigns.mission.id)

    # Initial expression validation
    {source_items, expression_validation} =
      if derived_item.expression && derived_item.expression != "" do
        validate_expression(derived_item.expression)
      else
        {[], nil}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:available_items, available_items)
     |> assign(:source_items, source_items)
     |> assign(:expression_validation, expression_validation)
     |> assign_form(DerivedItem.changeset(derived_item, %{}))}
  end

  @impl true
  def handle_event("validate", %{"derived_item" => params}, socket) do
    # Validate expression for live preview
    expression = Map.get(params, "expression", "")

    {source_items, expression_validation} =
      if expression != "" do
        validate_expression(expression)
      else
        {[], nil}
      end

    changeset =
      socket.assigns.derived_item
      |> DerivedItem.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:source_items, source_items)
     |> assign(:expression_validation, expression_validation)
     |> assign_form(changeset)}
  end

  def handle_event("insert_item", %{"item" => item}, socket) do
    # Send event to client-side hook to insert item at cursor position
    {:noreply,
     socket
     |> push_event("insert-text", %{text: item, target: "derived_item_expression"})}
  end

  def handle_event("save", %{"derived_item" => params}, socket) do
    save_derived_item(socket, socket.assigns.action, params)
  end

  def handle_event("delete", _params, socket) do
    case DerivedItem.delete(socket.assigns.derived_item) do
      {:ok, _} ->
        notify_parent({:deleted, socket.assigns.derived_item})

        {:noreply,
         socket
         |> put_flash(:info, "Derived item deleted")
         |> push_patch(to: socket.assigns.patch)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete derived item")}
    end
  end

  defp save_derived_item(socket, :edit, params) do
    case DerivedItem.update(socket.assigns.derived_item, params) do
      {:ok, derived_item} ->
        notify_parent({:saved, derived_item})

        {:noreply,
         socket
         |> put_flash(:info, "Derived item updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_derived_item(socket, :new, params) do
    params =
      params
      |> Map.put("mission_id", socket.assigns.mission.id)
      |> Map.put("organization_id", socket.assigns.mission.organization_id)

    case DerivedItem.create(params) do
      {:ok, derived_item} ->
        notify_parent({:saved, derived_item})

        {:noreply,
         socket
         |> put_flash(:info, "Derived item created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp validate_expression(expression) do
    case ExpressionEvaluator.validate(expression) do
      :ok ->
        case ExpressionEvaluator.extract_variables(expression) do
          {:ok, vars} ->
            {vars, %{valid: true, error: nil}}

          {:error, reason} ->
            {[], %{valid: false, error: "Failed to extract variables: #{inspect(reason)}"}}
        end

      {:error, reason} ->
        {[], %{valid: false, error: format_error(reason)}}
    end
  end

  defp format_error({:syntax_error, details}), do: "Syntax error: #{inspect(details)}"
  defp format_error(reason), do: "Invalid expression: #{inspect(reason)}"

  defp load_available_items(mission_id) do
    case DefinitionSet.load_active_complete(mission_id) do
      {:ok, definition_set} ->
        definition_set.packet_definitions
        |> Enum.flat_map(fn packet ->
          Enum.map(packet.packet_items, fn item ->
            "#{packet.name}.#{item.name}"
          end)
        end)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  defp item_exists?(item_name, available_items) do
    # Check both full qualified (PACKET.ITEM) and short (ITEM) names
    item_name in available_items ||
      Enum.any?(available_items, fn avail ->
        String.ends_with?(avail, ".#{item_name}")
      end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
