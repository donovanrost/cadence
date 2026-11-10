defmodule Cadence.Contacts.BookedPathSelectionTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{ContactRuntimeConfig, PathTemplateStore, ScheduledContact}
  alias Cadence.ProviderChangeFixtures

  setup do
    c = ProviderChangeFixtures.setup_contact()
    [template_id] = c.reservation.path_template_ids
    {:ok, selected} = PathTemplateStore.fetch(c.organization_id, c.mission_id, template_id)

    {:ok, candidate} =
      PathTemplateStore.persist(c.organization_id, %{
        selected
        | path_template_id: "path-candidate-#{System.unique_integer([:positive])}",
          path_id: "fallback-station:downlink",
          selection_role: :candidate,
          version: 1
      })

    %{c: c, candidate: candidate}
  end

  test "a pass booked on a candidate route schedules with that path selected", %{c: c} = ctx do
    booked = scheduled(c, ctx.candidate, %{"provider_reservation_id" => "reservation-1"})

    assert {:ok, [%{path_id: "fallback-station:downlink", selection_role: :selected}]} =
             ContactRuntimeConfig.resolve_paths(booked)

    assert :ok = ContactRuntimeConfig.validate(booked)
  end

  test "a contact not booked through a provider keeps the route's role", %{c: c} = ctx do
    manual = scheduled(c, ctx.candidate, %{})

    assert {:ok, [%{selection_role: :candidate}]} = ContactRuntimeConfig.resolve_paths(manual)

    assert {:error, :scheduled_contact_requires_selected_path} =
             ContactRuntimeConfig.validate(manual)
  end

  test "#59: each booked pass gets its own uplink resource; a manual contact keeps the route's",
       %{c: c} do
    [template_id] = c.reservation.path_template_ids
    {:ok, template} = PathTemplateStore.fetch(c.organization_id, c.mission_id, template_id)
    [ref] = template.provider_profile_refs

    {:ok, profile} =
      Cadence.Contacts.fetch_provider_profile(
        c.organization_id,
        c.mission_id,
        ref["provider_profile_id"]
      )

    {:ok, uplink_profile} =
      Cadence.Contacts.persist_provider_profile(c.organization_id, %{
        profile
        | version: profile.version + 1,
          configuration:
            Map.put(profile.configuration, "uplink_resource_id", "uplink:127.0.0.1:7001")
      })

    {:ok, uplink_template} =
      PathTemplateStore.persist(c.organization_id, %{
        template
        | version: template.version + 1,
          provider_profile_refs: [
            %{
              "provider_profile_id" => uplink_profile.provider_profile_id,
              "version" => uplink_profile.version
            }
          ]
      })

    resource = fn contact ->
      {:ok, [path]} = ContactRuntimeConfig.resolve_paths(contact)
      [binding] = path.provider_bindings
      binding.configuration["uplink_resource_id"]
    end

    pass = fn ref ->
      %{
        scheduled(c, uplink_template, %{"provider_reservation_id" => "reservation-" <> ref})
        | provider_contact_ref: "contact-" <> ref
      }
    end

    assert resource.(pass.("a")) == "uplink:127.0.0.1:7001:pass:contact-a"
    assert resource.(pass.("b")) == "uplink:127.0.0.1:7001:pass:contact-b"
    assert resource.(scheduled(c, uplink_template, %{})) == "uplink:127.0.0.1:7001"
  end

  defp scheduled(c, template, metadata) do
    ScheduledContact.new(%{
      organization_id: c.organization_id,
      mission_id: c.mission_id,
      scheduled_contact_id: "scheduled-#{System.unique_integer([:positive])}",
      source_endpoint_refs: c.reservation.source_endpoint_refs,
      contact_intents: [:telemetry_downlink],
      path_template_ids: [template.path_template_id],
      path_template_refs: [
        %{"path_template_id" => template.path_template_id, "version" => template.version}
      ],
      starts_at: c.reservation.starts_at,
      ends_at: c.reservation.ends_at,
      metadata: metadata
    })
  end
end
