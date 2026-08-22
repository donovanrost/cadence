defmodule CadenceWeb.Components.ApplicationDomainActionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Applications.{
    ActionConfirmation,
    ActionDefinition,
    ApplicationDefinition,
    SurfaceDefinition
  }

  alias CadenceWeb.Components.ApplicationDomainAction

  test "renders typed action semantics and host confirmation metadata" do
    action = action_definition()
    application = application_definition(action)
    surface = surface_definition([action.action_id])

    html =
      render_component(&ApplicationDomainAction.application_domain_action/1,
        id: "retry-delivery-action",
        application_definition: application,
        surface_definition: surface,
        action_id: action.action_id,
        label: "Retry delivery",
        event: "application_action"
      )

    document = LazyHTML.from_fragment(html)
    trigger = LazyHTML.query(document, "#retry-delivery-action")

    assert ["retry_delivery"] = LazyHTML.attribute(trigger, "data-application-domain-action")
    assert ["1"] = LazyHTML.attribute(trigger, "data-action-version")
    assert ["operation"] = LazyHTML.attribute(trigger, "data-action-intent")
    assert ["mission"] = LazyHTML.attribute(trigger, "data-action-scope")
    assert ["external"] = LazyHTML.attribute(trigger, "data-action-effect")
    assert ["asynchronous"] = LazyHTML.attribute(trigger, "data-action-execution")
    assert ["true"] = LazyHTML.attribute(trigger, "data-confirmation-required")
    assert ["attention"] = LazyHTML.attribute(trigger, "data-confirmation-tone")
    assert ["Retry delivery?"] = LazyHTML.attribute(trigger, "data-confirmation-title")
    assert ["Retry delivery"] = LazyHTML.attribute(trigger, "data-confirmation-label")
    assert ["application_action"] = LazyHTML.attribute(trigger, "phx-click")
    assert ["retry_delivery"] = LazyHTML.attribute(trigger, "phx-value-action-id")
  end

  test "fails closed when the surface does not declare the domain action" do
    action = action_definition()

    assert_raise ArgumentError, ~r/invalid domain action/, fn ->
      render_component(&ApplicationDomainAction.application_domain_action/1,
        id: "retry-delivery-action",
        application_definition: application_definition(action),
        surface_definition: surface_definition([]),
        action_id: action.action_id,
        label: "Retry delivery"
      )
    end
  end

  defp action_definition do
    %ActionDefinition{
      action_id: "retry_delivery",
      version: 1,
      intent: :operation,
      scope: :mission,
      required_permission: "operate_mission",
      effect: :external,
      execution: :asynchronous,
      confirmation: %ActionConfirmation{
        title: "Retry delivery?",
        message: "This starts another external delivery attempt.",
        confirm_label: "Retry delivery",
        tone: :attention
      }
    }
  end

  defp application_definition(action) do
    %ApplicationDefinition{
      application_key: "delivery",
      version: 1,
      display_name: "Delivery",
      description: "Deliver mission products.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      actions: [action]
    }
  end

  defp surface_definition(actions) do
    %SurfaceDefinition{
      surface_id: "operations",
      version: 1,
      purpose: :operations,
      scope: :mission,
      placement: :application_workspace,
      data_contract: %{query_id: "cadence.delivery.operations", version: 1},
      actions: actions,
      renderer: {:declarative, "cadence.host.surface.v1"}
    }
  end
end
