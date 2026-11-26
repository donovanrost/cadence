defmodule Cadence.AlarmsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow, Episodes, Ground, Notify}
  alias Cadence.Control.Alarms
  alias Cadence.Limits.Event
  alias Cadence.Reads.AlarmEpisodes
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("alarms")

    %{
      org: org,
      mission: mission,
      alice: member_scope(org, :member, "Alice"),
      bob: member_scope(org, :member, "Bob")
    }
  end

  describe "episode transitions" do
    test "open, escalate (clears ack), deescalate (keeps ack), auto-clear", ctx do
      observe(ctx, :caution, 0)
      [episode] = list(ctx)
      assert %{status: :new, severity: :caution} = episode

      {:ok, _} = Alarms.acknowledge(ctx.alice, ctx.mission, episode.id)
      observe(ctx, :critical, 1)
      assert [%{status: :new, severity: :critical, peak_severity: :critical}] = list(ctx)

      {:ok, _} = Alarms.acknowledge(ctx.alice, ctx.mission, episode.id)
      observe(ctx, :caution, 2)
      assert [%{status: :acknowledged, severity: :caution}] = list(ctx)

      observe(ctx, :normal, 3)
      assert [] = list(ctx)

      {:ok, detail} = Alarms.get_episode(ctx.alice, ctx.mission, episode.id)
      assert %{status: :cleared, cleared_unacknowledged: false} = detail

      assert Enum.map(detail.events, & &1.kind) ==
               [:raised, :acknowledged, :escalated, :acknowledged, :deescalated, :cleared]

      assert %{payload: %{"acknowledgement_cleared" => true}} =
               Enum.find(detail.events, &(&1.kind == :escalated))
    end

    test "a clear before anyone acknowledged is recorded", ctx do
      observe(ctx, :critical, 0)
      observe(ctx, :normal, 1)

      assert [%{status: :cleared, cleared_unacknowledged: true}] =
               list(ctx, %{state: "cleared"})
    end

    test "replayed and out-of-order observations change nothing", ctx do
      observe(ctx, :caution, 10, "ref-1")
      assert {:ok, :unchanged} = Episodes.observe(Repo, observation(ctx, :critical, 11, "ref-1"))

      assert {:ok, :unchanged} =
               Episodes.observe(Repo, observation(ctx, :normal, -60_000, "ref-old"))

      assert [%{severity: :caution, status: :new}] = list(ctx)
    end

    test "unknown or disabled states don't open episodes", ctx do
      assert {:ok, :unchanged} = Episodes.observe(Repo, observation(ctx, :ignore, 0))
      assert [] = list(ctx)
    end
  end

  describe "ground limits" do
    test "evaluation events open episodes and carry the evaluation time", ctx do
      {:ok, {_mission, 1}} = Ground.observe(Repo, ctx.mission, [limit_event(ctx, :red, 0)])

      assert [%{source: :ground_limit, severity: :critical, last_evaluated_at: %DateTime{}}] =
               list(ctx)
    end

    test "a projection rebuild clears subjects that are gone", ctx do
      Ground.observe(Repo, ctx.mission, [limit_event(ctx, :yellow, 0)])
      {:ok, {_mission, 1}} = Ground.reconcile(Repo, ctx.mission, nil, [])
      assert [] = list(ctx)
      assert [%{status: :cleared}] = list(ctx, %{state: "cleared"})
    end
  end

  describe "commands" do
    setup ctx do
      observe(ctx, :critical, 0)
      [episode] = list(ctx)
      %{episode: episode}
    end

    test "acknowledge is idempotent and publishes",
         %{alice: alice, mission: mission, episode: episode} = ctx do
      Notify.subscribe(ctx.org, mission)
      # #469: named only as a member of the organization (member_scope persists Alice's).

      assert {:ok, %{status: :acknowledged, acknowledged_by: %{name: "Alice"}}} =
               Alarms.acknowledge(alice, mission, episode.id)

      assert_receive {:alarms_changed, _, _}
      assert {:ok, %{status: :acknowledged}} = Alarms.acknowledge(alice, mission, episode.id)
    end

    test "assign needs an organization member and doesn't acknowledge", ctx do
      %{alice: alice, mission: mission, episode: episode} = ctx

      assert {:error, :assignee_not_member} = Alarms.assign(alice, mission, episode.id, "nobody")

      # Bob's user and membership are persisted by ConfigurationFixtures.member_scope (#471).
      bob_id = ctx.bob.user.user_id

      assert {:ok, %{assignee: %{id: ^bob_id, name: "Bob"}, status: :new}} =
               Alarms.assign(alice, mission, episode.id, bob_id)

      # #469: the stored assignee and actor documents carry no email.
      stored = Repo.get_by!(EpisodeRow, episode_id: episode.id)
      refute inspect(stored.assignee) =~ "@"
      refute inspect(stored.acknowledged_by) =~ "@"
    end

    test "hand off needs a note; cleared episodes take notes only", ctx do
      %{alice: alice, mission: mission, episode: episode} = ctx

      assert {:error, :note_required} =
               Alarms.hand_off(alice, mission, episode.id, %{to: nil, note: " "})

      assert {:ok, %{assignee: nil}} =
               Alarms.hand_off(alice, mission, episode.id, %{
                 to: nil,
                 note: "Next shift: watch VBAT"
               })

      observe(ctx, :normal, 1)
      assert {:error, :episode_cleared} = Alarms.acknowledge(alice, mission, episode.id)
      assert {:ok, _} = Alarms.add_note(alice, mission, episode.id, "Recovered after eclipse")

      {:ok, %{events: events}} = Alarms.get_episode(alice, mission, episode.id)
      assert [:raised, :handed_off, :cleared, :note] = Enum.map(events, & &1.kind)
    end

    test "outsiders can't act", %{org: org, mission: mission, episode: episode} do
      outsider = member_scope(org) |> Map.put(:organization_membership, nil)
      assert {:error, :forbidden} = Alarms.acknowledge(outsider, mission, episode.id)
      assert {:ok, []} = Alarms.permissions(outsider, mission)
    end
  end

  describe "console read" do
    # #469 (ca-security, dashboards): an outsider's old-form documents (stored before #469 with
    # an email for a name) never reach the read: the assignee, who acknowledged, each event's
    # actor and an assignment payload's from/to read {id: nil, name: nil}. No email, no id.
    test "an outsider's old-form documents read with neither email nor id (#469)", ctx do
      observe(ctx, :caution, 0)
      [episode] = list(ctx)
      {:ok, _} = Alarms.assign(ctx.alice, ctx.mission, episode.id, ctx.bob.user.user_id)
      {:ok, _} = Alarms.acknowledge(ctx.alice, ctx.mission, episode.id)

      old = %{"id" => "outsider-469", "name" => "out@example.test"}
      actor = Map.put(old, "kind", "user")
      id = episode.id

      Repo.update_all(from(e in EpisodeRow, where: e.episode_id == ^id),
        set: [assignee: old, acknowledged_by: actor]
      )

      Repo.update_all(from(e in EpisodeEventRow, where: e.episode_id == ^id), set: [actor: actor])

      Repo.update_all(
        from(e in EpisodeEventRow, where: e.episode_id == ^id and e.kind == "assigned"),
        set: [payload: %{"from" => old, "to" => old, "note" => nil}]
      )

      assert {:ok, read} = AlarmEpisodes.get(ctx.alice, ctx.mission, id)

      assert read.assignee == %{id: nil, name: nil}
      assert read.acknowledged_by == %{kind: "user", id: nil, name: nil}
      assert Enum.all?(read.events, &(&1.actor == %{kind: "user", id: nil, name: nil}))

      assert [%{"from" => %{"id" => nil, "name" => nil}, "to" => %{"id" => nil, "name" => nil}}] =
               for(%{payload: %{"from" => _} = payload} <- read.events, do: payload)

      refute inspect(read) =~ "@"
      refute inspect(read) =~ "outsider-469"
    end

    test "lists episodes with spacecraft and a summary", ctx do
      {:ok, sc} =
        SpacecraftStore.persist_spacecraft(
          ctx.org,
          Spacecraft.new(%{
            mission_id: ctx.mission,
            display_name: "EARENDIL-312",
            scid: 312
          })
        )

      Episodes.observe(Repo, %{observation(ctx, :critical, 0) | spacecraft_id: sc.spacecraft_id})

      assert {:ok, %{episodes: [episode], summary: %{active: 1, critical: %{new: 1}}}} =
               AlarmEpisodes.list(ctx.alice, ctx.mission)

      assert %{spacecraft: %{name: "EARENDIL-312", scid: 312}, point: %{name: "VBAT", unit: nil}} =
               episode
    end
  end

  defp observe(ctx, level, offset, ref \\ nil) do
    {:ok, _} = Episodes.observe(Repo, observation(ctx, level, offset, ref))
  end

  # Observation times track the wall clock (as live samples do), so they interleave correctly
  # with operator actions; a negative offset makes an observation older than earlier ones.
  defp observation(ctx, level, offset, ref \\ nil) do
    at = DateTime.add(DateTime.utc_now(), offset, :millisecond)

    %{
      source: "catalog_monitoring",
      organization_id: ctx.org,
      mission_id: ctx.mission,
      spacecraft_id: nil,
      subject_key: "VBAT/policy-1",
      parameter_ref: "VBAT",
      point_name: "VBAT",
      level: level,
      source_state: Atom.to_string(level),
      value: 23.1,
      observed_at: at,
      evaluated_at: at,
      ref: ref || unique("ref")
    }
  end

  defp limit_event(ctx, state, offset) do
    at = DateTime.add(DateTime.utc_now(), offset, :millisecond)

    %Event{
      limit_event_id: unique("limit_event"),
      mission_id: ctx.mission,
      point_id: "VBAT",
      point_name: "VBAT",
      limit_definition_id: "def-1",
      limit_definition_version: 1,
      limit_set_name: "default",
      evaluated_value: 22.0,
      limit_state: :red_low,
      normalized_state: state,
      violation: state != :green,
      generation_time: at,
      receipt_time: at
    }
  end

  defp list(ctx, filters \\ %{}) do
    {:ok, episodes} = Alarms.list_episodes(ctx.alice, ctx.mission, filters)
    episodes
  end
end
