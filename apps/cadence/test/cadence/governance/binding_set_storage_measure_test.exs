defmodule Cadence.Governance.BindingSetStorageMeasureTest do
  @moduledoc """
  Before/after numbers for #447 (CTO condition 2): what one generation of N spacecraft costs in
  the binding-set tables, and what applying it costs. Excluded from the normal run (`:scale`);

      mix test test/cadence/governance/binding_set_storage_measure_test.exs --include scale

  in a quiet window, on a catalog the size of dev's (10 packets a craft, so the cross product the
  issue measured: craft × 10 instances and rules). It prints rows and bytes added to the binding tables, statements and wall time
  for the review (which writes the version) and the apply, for a full fleet and for a one-craft
  change after it. The same file runs on develop (the tables of the membership form are read only
  when they exist), so one script gives both sides.
  """
  use Cadence.RuntimeCase, async: false

  @moduletag :scale
  @moduletag timeout: 1_800_000

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

  @tables ~w(governed_binding_sets governed_capability_instances governed_binding_rules
             governed_binding_artifacts governed_binding_set_members)

  setup do
    # The equivalence verifier reads every version back: it would be counted as statements here.
    verifier = Application.get_env(:cadence, :binding_set_storage_verifier)
    Application.delete_env(:cadence, :binding_set_storage_verifier)
    on_exit(fn -> Application.put_env(:cadence, :binding_set_storage_verifier, verifier) end)
    :ok
  end

  for craft <- [500, 1_000] do
    test "#{craft} spacecraft: one generation, and a one-craft change after it" do
      craft = unquote(craft)
      org = "org-measure-#{craft}"
      mid = "mission-measure-#{craft}"

      {first, revision, _endpoint} =
        Fixtures.setup_imported_mission!(org, mid, yaml: Fixtures.dev_sized_yaml())

      {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
      scope = Fixtures.user_scope(org, "operator")
      policy = ActivationPolicy.load(org, mid)

      {:ok, _} =
        ActivationPolicy.save(scope, mid, policy.token, %{
          "value" => %{"approval_requirement" => "direct"}
        })

      fleet = [
        first
        | Enum.map(2..craft, &Fixtures.persist_spacecraft!(org, mid, display_name: "Fleet #{&1}"))
      ]

      tokens = Map.new(fleet, &{&1.spacecraft_id, save(mission, scope, revision, &1, true)})
      full = measure(fn -> Review.request_many(scope, mid, tokens) end)
      {:ok, request} = full.result
      {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
      apply_full = measure(fn -> ControlActivations.execute(approved) end)
      assert {:ok, %{status: :succeeded}} = apply_full.result

      # One craft's commanding switch changes: the version written is still the whole fleet's.
      one = %{first.spacecraft_id => save(mission, scope, revision, first, false)}
      canary = measure(fn -> Review.request_many(scope, mid, one) end)
      {:ok, canary_request} = canary.result
      {:ok, canary_approved} = Activations.fetch_approved(canary_request.activation_request_id)
      apply_canary = measure(fn -> ControlActivations.execute(canary_approved) end)
      assert {:ok, %{status: :succeeded}} = apply_canary.result

      report(craft, "generation review (writes the version)", full)
      report(craft, "generation apply", apply_full)
      report(craft, "one-craft change review (writes the version)", canary)
      report(craft, "one-craft change apply", apply_canary)
    end
  end

  # Rows and bytes the binding tables gained, and the statements and wall time of `fun`.
  defp measure(fun) do
    before = sizes()
    test_pid = self()
    handler = "measure-#{System.unique_integer([:positive])}"
    counter = :counters.new(2, [])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        if self() == test_pid, do: count_query(counter, metadata[:result])
      end,
      nil
    )

    {us, result} =
      try do
        :timer.tc(fun)
      after
        :telemetry.detach(handler)
      end

    after_sizes = sizes()

    %{
      result: result,
      statements: :counters.get(counter, 1),
      rows_returned: :counters.get(counter, 2),
      ms: div(us, 1000),
      rows_added: after_sizes.rows - before.rows,
      bytes_added: after_sizes.bytes - before.bytes
    }
  end

  defp count_query(counter, result) do
    :counters.add(counter, 1, 1)

    case result do
      {:ok, %{num_rows: rows}} when is_integer(rows) -> :counters.add(counter, 2, rows)
      _other -> :ok
    end
  end

  defp sizes do
    Enum.reduce(@tables, %{rows: 0, bytes: 0}, fn table, acc ->
      %{rows: [[exists]]} = Repo.query!("SELECT to_regclass('#{table}') IS NOT NULL")

      if exists do
        %{rows: [[rows, bytes]]} =
          Repo.query!(
            "SELECT (SELECT count(*) FROM #{table}), pg_total_relation_size('#{table}'::regclass)"
          )

        %{rows: acc.rows + rows, bytes: acc.bytes + bytes}
      else
        acc
      end
    end)
  end

  defp report(craft, what, m) do
    IO.puts(
      "MEASURE #{craft} craft | #{what}: #{m.statements} statements, #{m.ms} ms, " <>
        "+#{m.rows_added} binding rows, +#{m.bytes_added} bytes"
    )
  end

  defp save(mission, scope, revision, craft, commanding) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => commanding,
        "handled_apids" => Fixtures.dev_sized_apids()
      })

    :ok =
      Fixtures.change_set_switches!(
        scope.organization_id,
        mission.mission_id,
        craft.spacecraft_id,
        document
      )

    {:ok, _} =
      Drafts.save(scope, mission.mission_id, craft.spacecraft_id, current.token, document)

    Drafts.snapshot(mission, craft).token
  end
end
