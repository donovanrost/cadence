defmodule CadenceWeb.OpsActivationRequestsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:activation_requests,
       dom_id: &"activation-request-#{&1.activation_request_id}"
     )
     |> assign(:page_title, "Activation approvals")
     |> assign(:ops_nav_item, :activations)
     |> assign(:activation_requests_page, page_dto())
     |> assign(:selected_request, nil)
     |> assign(:decision_form, decision_form_dto())
     |> refresh_requests()}
  end

  @impl true
  def handle_event("review", %{"request-id" => request_id}, socket) do
    request =
      Enum.find(socket.assigns.activation_requests, &(&1.activation_request_id == request_id))

    {:noreply,
     socket
     |> assign(:selected_request, selected_request_dto(request))
     |> assign(:decision_form, decision_form_dto(request_id))}
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
         |> assign(:decision_form, decision_form_dto())
         |> refresh_requests()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not record decision: #{error_text(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="activation-requests-component"
        v-component="FederatedFullPageSurface"
        page={@activation_requests_page}
        selected={@selected_request}
        form={@decision_form}
        activation_requests={@streams.activation_requests}
        v-on:review={JS.push("review")}
        v-on:decide={JS.push("decide")}
        v-ssr={false}
        class="contents"
      />
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
    |> stream(:activation_requests, Enum.map(requests, &request_dto/1), reset: true)
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

  defp page_dto do
    %{
      id: "activation-approval-inbox",
      heading: "Activation approvals",
      subtitle: "Review governed mission changes before Control applies them to runtime.",
      list: %{
        card_id: "activation-approval-list",
        id: "activation-requests",
        empty: %{
          id: "activation-requests-empty",
          copy: "No activation requests are waiting for approval."
        }
      }
    }
  end

  defp selected_request_dto(nil), do: nil

  defp selected_request_dto(request) do
    %{
      activation_request_id: request.activation_request_id,
      binding_set_id: request.binding_set_id,
      binding_set_version: request.binding_set_version
    }
  end

  defp decision_form_dto(request_id \\ "") do
    %{
      panel_id: "activation-decision-panel",
      id: "activation-decision-form",
      request_id: %{
        id: "activation_decision_request_id",
        name: "activation_decision[request_id]",
        type: "hidden",
        value: request_id
      },
      reason: %{
        id: "activation_decision_reason",
        name: "activation_decision[reason]",
        type: "textarea",
        label: "Decision rationale",
        required: true,
        value: ""
      },
      actions: %{
        reject: %{
          id: "reject-activation-request",
          name: "decision",
          value: "rejected",
          label: "Reject"
        },
        approve: %{
          id: "approve-activation-request",
          name: "decision",
          value: "approved",
          label: "Approve and apply"
        }
      }
    }
  end

  defp request_dto(request) do
    %{
      activation_request_id: request.activation_request_id,
      binding_set_id: request.binding_set_id,
      binding_set_version: request.binding_set_version,
      status: %{label: "Pending approval"},
      requester_display:
        request.requester_actor_document["display_name"] || request.requester_actor_id,
      review: %{
        id: "review-activation-#{request.activation_request_id}",
        label: "Review"
      }
    }
  end

  defp decision_message("approved"), do: "Activation approved and applied."
  defp decision_message("rejected"), do: "Activation rejected."

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason), do: inspect(reason)
end
