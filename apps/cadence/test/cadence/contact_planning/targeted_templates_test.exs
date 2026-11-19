defmodule Cadence.ContactPlanning.TargetedTemplatesTest do
  @moduledoc "CP3: templates that target a profile, a plane or a list (DECISIONS #37)."
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    TemplateSupersession,
    TemplateTargets
  }

  alias Cadence.Spacecraft

  @organization_id "org-targeted-templates"
  @mission_id "mission-targeted-templates"
  @now ~U[2026-07-17 00:00:00.000000Z]

  setup do
    %{organization: organization} = persist_mission_scope(@organization_id, @mission_id)

    for {id, plane} <- [{"sc-a", 1}, {"sc-b", 1}, {"sc-c", 2}] do
      craft =
        Spacecraft.new(%{
          spacecraft_id: id,
          mission_id: @mission_id,
          display_name: "Craft #{id}",
          metadata: %{"plane" => plane}
        })

      {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(@organization_id, craft)
    end

    %{scope: scope(organization)}
  end

  describe "TemplateTargets (pure)" do
    test "normalizes each kind and rejects what would silently target nobody" do
      assert {:ok, %{"kind" => "plane", "plane" => 3}} =
               TemplateTargets.normalize(%{kind: "plane", plane: 3})

      assert {:error, _} = TemplateTargets.normalize(%{"kind" => "plane", "plane" => "3"})
      assert {:error, _} = TemplateTargets.normalize(%{"kind" => "plane"})
      assert {:error, _} = TemplateTargets.normalize(%{"kind" => "profile"})

      assert {:error, _} =
               TemplateTargets.normalize(%{"kind" => "spacecraft_ids", "spacecraft_ids" => []})

      assert {:error, _} =
               TemplateTargets.normalize(%{
                 "kind" => "spacecraft_ids",
                 "spacecraft_ids" => ["a", "a"]
               })

      assert {:error, _} =
               TemplateTargets.normalize(%{
                 "kind" => "spacecraft_ids",
                 "spacecraft_ids" => ["a"],
                 "exclude_spacecraft_ids" => ["b"]
               })

      assert {:error, _} = TemplateTargets.normalize(%{"kind" => "fleet"})
    end

    test "selects by profile pin, integer plane and list, minus excludes" do
      crafts = [
        %Spacecraft{spacecraft_id: "a", spacecraft_type_id: "p1", metadata: %{"plane" => 1}},
        %Spacecraft{spacecraft_id: "b", spacecraft_type_id: "p1", metadata: %{"plane" => "1"}},
        %Spacecraft{spacecraft_id: "c", spacecraft_type_id: "p2", metadata: %{}}
      ]

      assert TemplateTargets.select(%{"kind" => "profile", "spacecraft_type_id" => "p1"}, crafts) ==
               ["a", "b"]

      # metadata.plane is free-form: a string "1" is not plane 1.
      assert TemplateTargets.select(%{"kind" => "plane", "plane" => 1}, crafts) == ["a"]

      profile = %{
        "kind" => "profile",
        "spacecraft_type_id" => "p1",
        "exclude_spacecraft_ids" => ["b", "c"]
      }

      assert TemplateTargets.select(profile, crafts) == ["a"]
      assert TemplateTargets.excluded_outside(profile, crafts) == ["c"]

      assert TemplateTargets.select(
               %{"kind" => "spacecraft_ids", "spacecraft_ids" => ["c"]},
               crafts
             ) ==
               ["c"]
    end
  end

  test "a plane template fans out per targeted spacecraft, once each", c do
    {:ok, template, version} =
      ContactRequirementTemplates.create(
        c.scope,
        @mission_id,
        attrs(%{"kind" => "plane", "plane" => 1}),
        now: @now
      )

    assert version.name == "Plane 1 downlinks"
    assert version.spacecraft_id == nil

    {:ok, results} = materialize(c, template, @now)

    # Two occurrences in the hour window × sc-a and sc-b.
    assert length(results) == 4

    assert results
           |> Enum.map(& &1.requirement_version.spacecraft_id)
           |> Enum.uniq()
           |> Enum.sort() ==
             ["sc-a", "sc-b"]

    {:ok, again} = materialize(c, template, @now)
    assert Enum.all?(again, &(&1.status == :existing))
  end

  test "targets are validated against the mission", c do
    assert {:error, {:template_target_unknown_spacecraft, ["ghost"]}} =
             ContactRequirementTemplates.create(
               c.scope,
               @mission_id,
               attrs(%{"kind" => "spacecraft_ids", "spacecraft_ids" => ["sc-a", "ghost"]})
             )

    assert {:error, :template_target_profile_not_found} =
             ContactRequirementTemplates.create(
               c.scope,
               @mission_id,
               attrs(%{"kind" => "profile", "spacecraft_type_id" => "nope"})
             )

    assert {:error, {:invalid_contact_requirement_template, _}} =
             ContactRequirementTemplates.create(
               c.scope,
               @mission_id,
               attrs(%{"kind" => "plane", "plane" => 0})
             )
  end

  test "fan-out over the cap fails instead of truncating", c do
    previous = Application.get_env(:cadence, :template_fan_out_limit)
    Application.put_env(:cadence, :template_fan_out_limit, 10_000)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :template_fan_out_limit, previous),
        else: Application.delete_env(:cadence, :template_fan_out_limit)
    end)

    assert ContactRequirementTemplates.fan_out_limit() == 10_000

    ids =
      for n <- 1..11 do
        id = "sc-fan-#{n}"
        craft = Spacecraft.new(%{spacecraft_id: id, mission_id: @mission_id, display_name: id})
        {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(@organization_id, craft)
        id
      end

    {:ok, template, _} =
      ContactRequirementTemplates.create(
        c.scope,
        @mission_id,
        attrs(%{"kind" => "spacecraft_ids", "spacecraft_ids" => ids}, %{
          schedule_document: %{
            "type" => "fixed_interval",
            "anchor_at" => DateTime.to_iso8601(@now),
            "interval_seconds" => 60,
            "window_offset_seconds" => 0,
            "window_duration_seconds" => 60
          },
          catch_up_policy_document: %{
            "maximum_occurrences_per_run" => 1_000,
            "maximum_lookback_seconds" => 86_400
          }
        }),
        now: @now
      )

    # 1,000 occurrences × 11 spacecraft > 10,000.
    assert {:error, {:template_fan_out_exceeded, 11_000}} =
             ContactRequirementTemplates.materialize(
               c.scope,
               @mission_id,
               template.contact_requirement_template_id,
               @now,
               DateTime.add(@now, 999 * 60, :second),
               now: @now
             )

    assert ContactRequirements.list(@organization_id, @mission_id) == []
  end

  test "a newer version supersedes the older version's future, unplanned requirements", c do
    {:ok, template, _} =
      ContactRequirementTemplates.create(c.scope, @mission_id, plane_one(), now: @now)

    {:ok, first} = materialize(c, template, @now)
    assert length(first) == 4

    {:ok, _, _} =
      ContactRequirementTemplates.version(
        c.scope,
        @mission_id,
        template.contact_requirement_template_id,
        1,
        %{name: "Plane 1 downlinks (5 min)"},
        now: @now
      )

    {:ok, second} = materialize(c, template, @now)
    assert Enum.all?(second, &(&1.status == :created))

    active = ContactRequirements.list(@organization_id, @mission_id, lifecycle_state: :active)
    assert length(active) == 4

    assert Enum.all?(active, fn {_, v} ->
             v.metadata["generation"]["contact_requirement_template_version"] == 2
           end)

    canceled = ContactRequirements.list(@organization_id, @mission_id, lifecycle_state: :canceled)
    assert length(canceled) == 4
    assert Enum.all?(canceled, fn {r, _} -> r.lifecycle_reason =~ "template_versioned" end)
  end

  test "spacecraft that leave the target lose their future requirements", c do
    {:ok, template, _} =
      ContactRequirementTemplates.create(c.scope, @mission_id, plane_one(), now: @now)

    {:ok, _} = materialize(c, template, @now)

    # sc-b moves to plane 2: the same version re-materializes and sc-b's future requirements go.
    {:ok, craft} = Cadence.SpacecraftStore.fetch_spacecraft(@organization_id, @mission_id, "sc-b")

    {:ok, _} =
      Cadence.SpacecraftStore.update_spacecraft(@organization_id, %{
        craft
        | metadata: %{"plane" => 2}
      })

    {:ok, again} = materialize(c, template, @now)
    assert again |> Enum.map(& &1.requirement_version.spacecraft_id) |> Enum.uniq() == ["sc-a"]

    canceled = ContactRequirements.list(@organization_id, @mission_id, lifecycle_state: :canceled)
    assert length(canceled) == 2

    assert Enum.all?(canceled, fn {r, v} ->
             v.spacecraft_id == "sc-b" and r.lifecycle_reason =~ "left_template_target"
           end)
  end

  test "requirements whose window has started are left alone", c do
    {:ok, template, v1} =
      ContactRequirementTemplates.create(c.scope, @mission_id, plane_one(), now: @now)

    {:ok, _} = materialize(c, template, @now)

    later = DateTime.add(@now, 3_600, :second)

    assert %{superseded: 0} =
             TemplateSupersession.supersede(c.scope, v1, [], later, {@now, later})

    assert length(
             ContactRequirements.list(@organization_id, @mission_id, lifecycle_state: :active)
           ) ==
             4
  end

  test "materializing with supersede: false (a reviewed fleet start) cancels nothing", c do
    {:ok, template, _} =
      ContactRequirementTemplates.create(c.scope, @mission_id, plane_one(), now: @now)

    {:ok, _} = materialize(c, template, @now)

    {:ok, _, _} =
      ContactRequirementTemplates.version(
        c.scope,
        @mission_id,
        template.contact_requirement_template_id,
        1,
        %{name: "Plane 1 v2"},
        now: @now
      )

    {:ok, _} =
      ContactRequirementTemplates.materialize(
        c.scope,
        @mission_id,
        template.contact_requirement_template_id,
        @now,
        DateTime.add(@now, 3_599, :second),
        now: @now,
        supersede: false
      )

    # v1 and v2 requirements are both still active: the reviewed inputs stay valid.
    assert length(
             ContactRequirements.list(@organization_id, @mission_id, lifecycle_state: :active)
           ) ==
             8
  end

  defp plane_one, do: attrs(%{"kind" => "plane", "plane" => 1})

  defp materialize(c, template, now) do
    ContactRequirementTemplates.materialize(
      c.scope,
      @mission_id,
      template.contact_requirement_template_id,
      now,
      DateTime.add(now, 3_599, :second),
      now: now
    )
  end

  defp attrs(target, overrides \\ %{}) do
    Map.merge(
      %{
        name: "Plane 1 downlinks",
        target_document: target,
        schedule_document: %{
          "type" => "fixed_interval",
          "anchor_at" => DateTime.to_iso8601(@now),
          "interval_seconds" => 1_800,
          "window_offset_seconds" => 600,
          "window_duration_seconds" => 1_200
        },
        requirement_document: %{
          "service_direction" => "downlink",
          "contact_intent" => "recurring_payload_downlink",
          "success_measure" => "minimum_duration",
          "minimum_duration_seconds" => 300,
          "preferred_duration_seconds" => 300,
          "minimum_data_volume_bytes" => nil,
          "contact_count" => 1,
          "minimum_separation_seconds" => 0,
          "priority" => "routine",
          "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
          "station_constraints_document" => %{"allowed" => [], "excluded" => []},
          "policy_constraints_document" => %{},
          "approval_policy_document" => %{"mode" => "manual"},
          "rationale" => "Targeted template test",
          "metadata" => %{}
        },
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 10,
          "maximum_lookback_seconds" => 86_400
        }
      },
      overrides
    )
  end

  defp scope(organization) do
    user =
      User.new(%{
        user_id: "targeted-template-admin",
        email: "targeted-template-admin@example.test",
        display_name: "Targeted Admin"
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user.user_id,
          organization_id: organization.organization_id,
          role: :organization_admin
        })
    })
  end
end
