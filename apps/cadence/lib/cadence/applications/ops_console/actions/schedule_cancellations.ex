defmodule Cadence.Applications.OpsConsole.Actions.ScheduleCancellations do
  @moduledoc "Cancellation bound to the exact reviewed reservation before the provider mutation."
  alias Cadence.Auth.Scope
  alias Cadence.Contacts.ProviderBooking

  @keys ~w(contract_version organization_id mission_id reservation_id provider_revision lifecycle_state provider_contact_ref)
  def execute(%Scope{} = scope, mission, params) do
    with true <- is_map(params) and Map.keys(params) == ["reservation_evidence"],
         e = params["reservation_evidence"],
         true <- is_map(e) and Enum.sort(Map.keys(e)) == Enum.sort(@keys),
         true <-
           e["contract_version"] === 1 and e["organization_id"] == scope.organization_id and
             e["mission_id"] == mission,
         true <- scope.mission_id in [nil, mission],
         true <- identifier?(e["reservation_id"]) and text?(e["provider_contact_ref"]),
         v when is_integer(v) and v in 1..2_147_483_647 <- e["provider_revision"],
         true <- e["lifecycle_state"] in ~w(pending confirmed active) do
      ProviderBooking.cancel(scope.organization_id, mission, e["reservation_id"],
        expected_cancel_evidence:
          Map.take(e, ~w(provider_revision lifecycle_state provider_contact_ref))
      )
    else
      _ -> {:error, :invalid_reservation_cancellation_evidence}
    end
  end

  defp identifier?(v),
    do: text?(v) and byte_size(v) <= 240 and not Regex.match?(~r/[\x00-\x20\x7f]/, v)

  defp text?(v), do: is_binary(v) and byte_size(v) in 1..512 and String.valid?(v)
end
