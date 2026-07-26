defmodule Cadence.Applications.ActionDefinitionTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ActionConfirmation,
    ActionDefinition,
    ApplicationDefinition
  }

  test "validates typed domain-action metadata and confirmation copy" do
    action = valid_action()

    assert :ok = ActionDefinition.validate(action)

    confirmed = %ActionDefinition{
      action
      | confirmation: %ActionConfirmation{
          title: "Retry delivery?",
          message: "This starts another external delivery attempt.",
          confirm_label: "Retry delivery",
          tone: :attention
        }
    }

    assert :ok = ActionDefinition.validate(confirmed)

    assert {:error, :invalid_application_action_definition} =
             ActionDefinition.validate(%ActionDefinition{action | confirmation: %{}})
  end

  test "resolves only actions declared by an application" do
    application = valid_application([valid_action()])

    assert {:ok, %ActionDefinition{action_id: "retry_delivery"}} =
             ApplicationDefinition.fetch_action(application, "retry_delivery")

    assert {:error, :undeclared_application_action} =
             ApplicationDefinition.fetch_action(application, "not_declared")

    assert {:error, :undeclared_application_action} =
             ApplicationDefinition.fetch_action(application, :retry_delivery)
  end

  defp valid_action do
    %ActionDefinition{
      action_id: "retry_delivery",
      version: 1,
      intent: :operation,
      scope: :mission,
      input_contract: %{schema_id: "cadence.delivery.retry", version: 1},
      result_contract: %{schema_id: "cadence.delivery.attempt", version: 1},
      required_permission: "operate_mission",
      effect: :external,
      execution: :asynchronous,
      concurrency: %{strategy: :idempotency_key},
      progress_contract: %{schema_id: "cadence.delivery.progress", version: 1}
    }
  end

  defp valid_application(actions) do
    %ApplicationDefinition{
      application_key: "delivery",
      version: 1,
      display_name: "Delivery",
      description: "Deliver mission products.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      actions: actions
    }
  end
end
