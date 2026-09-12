defmodule Cadence.Reads.ActivationApprovals do
  @moduledoc "Authorized, host-owned inbox for governed activation approvals."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Management.Activations
  alias Cadence.Missions

  def load(scope, mission_id) do
    with :ok <- Activations.authorize_review(scope, mission_id),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, requests} <-
           Activations.list(scope, mission_id, state: :approval_pending, limit: 100) do
      JSONBoundary.safe(presentation(requests))
    end
  end

  def presentation(requests),
    do: %{
      "page" => %{
        "id" => "activation-approval-inbox",
        "heading" => "Activation approvals",
        "subtitle" => "Review governed mission changes before Control applies them to runtime.",
        "list" => %{
          "card_id" => "activation-approval-list",
          "id" => "activation-requests",
          "empty" => %{
            "id" => "activation-requests-empty",
            "copy" => "No activation requests are waiting for approval."
          }
        }
      },
      "selected" => nil,
      "form" => %{
        "panel_id" => "activation-decision-panel",
        "id" => "activation-decision-form",
        "request_id" => %{
          "id" => "activation_decision_request_id",
          "name" => "activation_decision[request_id]",
          "type" => "hidden",
          "value" => ""
        },
        "reason" => %{
          "id" => "activation_decision_reason",
          "name" => "activation_decision[reason]",
          "type" => "textarea",
          "label" => "Decision rationale",
          "required" => true,
          "value" => ""
        },
        "actions" => %{
          "reject" => %{
            "id" => "reject-activation-request",
            "name" => "decision",
            "value" => "rejected",
            "label" => "Reject"
          },
          "approve" => %{
            "id" => "approve-activation-request",
            "name" => "decision",
            "value" => "approved",
            "label" => "Approve and apply"
          }
        }
      },
      "activation_requests" => Enum.map(requests, &request/1)
    }

  defp request(request) do
    %{
      "__dom_id" => "activation-request-" <> request.activation_request_id,
      "activation_request_id" => request.activation_request_id,
      "binding_set_id" => request.binding_set_id,
      "binding_set_version" => request.binding_set_version,
      "status" => %{"label" => "Approval pending"},
      "requester_display" => requester_display(request),
      "review" => %{"id" => "review-" <> request.activation_request_id, "label" => "Review"}
    }
  end

  defp requester_display(request) do
    case request.requester_actor_document["display_name"] do
      name when is_binary(name) and byte_size(name) in 1..255 -> name
      _ -> request.requester_actor_id
    end
  end
end
