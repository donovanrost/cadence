defmodule Cadence.Reads.ApplicationSurfaces.ReferenceResolverTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{HostContext, SurfaceDocument}
  alias Cadence.Applications.SurfaceElements.GeneratedForm
  alias Cadence.Auth.Scope

  alias Cadence.Extensions.Presentation.{
    FieldDefinition,
    ReferenceDefinition
  }

  alias Cadence.Reads.ApplicationSurfaces.ReferenceResolver

  test "refuses a reference field: no provider is registered (#669)" do
    assert {:error, :unknown_reference_provider} =
             resolve_reference(%ReferenceDefinition{
               provider_id: "mission.application.query",
               version: 1
             })
  end

  test "rejects a reference input without a typed provider contract" do
    assert {:error, :invalid_reference_field} = resolve_reference(nil)
  end

  defp resolve_reference(reference) do
    scope = %Scope{
      actor_kind: :user,
      organization_id: "org-reference-resolver",
      user: %{user_id: "reference-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    document = %SurfaceDocument{
      title: "Reference contract",
      form: %GeneratedForm{
        id: "reference-contract-form",
        title: "Reference contract",
        action_id: "save_reference",
        submit_label: "Save",
        success_message: "Saved.",
        fields: [
          %FieldDefinition{
            field: :point_id,
            label: "Point",
            type: :reference,
            reference: reference
          }
        ]
      }
    }

    ReferenceResolver.resolve(scope, HostContext.mission("mission-reference-resolver"), document)
  end
end
