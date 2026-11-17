defmodule Cadence.Control.ActivationRequests.RefusalsTest do
  @moduledoc "ux U95: what the approve preflight's refusals carry for the console's words."
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Control.ActivationRequests.Refusals

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))
    {org, mission} = {"org-refusals-" <> id, "mission-refusals-" <> id}
    persist_mission_scope(org, mission)
    revision = Fixtures.persist_imported_revision!(org, mission, approve: false)
    %{org: org, mission: mission, revision: revision}
  end

  test "an unapproved model names its catalog revision; one no catalog names has nulls", c do
    model = c.revision.mission_model_revision_id
    request = %{metadata: %{"mission_model" => %{"revision_id" => model}}}

    assert {:error, {:approve_refused, :mission_model_revision_not_approved, details}} =
             Refusals.explain(
               {:error, :mission_model_revision_not_approved},
               c.org,
               c.mission,
               request
             )

    number = c.revision.revision_number
    assert %{catalog_revisions: [%{number: ^number, mission_model_revision_id: ^model}]} = details

    assert {:error,
            {:approve_refused, :mission_model_revision_not_approved,
             %{catalog_revisions: [%{id: nil, number: nil, mission_model_revision_id: "orphan"}]}}} =
             Refusals.explain(
               {:error, {:mission_model_revision_not_approved, ["orphan"]}},
               c.org,
               c.mission,
               %{metadata: %{}}
             )
  end

  test "a failed comparison names the report, the model and its catalog revision", c do
    model = c.revision.mission_model_revision_id
    number = c.revision.revision_number

    assert {:error,
            {:approve_refused, :mission_model_comparison_failed,
             %{
               catalog_revision: %{number: ^number},
               mission_model_revision_id: ^model,
               comparison_report_id: "report-1"
             }}} =
             Refusals.explain(
               {:error, {:mission_model_comparison_failed, model, "report-1"}},
               c.org,
               c.mission,
               %{metadata: %{}}
             )
  end

  test "plain refusals carry no details; a manifest field is named; others pass through", c do
    # domain's R1: the configuration admission's two, also refused before anything is recorded.
    for code <- [
          :approved_activation_content_mismatch,
          :change_set_activation_stale,
          :spacecraft_configuration_review_required
        ] do
      assert {:error, {:approve_refused, ^code, nil}} =
               Refusals.explain({:error, code}, c.org, c.mission, %{metadata: %{}})
    end

    # ux U95: a model no longer active names nothing without reviewed craft in the request.
    assert {:error, {:approve_refused, :spacecraft_model_not_active, nil}} =
             Refusals.explain({:error, :spacecraft_model_not_active}, c.org, c.mission, %{
               metadata: %{}
             })

    assert {:error, {:approve_refused, :mission_model_manifest_mismatch, %{field: "plans"}}} =
             Refusals.explain(
               {:error, {:mission_model_manifest_mismatch, :plans}},
               c.org,
               c.mission,
               %{metadata: %{}}
             )

    assert {:error, :activation_policy_changed} =
             Refusals.explain(
               {:error, :activation_policy_changed},
               c.org,
               c.mission,
               %{metadata: %{}}
             )

    assert {:ok, :anything} =
             Refusals.explain({:ok, :anything}, c.org, c.mission, %{metadata: %{}})
  end
end
