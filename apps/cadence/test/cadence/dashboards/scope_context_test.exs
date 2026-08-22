defmodule Cadence.Dashboards.ScopeContextTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.ScopeContext

  test "derives typed single scope ids from primary selectors" do
    assert %ScopeContext{} =
             context =
             ScopeContext.from_map(%{
               primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
             })

    assert context.spacecraft_id == "sc-1"
    assert ScopeContext.scope_id(context, :spacecraft) == "sc-1"
    assert ScopeContext.scope_ids(context, :spacecraft) == ["sc-1"]
    assert ScopeContext.primary_kind(context) == "spacecraft"
    assert ScopeContext.primary_ids(context) == ["sc-1"]

    assert %ScopeContext{} =
             contact_context =
             ScopeContext.from_map(%{
               "primary" => %{"kind" => "contact", "mode" => "one", "ids" => ["contact-1"]}
             })

    assert contact_context.contact_id == "contact-1"
    assert ScopeContext.scope_id(contact_context, :contact) == "contact-1"
    assert ScopeContext.scope_ids(contact_context, :contact) == ["contact-1"]
    assert ScopeContext.scope_id(contact_context, :spacecraft) == nil

    source_endpoint_context =
      ScopeContext.from_map(%{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["endpoint-1"]}
      })

    assert source_endpoint_context.source_endpoint_id == "endpoint-1"
    assert ScopeContext.scope_id(source_endpoint_context, :source_endpoint) == "endpoint-1"
    assert ScopeContext.scope_ids(source_endpoint_context, :source_endpoint) == ["endpoint-1"]
  end

  test "preserves explicit typed ids ahead of primary ids" do
    context =
      ScopeContext.from_map(%{
        spacecraft_id: "sc-explicit",
        primary: %{kind: :spacecraft, mode: :one, ids: ["sc-primary"]}
      })

    assert context.spacecraft_id == "sc-explicit"
    assert ScopeContext.scope_id(context, :spacecraft) == "sc-explicit"
    assert ScopeContext.scope_ids(context, :spacecraft) == ["sc-explicit", "sc-primary"]
  end

  test "does not derive a single id from multi-entity scope modes" do
    context =
      ScopeContext.from_map(%{
        primary: %{kind: "spacecraft", mode: "many", ids: ["sc-1", "sc-2"]}
      })

    assert context.spacecraft_id == nil
    assert ScopeContext.scope_id(context, :spacecraft) == nil
    assert ScopeContext.scope_ids(context, :spacecraft) == ["sc-1", "sc-2"]
    assert ScopeContext.primary_ids(context) == ["sc-1", "sc-2"]
  end

  test "preserves multi-entity runtime scope filters when primary scope is overridden" do
    runtime =
      ScopeContext.from_map(%{
        primary: %{kind: "contact", mode: "many", ids: ["contact-1", "contact-2"]}
      })

    placement_override =
      ScopeContext.from_map(%{
        primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
      })

    context = ScopeContext.resolve(runtime, nil, placement_override)

    assert ScopeContext.primary_kind(context) == "spacecraft"
    assert ScopeContext.scope_id(context, :spacecraft) == "sc-1"
    assert ScopeContext.scope_ids(context, :spacecraft) == ["sc-1"]
    assert ScopeContext.scope_id(context, :contact) == nil
    assert ScopeContext.scope_ids(context, :contact) == ["contact-1", "contact-2"]
  end
end
