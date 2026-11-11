defmodule Cadence.Commanding.VerifierArgumentsTest do
  @moduledoc "value_from_argument resolves to the request's value when the instance is created."
  use Cadence.UnitCase, async: true

  alias Cadence.Catalog.Command.Compiler.VerifierPlan
  alias Cadence.Catalog.Command.MatchCriteria

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    ReleaseArtifacts,
    VerifierArguments
  }

  @mode %{argument_id: "argument:mode", name: "mode", base_type: :enumerated}
  @ids %{
    mission_id: "mission",
    source_endpoint_ref: "endpoint",
    mission_model_revision_id: "revision",
    command_id: "command:set_mode",
    command_request_id: "request-1",
    command_queue_entry_id: "entry-1",
    queue_lane_key: "lane",
    realized_contact_id: "contact-1"
  }
  @label %{argument_id: "argument:label", name: "label", base_type: :string}

  test "values are keyed by argument id; an enumerated code sent as a string is its integer" do
    request = request(%{"mode" => "3", "label" => "07"})

    assert VerifierArguments.values(request, [@mode, @label]) ==
             %{"argument:mode" => 3, "argument:label" => "07"}

    assert VerifierArguments.values(request(%{}), [@mode]) == %{}
  end

  test "bind fills value from the argument, in nested conditions too; a missing one stays nil" do
    applied = criteria("argument:mode")

    compound =
      MatchCriteria.new(%{criteria_type: :compound, operator: :and, conditions: [applied]})

    arguments = %{"argument:mode" => 3}

    assert %MatchCriteria{value: 3} = VerifierArguments.bind(applied, arguments)
    assert %{conditions: [%{value: 3}]} = VerifierArguments.bind(compound, arguments)
    assert %MatchCriteria{value: nil} = VerifierArguments.bind(applied, %{})
    assert VerifierArguments.bind(nil, arguments) == nil

    constant = MatchCriteria.new(%{subject_ref: "transport:completed", value: true})
    assert VerifierArguments.bind(constant, arguments) == constant
  end

  test "a released SET_MODE's Mode applied instance compares with the commanded mode" do
    request = request(%{"mode" => 4})

    plan =
      VerifierPlan.new(%{
        command_id: "command:set_mode",
        verifier_id: "verifier:mode_applied",
        name: "Mode applied",
        phase: :completion,
        success_criteria: criteria("argument:mode")
      })

    [instance] =
      ReleaseArtifacts.verifier_instances(
        CommandQueueEntry.new(Map.put(@ids, :organization_id, "org")),
        request,
        CommandReleaseAttempt.new(Map.put(@ids, :command_release_attempt_id, "attempt-1")),
        [plan],
        ~U[2026-11-11 12:00:00Z],
        [@mode]
      )

    assert %MatchCriteria{value: 4, value_from_argument: "argument:mode", use_calibrated: false} =
             instance.success_criteria
  end

  defp request(values),
    do:
      CommandRequest.new(
        Map.merge(@ids, %{command_name: "SET_MODE", resolved_argument_values: values})
      )

  defp criteria(argument_id) do
    MatchCriteria.new(%{
      criteria_type: :comparison,
      subject_ref: "semantic:parameter:sc_mode",
      comparison: :equal,
      value_from_argument: argument_id,
      use_calibrated: false
    })
  end
end
