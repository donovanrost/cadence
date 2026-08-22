defmodule CadenceWeb.OpsActivationRequestsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations, as: ManagementActivations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:activation_requests,
       dom_id: &"activation-request-#{&1.activation_request_id}"
     )
     |> assign(:page_title, "Activation approvals")
     |> assign(:ops_nav_item, :activations)
     |> assign(:selected_request, nil)
     |> assign(:decision_form, decision_form())
     |> refresh_requests()}
  end

  @impl true
  def handle_event("review", %{"request-id" => request_id}, socket) do
    request =
      Enum.find(socket.assigns.activation_requests, &(&1.activation_request_id == request_id))

    {:noreply,
     socket
     |> assign(:selected_request, request)
     |> assign(:decision_form, decision_form(request_id))}
  end

  def handle_event(
        "decide",
        %{
          "activation_decision" => %{"request_id" => request_id, "reason" => reason},
          "decision" => decision
        },
        socket
      ) do
    result = decide(socket, request_id, reason, decision)

    case result do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, decision_message(decision))
         |> assign(:selected_request, nil)
         |> assign(:decision_form, decision_form())
         |> refresh_requests()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not record decision: #{error_text(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="activation-approval-inbox" class="space-y-4">
        <.page_header
          title="Activation approvals"
          subtitle="Review governed mission changes before Control applies them to runtime."
        />

        <.card id="activation-approval-list">
          <div id="activation-requests" phx-update="stream" class="divide-y divide-base-300/30">
            <div id="activation-requests-empty" class="hidden only:block py-8 text-center text-sm text-base-content/60">
              No activation requests are waiting for approval.
            </div>
            <div
              :for={{dom_id, request} <- @streams.activation_requests}
              id={dom_id}
              class="flex items-center justify-between gap-4 py-3"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <span class="font-mono text-xs text-base-content/60">
                    {request.binding_set_id}@{request.binding_set_version}
                  </span>
                  <span class="rounded border border-warning/30 bg-warning/10 px-2 py-0.5 text-[0.625rem] font-semibold uppercase tracking-wide text-warning">
                    Pending approval
                  </span>
                </div>
                <p class="mt-1 text-sm text-base-content/70">
                  Requested by {request.requester_actor_document["display_name"] || request.requester_actor_id}
                </p>
              </div>
              <.button
                id={"review-activation-#{request.activation_request_id}"}
                size={:sm}
                variant={:ghost}
                phx-click="review"
                phx-value-request-id={request.activation_request_id}
              >
                Review
              </.button>
            </div>
          </div>
        </.card>

        <.card :if={@selected_request} id="activation-decision-panel">
          <.form for={@decision_form} id="activation-decision-form" phx-submit="decide">
            <.input field={@decision_form[:request_id]} type="hidden" />
            <.input
              field={@decision_form[:reason]}
              type="textarea"
              label="Decision rationale"
              required
            />
            <div class="mt-3 flex justify-end gap-2">
              <.button
                id="reject-activation-request"
                type="submit"
                name="decision"
                value="rejected"
                variant={:ghost}
              >
                Reject
              </.button>
              <.button
                id="approve-activation-request"
                type="submit"
                name="decision"
                value="approved"
              >
                Approve and apply
              </.button>
            </div>
          </.form>
        </.card>
      </section>
    </Layouts.app>
    """
  end

  defp refresh_requests(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    requests =
      case ManagementActivations.list(scope, mission.mission_id,
             state: :approval_pending,
             limit: 100
           ) do
        {:ok, requests} -> requests
        {:error, _reason} -> []
      end

    socket
    |> assign(:activation_requests, requests)
    |> stream(:activation_requests, requests, reset: true)
  end

  defp decide(socket, request_id, reason, "approved") do
    with {:ok, _execution} <-
           ControlActivations.approve_and_execute(
             socket.assigns.current_scope,
             request_id,
             reason
           ) do
      :ok
    end
  end

  defp decide(socket, request_id, reason, "rejected") do
    with {:ok, _request, _decision} <-
           ManagementActivations.reject(socket.assigns.current_scope, request_id, reason) do
      :ok
    end
  end

  defp decide(_socket, _request_id, _reason, _decision), do: {:error, :invalid_decision}

  defp decision_form(request_id \\ "") do
    to_form(%{"request_id" => request_id, "reason" => ""}, as: :activation_decision)
  end

  defp decision_message("approved"), do: "Activation approved and applied."
  defp decision_message("rejected"), do: "Activation rejected."

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason), do: inspect(reason)
end
