defmodule Cadence.Applications.ApplicationDefinitionTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ApplicationDefinition,
    ResourceClaimDefinition,
    ResourceContract
  }

  test "accepts a bounded application definition" do
    assert :ok = ApplicationDefinition.validate(valid_application())
  end

  test "an application is valid on several installable scopes" do
    application = %ApplicationDefinition{
      valid_application()
      | installable_scopes: [:mission, :spacecraft]
    }

    assert :ok = ApplicationDefinition.validate(application)
  end

  test "rejects unknown or duplicate installable scopes" do
    for scopes <- [[], [:mission, :mission], [:galaxy]] do
      assert {:error, :invalid_application_definition} =
               ApplicationDefinition.validate(%ApplicationDefinition{
                 valid_application()
                 | installable_scopes: scopes
               })
    end
  end

  test "rejects duplicate resource claim identities" do
    claim = %ResourceClaimDefinition{
      claim_type: :canonical_point,
      scope: :mission,
      mode: :shared,
      description: "Canonical telemetry input."
    }

    assert {:error, :invalid_application_resource_contract} =
             ResourceContract.validate(%ResourceContract{claims: [claim, claim]})
  end

  defp valid_application do
    %ApplicationDefinition{
      application_key: "example",
      version: 1,
      display_name: "Example",
      description: "A bounded application definition.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      configuration_contract: %{schema_id: "cadence.example.configuration", version: 1}
    }
  end
end
