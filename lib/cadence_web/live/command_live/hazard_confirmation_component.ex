defmodule CadenceWeb.CommandLive.HazardConfirmationComponent do
  @moduledoc """
  Modal dialog for confirming hazardous command dispatch.

  Displays the hazard description and requires the operator to type
  a confirmation phrase before the command can be executed.
  """

  use CadenceWeb, :live_component

  alias Cadence.Commands

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <span class="text-warning">
          <.icon name="hero-exclamation-triangle" class="size-6 inline" />
          Hazardous Command
        </span>
        <:subtitle>
          This command requires confirmation before execution
        </:subtitle>
      </.header>

      <div class="alert alert-warning my-4">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <div>
          <div class="font-bold">{@command_name}</div>
          <div class="text-sm">{@hazard_description}</div>
        </div>
      </div>

      <.simple_form
        for={@form}
        id="hazard-confirmation-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="confirm"
      >
        <p class="text-sm text-base-content/70 mb-2">
          Type <span class="font-mono font-bold text-warning">CONFIRM</span> to proceed:
        </p>

        <.input
          field={@form[:confirmation]}
          type="text"
          placeholder="Type CONFIRM"
          autocomplete="off"
          phx-debounce="100"
        />

        <div class="text-xs text-base-content/50 mt-2">
          Token expires: {format_expiry(@expires_at)}
        </div>

        <:actions>
          <button
            type="button"
            phx-click="cancel"
            phx-target={@myself}
            class="btn btn-ghost"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="btn btn-warning"
            disabled={not @confirmed}
          >
            <.icon name="hero-bolt" class="size-4" />
            Execute Command
          </button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    form = to_form(%{"confirmation" => ""})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:confirmed, false)}
  end

  @impl true
  def handle_event("validate", %{"confirmation" => confirmation}, socket) do
    confirmed = String.upcase(confirmation) == "CONFIRM"

    {:noreply,
     socket
     |> assign(:confirmed, confirmed)
     |> assign(:form, to_form(%{"confirmation" => confirmation}))}
  end

  def handle_event("confirm", _params, socket) do
    if socket.assigns.confirmed do
      mission_id = socket.assigns.mission_id
      token = socket.assigns.token

      case Commands.confirm_dispatch(mission_id, token) do
        {:ok, command_log_id} ->
          send(self(), {:command_confirmed, command_log_id})
          {:noreply, socket}

        {:error, :token_expired} ->
          send(self(), {:confirmation_error, "Confirmation token expired. Please try again."})
          {:noreply, socket}

        {:error, :invalid_token} ->
          send(self(), {:confirmation_error, "Invalid confirmation token."})
          {:noreply, socket}

        {:error, reason} ->
          send(self(), {:confirmation_error, "Command failed: #{inspect(reason)}"})
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel", _params, socket) do
    send(self(), :confirmation_cancelled)
    {:noreply, socket}
  end

  defp format_expiry(datetime) do
    # Show relative time remaining
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(datetime, now)

    cond do
      diff_seconds <= 0 -> "Expired"
      diff_seconds < 60 -> "#{diff_seconds}s"
      true -> "#{div(diff_seconds, 60)}m #{rem(diff_seconds, 60)}s"
    end
  end
end
