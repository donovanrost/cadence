defmodule Cadence.ContactPlanning.GrantOperationsTest do
  @moduledoc """
  #283: a grant operation's request digest is a stored hash recomputed on replay (DECISIONS
  #108), so its layout is pinned here. A change to these values is a layout change.
  """
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.GrantOperations

  test "golden digests, one per action" do
    digests = %{
      approve: GrantOperations.digest(:approve, "sha-abc"),
      reject: GrantOperations.digest(:reject, "  Too broad "),
      narrow:
        GrantOperations.digest(:narrow, %{
          "maximum_contacts" => 2,
          allowed_actions: [:repair, :plan]
        })
    }

    assert digests == golden()
  end

  test "normalization: reason trimmed, changes sorted and keyed alike" do
    assert GrantOperations.digest(:reject, "Too broad") ==
             GrantOperations.digest(:reject, "  Too broad  ")

    assert GrantOperations.digest(:narrow, %{
             allowed_actions: [:plan, :repair],
             maximum_contacts: 2
           }) ==
             GrantOperations.digest(:narrow, %{
               "maximum_contacts" => 2,
               "allowed_actions" => ["repair", "plan"]
             })
  end

  defp golden,
    do: %{
      approve: "b62811d9b1385f73df71156fb1ed2c3548e40cc8660c7c542df3cdb75b64730c",
      reject: "2471a44c412f044fa5b9a2806f1b17d062cdd7cba6e58ab4dd0f583b05d71480",
      narrow: "83376f3b16a997492322b7826141e6998745cdbf2719294c2f21738239053ab6"
    }
end
