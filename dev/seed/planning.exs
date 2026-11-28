defmodule QaRestPlanning do
  @moduledoc "Seeds the Earendil planning draft and recurring downlink templates over REST."

  import EarendilRestClient, only: [request!: 3, request!: 4]

  @anchor "2026-01-01T00:00:00Z"
  @minimum_duration 300

  def seed(client, approver, mission_id) do
    path = "/missions/#{mission_id}/contact-planning"
    {client, policy} = request!(client, :get, path <> "/policy")

    client =
      if policy["version"] do
        client
      else
        {client, _} =
          request!(client, :post, path <> "/policy", %{
            document: policy_document(),
            reason: "Earendil demo planning boundary"
          })

        client
      end

    {client, policy} = request!(client, :get, path <> "/policy")

    if policy["pending"] do
      {_, result} =
        request!(approver, :post, path <> "/policy/#{policy["pending"]["version"]}/decision", %{
          decision: "approve",
          comment: "Seed Earendil planning policy"
        })

      unless result["state"] == "active", do: raise("planning policy approval failed")
    end

    count = planning_count!()
    {client, fleet} = request!(client, :get, "/missions/#{mission_id}/spacecraft")

    spacecraft =
      fleet["spacecraft"]
      |> Enum.sort_by(& &1["scid"])
      |> Enum.take(count)

    {client, listed} = request!(client, :get, path <> "/templates")

    client =
      Enum.reduce(spacecraft, client, fn craft, client ->
        seed_template(client, path, craft["id"], craft["name"], listed["templates"])
      end)

    if spacecraft == [],
      do: IO.puts("  planning templates wait on an applied Earendil fleet")

    IO.puts("  active planning policy and #{length(spacecraft)} recurring templates present")
    client
  end

  defp seed_template(client, path, spacecraft_id, spacecraft_name, templates) do
    existing =
      Enum.find(templates, fn template ->
        template["target"] == %{
          "kind" => "spacecraft_ids",
          "spacecraft_ids" => [spacecraft_id]
        }
      end)

    if existing do
      update_template(client, path, existing["id"], spacecraft_name)
    else
      {client, _} =
        request!(client, :post, path <> "/templates", %{
          name: "Earendil downlink #{spacecraft_name}",
          target: %{kind: "spacecraft_ids", spacecraft_ids: [spacecraft_id]},
          document: template_document(),
          operation_id: "earendil-downlink-#{spacecraft_id}"
        })

      client
    end
  end

  defp update_template(client, path, template_id, spacecraft_name) do
    {client, detail} = request!(client, :get, path <> "/templates/#{template_id}")

    name = "Earendil downlink #{spacecraft_name}"

    if detail["name"] == name and
         get_in(detail, ["document", "requirement", "minimum_duration_seconds"]) ==
           @minimum_duration do
      client
    else
      {client, _} =
        request!(client, :post, path <> "/templates/#{template_id}", %{
          name: name,
          document: template_document(),
          expected_version: detail["version"]
        })

      client
    end
  end

  defp planning_count! do
    case Integer.parse(System.get_env("EARENDIL_PLANNING_SPACECRAFT", "10")) do
      {count, ""} when count >= 1 -> count
      _ -> raise "EARENDIL_PLANNING_SPACECRAFT must be a positive integer"
    end
  end

  defp template_document do
    %{
      schedule: %{
        type: "fixed_interval",
        anchor_at: @anchor,
        interval_seconds: 21_600,
        window_offset_seconds: 0,
        window_duration_seconds: 21_600
      },
      requirement: %{
        service_direction: "downlink",
        contact_intent: "recurring_payload_downlink",
        success_measure: "minimum_duration",
        minimum_duration_seconds: @minimum_duration,
        preferred_duration_seconds: @minimum_duration,
        minimum_data_volume_bytes: nil,
        contact_count: 1,
        minimum_separation_seconds: 0,
        priority: "routine",
        provider_constraints_document: %{allowed: [], excluded: []},
        station_constraints_document: %{allowed: [], excluded: []},
        policy_constraints_document: %{},
        approval_policy_document: %{mode: "manual"},
        rationale: "Earendil demo: drain the payload recorder every 6 h",
        metadata: %{"fixture" => "reflect-orbital-v1"}
      },
      catch_up_policy: %{maximum_occurrences_per_run: 8, maximum_lookback_seconds: 86_400}
    }
  end

  defp policy_document do
    %{
      horizon: %{
        max_horizon_seconds: 172_800,
        requirement_concurrency: 4,
        provider_search_concurrency: 2,
        reuse_freshness_seconds: 300
      },
      scoring: %{
        priority_weight: 2_000,
        deadline_weight: 1_000,
        scarcity_weight: 800,
        local_improvement_limit: 100,
        local_improvement_width: 2
      },
      resources: %{default_exclusive_capacity: 1, capacities: %{}},
      budgets: %{
        max_contacts: 1_000,
        max_estimated_cost_micros: nil,
        currency: nil,
        per_provider: %{},
        critical_contact_reserve: 0,
        critical_cost_reserve_micros: 0
      },
      redundancy: %{
        distinct_provider_required: false,
        distinct_station_required: false,
        distinct_service_pool_required: false
      },
      automation: %{
        mode: "advisory",
        execution_concurrency: 2,
        max_repair_attempts: 2,
        repair_horizon_seconds: 43_200,
        automatic_submission: false
      }
    }
  end
end
