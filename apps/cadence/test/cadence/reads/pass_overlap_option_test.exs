defmodule Cadence.Reads.PassOverlapOptionTest do
  @moduledoc """
  #1051: reading a mission's passes decorates each with its listener overlap, which resolves the
  paths (path templates, provider and transport profiles) of every booked contact around the
  window. A group's preflight and the uplink on its show only need windows and refs, so they ask
  for `overlap: false` and read none of those tables, whatever the mission has booked.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, PathTemplate, ProviderBinding, ProviderProfile, ScheduledContact}
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.{CommandPreflight, Passes, PassUplink}

  @tables ~r/contact_(provider_profiles|path_templates|transport_profiles)/

  setup do
    c = setup!(3)
    [first, second, third] = c.spacecraft
    starts = DateTime.add(DateTime.utc_now(), 1_800)

    # Two booked passes on one listener at the same time (the second loses its start to the first),
    # and a third elsewhere in time; each contact resolves its path through the one template.
    template = template!(c, first)
    one = commandable_pass!(c.org, c.mission, first, starts)
    two = commandable_pass!(c.org, c.mission, second, starts)
    commandable_pass!(c.org, c.mission, third, DateTime.add(starts, 7_200))
    for pass <- [one, two], do: book!(c, pass, template)

    Map.merge(c, %{overlapping: [one, two] |> Enum.map(& &1.scheduled_contact_id)})
  end

  defp template!(c, craft) do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, profile} =
      Contacts.persist_provider_profile(
        c.org,
        ProviderProfile.new(%{
          provider_profile_id: "listen-" <> suffix,
          mission_id: c.mission,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
            "port" => 46_105,
            "ingress_protocol_family" => "tm",
            "frame_size" => 10
          }
        })
      )

    {:ok, template} =
      Contacts.persist_path_template(
        c.org,
        PathTemplate.new(%{
          path_template_id: "tpl-" <> suffix,
          mission_id: c.mission,
          path_id: "path-" <> suffix,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: Cadence.SourceEndpoints.managed_source_endpoint_id(craft),
          provider_profile_refs: [
            %{"provider_profile_id" => profile.provider_profile_id, "version" => profile.version}
          ]
        })
      )

    template
  end

  # The scheduled contact behind a booked pass, resolving its paths through the template.
  defp book!(c, pass, template) do
    {:ok, _} =
      Contacts.persist_scheduled_contact(
        c.org,
        ScheduledContact.new(%{
          scheduled_contact_id: pass.scheduled_contact_id,
          mission_id: c.mission,
          source_endpoint_refs: [template.source_endpoint_ref],
          path_template_ids: [template.path_template_id],
          contact_intents: [:command_window],
          # A command window needs a selected uplink path of its own.
          paths: [
            Path.new(%{
              path_id: "uplink-" <> pass.scheduled_contact_id,
              direction: :uplink,
              selection_role: :selected,
              source_endpoint_ref: template.source_endpoint_ref,
              provider_bindings: [
                ProviderBinding.new(%{
                  provider_binding_id: "uplink-binding",
                  adapter_key: :tcp_socket,
                  configuration: %{
                    mode: :connect,
                    host: "127.0.0.1",
                    port: 46_200,
                    uplink_resource_id: "uplink-" <> pass.scheduled_contact_id
                  }
                })
              ]
            })
          ],
          starts_at: pass.starts_at,
          ends_at: pass.ends_at
        })
      )
  end

  # The queries that touch the contact profile and template tables while `fun` runs.
  defp profile_reads(fun) do
    ref = make_ref()
    me = self()
    handler = "overlap-option-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, meta, _cfg ->
        if self() == me and Regex.match?(@tables, meta.query), do: send(me, {:read, ref})
      end,
      nil
    )

    try do
      result = fun.()
      {drain(ref, 0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, n) do
    receive do
      {:read, ^ref} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end

  defp window, do: {DateTime.utc_now(), DateTime.add(DateTime.utc_now(), 6 * 3_600)}

  test "the default read resolves the booked contacts' paths; overlap: false reads none", c do
    {from, until} = window()

    {with_overlap, %{passes: passes}} =
      profile_reads(fn -> Passes.load(c.org, c.mission, from, until, %{}) end)

    assert with_overlap > 0, "the control: the decoration reads the profile tables"

    # And the passes screen's read still carries the overlap: the two passes on one listener.
    flagged = for p <- passes, p.scheduled_contact_id in c.overlapping, do: p.listener_overlap
    assert length(flagged) == 2
    assert Enum.all?(flagged, &(is_map(&1) and &1.direction == "downlink"))

    {without, %{passes: skipped}} =
      profile_reads(fn -> Passes.load(c.org, c.mission, from, until, %{overlap: false}) end)

    assert without == 0
    assert Enum.map(skipped, & &1.id) == Enum.map(passes, & &1.id)
    assert Enum.all?(skipped, &is_nil(&1.listener_overlap))
  end

  test "preflight reads no contact profile or template", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {reads, {:ok, preflight}} =
      profile_reads(fn -> CommandPreflight.run(c.org, c.mission, actor(c), draft) end)

    assert reads == 0
    assert %{result: :go} = Enum.find(preflight.checks, &(&1.key == :contact))
  end

  test "a group's uplink on its show reads no contact profile or template", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {reads, uplink} =
      profile_reads(fn -> PassUplink.for_groups(c.org, c.mission, [group.command_group_id]) end)

    # (It does read passes: the group's targets' next contacts are in the answer.)
    assert %{pass: %{reservation_id: _, booked: true}} = uplink[group.command_group_id]
    assert reads == 0
  end
end
