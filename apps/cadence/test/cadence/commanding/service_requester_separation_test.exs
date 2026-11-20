defmodule Cadence.Commanding.ServiceRequesterSeparationTest do
  # #280: a command request made through a service identity counts as made by the service's
  # accountable people. Before #280 the check compared user ids only, so a service requester (no
  # user_id) passed it, and so did one with nobody on record (ca-security's fail-open).
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Auth
  alias Cadence.Auth.{ServiceAccountableRow, ServiceIdentity}
  alias Cadence.Commanding.LifecyclePolicy
  alias Cadence.Persistence.JsonDocument
  alias Cadence.ServiceIdentityFixtures

  @org "org-command-service"
  @mission "mission-command-service"

  setup do
    persist_mission_scope(@org, @mission)

    {:ok, %{service_identity: service}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: @org,
          mission_id: @mission,
          display_name: "Pass scripts",
          capabilities: [:mission_admin]
        }),
        ServiceIdentityFixtures.issuer_scope(@org, "issuer-a")
      )

    request = %{
      organization_id: @org,
      command_request_id: "command-request-1",
      requested_by_document:
        JsonDocument.wrap_value(%{
          "actor_kind" => "service",
          "service_identity_id" => service.service_identity_id
        })
    }

    %{service: service, request: request}
  end

  test "the service's issuer can't approve its request; the refusal names the service", c do
    id = c.service.service_identity_id

    assert {:error,
            {:command_request_self_approval_not_allowed, "command-request-1",
             %{via_service: %{id: ^id, name: "Pass scripts"}}}} =
             LifecyclePolicy.ensure_not_self_approval(c.request, %{"user_id" => "issuer-a"})

    assert :ok =
             LifecyclePolicy.ensure_not_self_approval(c.request, %{"user_id" => "someone-else"})
  end

  test "with nobody on record for the service, nobody can approve its request", c do
    Cadence.ServiceIdentityFixtures.forget_accountables!(c.service.service_identity_id)

    id = c.service.service_identity_id

    assert {:error,
            {:command_request_approver_authors_unknown, "command-request-1",
             %{service: %{id: ^id}}}} =
             LifecyclePolicy.ensure_not_self_approval(c.request, %{"user_id" => "someone-else"})
  end

  test "a person requester is refused as before, with no details", c do
    request = %{
      c.request
      | requested_by_document:
          JsonDocument.wrap_value(%{"actor_kind" => "user", "user_id" => "operator-b"})
    }

    assert {:error, {:command_request_self_approval_not_allowed, "command-request-1"}} =
             LifecyclePolicy.ensure_not_self_approval(request, %{"user_id" => "operator-b"})
  end
end
