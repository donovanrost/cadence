defmodule Cadence.Configuration.ChangeSetLanesTest do
  @moduledoc """
  ADR-020 P3 slice L (#451; U108): change sets run in lanes. Configuration keeps one active set
  (open or in review); monitoring has one open set, and its sets in review don't count. Every kind
  is in one lane, so one staging request never spans two.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Configuration.{ChangeSetRow, ChangeSetStore, Kinds, Staging, Status}
  alias Cadence.Repo

  defmodule MonitoringStubKind do
    @moduledoc false
    def kind, do: "monitoring_lane_stub"
    def lane, do: :monitoring
  end

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission()
    %{org: org, mission: mission, actor: %{"kind" => "user", "id" => "user-lanes"}}
  end

  defp open!(c, lane) do
    {:ok, set} =
      Repo.transaction(fn -> ChangeSetStore.lock_or_open(c.org, c.mission, 1, c.actor, lane) end)

    set
  end

  defp to_review!(set),
    do:
      set
      |> Ecto.Changeset.change(state: "in_review", submitted_at: DateTime.utc_now())
      |> Repo.update!()

  test "each lane opens its own set, and neither is the other's", c do
    configuration = open!(c, "configuration")
    monitoring = open!(c, "monitoring")

    assert configuration.lane == "configuration"
    assert monitoring.lane == "monitoring"
    refute configuration.change_set_id == monitoring.change_set_id

    assert ChangeSetStore.active(c.mission).change_set_id == configuration.change_set_id

    assert ChangeSetStore.active(c.mission, "monitoring").change_set_id ==
             monitoring.change_set_id

    # Staging again lands in the same open set of its lane.
    assert open!(c, "monitoring").change_set_id == monitoring.change_set_id
  end

  test "a monitoring set in review doesn't hold the lane; a configuration one does", c do
    first = c |> open!("monitoring") |> to_review!()
    second = open!(c, "monitoring")

    refute second.change_set_id == first.change_set_id
    assert [%ChangeSetRow{change_set_id: id}] = ChangeSetStore.in_review(c.mission, "monitoring")
    assert id == first.change_set_id

    reviewed = c |> open!("configuration") |> to_review!()
    # Configuration's in-review set is still its active one: staging finds it (and freezes).
    assert open!(c, "configuration").change_set_id == reviewed.change_set_id
  end

  test "the database holds each lane to its rule", c do
    open!(c, "monitoring")

    duplicate = %ChangeSetRow{
      change_set_id: "change_set:dup",
      organization_id: c.org,
      mission_id: c.mission,
      lane: "monitoring",
      state: "open",
      base_revision_number: 1,
      opened_by: c.actor,
      opened_at: DateTime.utc_now()
    }

    assert_raise Ecto.ConstraintError, fn -> Repo.insert!(duplicate) end

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%{duplicate | change_set_id: "change_set:lane", lane: "telemetry"})
    end
  end

  describe "a staging request goes to one lane" do
    setup do
      previous = Application.get_env(:cadence, :configuration_kinds, [])
      Application.put_env(:cadence, :configuration_kinds, previous ++ [MonitoringStubKind])
      on_exit(fn -> Application.put_env(:cadence, :configuration_kinds, previous) end)
      :ok
    end

    test "its kinds' lane, configuration when no kind says otherwise" do
      assert Kinds.lane(MonitoringStubKind) == "monitoring"
      assert Kinds.lane(Kinds.fetch!("ground_station")) == "configuration"

      assert {:ok, "configuration"} = Staging.lane([%{kind: "ground_station", action: "create"}])

      assert {:ok, "monitoring"} =
               Staging.lane([%{kind: "monitoring_lane_stub", action: "create"}])

      # An unknown kind is its op's own refusal, later.
      assert {:ok, "configuration"} = Staging.lane([%{kind: "nope", action: "create"}])
    end

    test "never two lanes at once" do
      assert {:error, :mixed_lanes} =
               Staging.lane([
                 %{kind: "ground_station", action: "create"},
                 %{kind: "monitoring_lane_stub", action: "create"}
               ])
    end
  end

  test "the staged bar is per lane; monitoring's lists its sets in review", c do
    reviewed = c |> open!("monitoring") |> to_review!()

    configuration = Status.current(c.org, c.mission)
    assert configuration.lane == "configuration"
    assert configuration.change_set == nil
    refute Map.has_key?(configuration, :in_review)

    monitoring = Status.current(c.org, c.mission, "monitoring")
    assert monitoring.change_set == nil
    assert [%{id: id}] = monitoring.in_review
    assert id == reviewed.change_set_id
    assert monitoring.head == configuration.head
  end
end
