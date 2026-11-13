defmodule Cadence.Configuration.LimitDefinitionKindTest do
  @moduledoc """
  Limits through change sets (DECISIONS #77, stage 2): create, edit and retire keep the point's
  versions under one id; thresholds and points are checked; limit facts are announced only after
  a change set commits (a preview or a discarded change set announces nothing), while the direct
  save keeps announcing as it always has.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Alarms.EpisodeRow
  alias Cadence.Control.Configuration
  alias Cadence.Control.LimitDefinitionKind, as: ConfigKind
  alias Cadence.Limits
  alias Cadence.Limits.Facts

  @point "DERIVED.BUS_VOLTAGE"

  setup do
    on_exit(with_approval_required(false))
    kinds = Application.get_env(:cadence, :configuration_kinds, [])
    Application.put_env(:cadence, :configuration_kinds, Enum.uniq(kinds ++ [ConfigKind]))
    on_exit(fn -> Application.put_env(:cadence, :configuration_kinds, kinds) end)

    %{organization_id: org, mission_id: mission} = configuration_mission("limits")
    ctx = %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}

    apply_ops(ctx, "Point", [
      %{
        kind: "derived_telemetry",
        action: :create,
        document: %{"point_id" => @point, "expression" => "28 + 0"}
      }
    ])

    :ok = Facts.subscribe(relay(self()))
    ctx
  end

  describe "create, edit and retire" do
    test "keep one id and the point's versions; retired leaves the live set", ctx do
      [id] = apply_ops(ctx, "Add", [create(thresholds(20, 22, 30, 32))])

      assert id == Limits.limit_definition_id(@point, "DEFAULT")
      assert [%{limit_definition_id: ^id, version: 1}] = live(ctx)
      assert_announced(ctx, :registered, 1)

      apply_ops(ctx, "Edit", [edit(id, "thresholds.red_high", 34)])
      assert [%{version: 2, thresholds: %{"red_high" => 34}}] = live(ctx)
      assert_announced(ctx, :activated, 2)

      apply_ops(ctx, "Retire", [%{kind: "limit_definition", action: :delete, entity_id: id}])
      assert live(ctx) == []
      assert ConfigKind.load(ctx.org, ctx.mission, [id]) == %{}
      assert {:limit_fact, %{limit_definition_id: ^id}} = assert_announced(ctx, :retired, 2)

      # Adding the point's limits again continues its history under the same id.
      assert [^id] = apply_ops(ctx, "Again", [create(thresholds(21, 22, 30, 31))])
      assert [%{limit_definition_id: ^id, version: 3}] = live(ctx)
    end

    test "summaries name the set only when it isn't DEFAULT (U43)" do
      doc = %{"point_id" => @point, "limit_set_name" => "DEFAULT"}
      eclipse = %{doc | "limit_set_name" => "ECLIPSE"}
      assert ConfigKind.summary(:create, nil, doc) == "Add limits for #{@point}"
      assert ConfigKind.summary(:update, doc, doc) == "Edit limits for #{@point}"
      assert ConfigKind.summary(:delete, doc, nil) == "Retire limits for #{@point}"
      assert ConfigKind.summary(:create, nil, eclipse) == "Add ECLIPSE limits for #{@point}"
    end
  end

  describe "checks" do
    test "thresholds, unknown points and a second live set are refused", ctx do
      assert invalid_op(ctx, create(thresholds(30, 22, 20, 32))) == ["thresholds"]
      assert invalid_op(ctx, create(%{"red_low" => "low"})) == ["thresholds"]
      assert invalid_op(ctx, create(%{"amber" => 1})) == ["thresholds"]

      assert validation_errors(ctx, [create(thresholds(1, 2, 3, 4), "GHOST.value")]) == [
               "point_id"
             ]

      # Limits already live for the point and set are refused when staging (U43).
      [id] = apply_ops(ctx, "Add", [create(thresholds(20, 22, 30, 32))])

      assert {:error,
              {:invalid_op, 0,
               [
                 %{
                   path: "point_id",
                   message: "Limits for DERIVED.BUS_VOLTAGE already exist. Edit them instead."
                 }
               ]}} =
               Configuration.preview(
                 ctx.alice,
                 ctx.mission,
                 {:ops, [create(thresholds(1, 2, 3, 4))]}
               )

      {:ok, %{verdict: :no_go, checks: checks}} =
        Configuration.preview(
          ctx.alice,
          ctx.mission,
          {:ops, [edit(id, "limit_set_name", "ECLIPSE")]}
        )

      assert %{items: [%{errors: [%{path: "point_id", message: message}]}]} =
               Enum.find(checks, &(&1.key == "validation"))

      assert message == "The point and limit set can't change after the limits are added."
    end
  end

  describe "holds" do
    test "a raised limit alarm on the point asks for an acknowledgement (U43)", ctx do
      [id] = apply_ops(ctx, "Add", [create(thresholds(20, 22, 30, 32))])
      episode = raised_alarm(ctx)

      assert {:ok, %{verdict: :hold, checks: checks}} =
               Configuration.preview(
                 ctx.alice,
                 ctx.mission,
                 {:ops, [edit(id, "thresholds.red_high", 40)]}
               )

      assert %{
               items: [
                 %{
                   reason: :limit_alarm_active,
                   blocking: false,
                   sentence:
                     "DERIVED.BUS_VOLTAGE has a red-limit alarm raised now. When this is " <>
                       "applied, it's checked against the new limits and may clear or change.",
                   details: %{
                     point_id: @point,
                     limit_set_name: "DEFAULT",
                     severity: "critical",
                     episode_id: ^episode
                   }
                 }
               ]
             } = Enum.find(checks, &(&1.key == "compatibility"))
    end
  end

  describe "limit facts" do
    test "a preview announces nothing and leaves nothing behind", ctx do
      assert {:ok, %{verdict: :go}} =
               Configuration.preview(
                 ctx.alice,
                 ctx.mission,
                 {:ops, [create(thresholds(20, 22, 30, 32))]}
               )

      refute_announced(ctx)
      assert live(ctx) == []
    end

    test "a staged, previewed and then discarded change set announces nothing", ctx do
      {:ok, staged} =
        Configuration.stage(ctx.alice, ctx.mission, %{summary: "Maybe"}, [
          create(thresholds(20, 22, 30, 32))
        ])

      assert {:ok, %{verdict: :go}} =
               Configuration.preview(ctx.alice, ctx.mission, staged.change_set_id)

      assert {:ok, _} =
               Configuration.discard(ctx.alice, ctx.mission, staged.change_set_id, staged.version)

      refute_announced(ctx)
      assert live(ctx) == []
    end

    test "the direct save still announces as it always has", ctx do
      review = Limits.limit_definition_review(ctx.org, ctx.mission, @point, "DEFAULT")

      assert {:ok, _definition} =
               Limits.append_limit_definition(
                 ctx.org,
                 ctx.mission,
                 %{
                   point_id: @point,
                   limit_set_name: "DEFAULT",
                   thresholds: thresholds(1, 2, 3, 4)
                 },
                 review
               )

      assert_announced(ctx, :registered, 1)
    end
  end

  # The global bus delivers with a call, so a relay answers it and forwards the fact here.
  defp relay(test) do
    pid = spawn_link(fn -> relay_loop(test) end)
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp relay_loop(test) do
    receive do
      {:"$gen_call", from, {:cadence_fact, {:cadence, :limits, :facts}, fact}} ->
        GenServer.reply(from, :ok)
        send(test, {:limit_fact, fact})
    end

    relay_loop(test)
  end

  defp assert_announced(%{mission: mission}, event_type, version) do
    assert_receive {:limit_fact,
                    %{
                      mission_id: ^mission,
                      event_type: ^event_type,
                      limit_definition_version: ^version
                    }}
  end

  defp refute_announced(%{mission: mission}),
    do: refute_receive({:limit_fact, %{mission_id: ^mission}}, 200)

  defp raised_alarm(%{org: org, mission: mission}) do
    episode_id = "episode-" <> Integer.to_string(System.unique_integer([:positive]))
    now = DateTime.utc_now()

    Repo.insert!(%EpisodeRow{
      episode_id: episode_id,
      organization_id: org,
      mission_id: mission,
      spacecraft_id: "sc-1",
      spacecraft_scope_id: "sc-1",
      source: "ground_limit",
      subject_key: @point,
      parameter_ref: @point,
      severity: "critical",
      peak_severity: "critical",
      state: "active",
      source_state: "red_high",
      opened_at: now,
      last_observed_at: now,
      last_evaluated_at: now
    })

    episode_id
  end

  defp thresholds(red_low, yellow_low, yellow_high, red_high),
    do: %{
      "red_low" => red_low,
      "yellow_low" => yellow_low,
      "yellow_high" => yellow_high,
      "red_high" => red_high
    }

  defp live(%{org: org, mission: mission}), do: Limits.active_limit_definitions(org, mission)

  defp invalid_op(%{alice: alice, mission: mission}, op) do
    assert {:error, {:invalid_op, 0, errors}} =
             Configuration.preview(alice, mission, {:ops, [op]})

    Enum.map(errors, & &1.path)
  end

  defp validation_errors(%{alice: alice, mission: mission}, ops) do
    {:ok, %{verdict: :no_go, checks: checks}} = Configuration.preview(alice, mission, {:ops, ops})
    %{items: [%{errors: errors}]} = Enum.find(checks, &(&1.key == "validation"))
    Enum.map(errors, & &1.path)
  end

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end

  defp create(thresholds, point \\ @point),
    do: %{
      kind: "limit_definition",
      action: :create,
      document: %{"point_id" => point, "thresholds" => thresholds}
    }

  defp edit(id, path, value),
    do: %{
      kind: "limit_definition",
      action: :update,
      entity_id: id,
      changes: [%{path: path, value: value}]
    }
end
