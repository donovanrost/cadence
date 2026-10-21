defmodule Cadence.Dev.ReflectOrbital.Dashboards do
  @moduledoc "Saved, native telemetry dashboards for the Earendil rehearsal."
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F

  alias Cadence.Dashboards.{
    CurrentVersions,
    Document,
    Documents,
    Management,
    Placement,
    Section,
    WidgetDef
  }

  def run(opts \\ []) do
    discover_history_capabilities()
    documents = Enum.map(definitions(), &save(&1, Keyword.get(opts, :replace?, false)))
    name = "Earendil — Demo Rotation"

    playlist =
      Enum.find(
        Management.list_playlists(F.organization_id(), F.mission_id()),
        &(&1.name == name)
      ) ||
        case Management.create_playlist(
               F.organization_id(),
               F.mission_id(),
               %{
                 name: name,
                 description: "Six live telemetry views for the ten-spacecraft rehearsal.",
                 dashboard_ids: Enum.map(documents, & &1.dashboard_id),
                 dwell_seconds: 30,
                 wallboard_mode: true
               },
               created_by: "user_environment_admin"
             ) do
          {:ok, created} -> created
          error -> raise "Playlist failed: #{inspect(error)}"
        end

    %{
      dashboards: Enum.map(documents, &%{id: &1.dashboard_id, name: &1.name}),
      playlist: playlist.dashboard_playlist_id
    }
  end

  def definitions do
    [fleet(), overview(), power(), thermal(), attitude(), communications()]
  end

  defp discover_history_capabilities do
    attrs = %{
      organization_id: F.organization_id(),
      mission_id: F.mission_id(),
      logical_source: :telemetry,
      realm: :flight,
      source_binding_id: "default_flight_telemetry"
    }

    with {:ok, prepared} <-
           Cadence.Control.DataSources.prepare_probe("managed_questdb_primary", attrs,
             questdb_probe?: true,
             materialize_adapter_capabilities?: true,
             actor_id: "user_environment_admin"
           ),
         %{source_health: :healthy, reason: :source_probe_succeeded} = probe <-
           Cadence.Control.DataSources.observe_probe(prepared),
         {:ok, _, _} <- Cadence.Control.DataSources.persist_probe(prepared, probe) do
      for invalidate <- [:invalidate_plans, :invalidate_source_results, :invalidate_frames] do
        apply(Cadence.Dashboards.RuntimeCache, invalidate, [[mission_id: F.mission_id()]])
      end

      :ok
    else
      error -> raise "QuestDB must be healthy for the rehearsal: #{inspect(error, limit: 10)}"
    end
  end

  defp fleet do
    trends =
      F.spacecraft()
      |> Enum.take(10)
      |> Enum.with_index()
      |> Enum.map(fn {spacecraft, index} ->
        number = (index + 1) |> Integer.to_string() |> String.pad_leading(3, "0")
        scope = %{primary: %{kind: :spacecraft, mode: :one, ids: [spacecraft.spacecraft_id]}}

        widget(
          "fleet-battery-#{number}",
          "cadence.time_series",
          "EARENDIL-#{number} · Battery Charge",
          ["EPS.batt_soc"],
          {rem(index, 3) * 4, div(index, 3) * 4, 4, 4},
          :decimated_envelope,
          scope
        )
      end)

    document(
      "fleet",
      "Fleet Watch",
      "Ten live vehicles in a 500-spacecraft constellation. Each chart follows one spacecraft at 1 Hz.",
      trends,
      %{primary: %{kind: :mission, mode: :context}}
    )
  end

  defp overview do
    document(
      "overview",
      "Spacecraft Overview",
      "A quick health check for the selected spacecraft. EARENDIL-001 through 010 have live rehearsal telemetry.",
      [
        tile("mode", "Spacecraft Mode", "HK.sc_mode", 0, 0, 0),
        tile("charge", "Battery Charge", "EPS.batt_soc", 3, 0, 1),
        tile("temperature", "Battery Temperature", "THERM.temp_battery", 6, 0, 1),
        tile("link", "Link State", "COMM.link_state", 9, 0, 0),
        chart("voltage", "Battery Voltage", ["EPS.batt_voltage"], 0, 2),
        chart(
          "temperatures",
          "Subsystem Temperatures",
          ["THERM.temp_obc", "THERM.temp_battery", "THERM.temp_payload"],
          6,
          2
        ),
        chart("attitude", "Pointing Angles", ["ADCS.roll", "ADCS.pitch", "ADCS.yaw"], 0, 6),
        chart("radio", "Receive Signal-to-Noise Ratio", ["COMM.rx_snr"], 6, 6)
      ]
    )
  end

  defp power do
    document(
      "power",
      "Electrical Power",
      "Battery, solar arrays and regulated buses for the selected demo spacecraft.",
      [
        tile("soc", "State of Charge", "EPS.batt_soc", 0, 0, 1),
        tile("voltage", "Battery Voltage", "EPS.batt_voltage", 3, 0, 2),
        tile("current", "Battery Current", "EPS.batt_current", 6, 0, 2),
        tile("power", "Total Power", "EPS.total_power", 9, 0, 1),
        chart("battery", "Battery Voltage", ["EPS.batt_voltage"], 0, 2),
        chart("charge", "Battery State of Charge", ["EPS.batt_soc"], 6, 2),
        chart("solar", "Solar Array Current", ["EPS.sa1_current", "EPS.sa2_current"], 0, 6),
        chart(
          "buses",
          "Regulated Bus Voltages",
          ["EPS.bus_3v3", "EPS.bus_5v", "EPS.bus_12v"],
          6,
          6
        ),
        matrix("state", "Power State", ["EPS.eps_mode", "EPS.eclipse_flag", "EPS.batt_temp"], 10)
      ]
    )
  end

  defp thermal do
    document(
      "thermal",
      "Thermal Control",
      "Temperatures, heaters and thermal mode from the demo spacecraft database.",
      [
        tile("obc", "Flight Computer", "THERM.temp_obc", 0, 0, 1),
        tile("battery", "Battery", "THERM.temp_battery", 3, 0, 1),
        tile("payload", "Payload", "THERM.temp_payload", 6, 0, 1),
        tile("heater", "Heater Power", "THERM.heater_power_total", 9, 0, 1),
        chart(
          "bus",
          "Internal Temperatures",
          ["THERM.temp_obc", "THERM.temp_battery", "THERM.temp_payload"],
          0,
          2
        ),
        chart(
          "panels",
          "Solar Panel Temperatures",
          ["THERM.temp_solar_panel_1", "THERM.temp_solar_panel_2"],
          6,
          2
        ),
        matrix(
          "control",
          "Thermal Control State",
          ["THERM.thermal_mode", "THERM.heater_1_state", "THERM.heater_2_state"],
          6
        )
      ]
    )
  end

  defp attitude do
    document(
      "attitude",
      "Attitude & Pointing",
      "Attitude, body rates and reaction wheels. Values are synthetic bus telemetry, not a reflector pointing solution.",
      [
        tile("mode", "ADCS Mode", "ADCS.adcs_mode", 0, 0, 0),
        tile("roll", "Roll", "ADCS.roll", 3, 0, 2),
        tile("pitch", "Pitch", "ADCS.pitch", 6, 0, 2),
        tile("yaw", "Yaw", "ADCS.yaw", 9, 0, 2),
        chart("pointing", "Attitude Angles", ["ADCS.roll", "ADCS.pitch", "ADCS.yaw"], 0, 2),
        chart(
          "rates",
          "Body Rates",
          ["ADCS.roll_rate", "ADCS.pitch_rate", "ADCS.yaw_rate"],
          6,
          2
        ),
        chart(
          "wheels",
          "Reaction Wheel Speeds",
          ["ADCS.rw1_speed", "ADCS.rw2_speed", "ADCS.rw3_speed"],
          0,
          6
        ),
        chart(
          "quaternion",
          "Attitude Quaternion",
          ["ADCS.q_w", "ADCS.q_x", "ADCS.q_y", "ADCS.q_z"],
          6,
          6
        )
      ]
    )
  end

  defp communications do
    document(
      "comms-payload",
      "Communications & Payload",
      "Radio link quality and the generic demo payload. This is not a Reflect Orbital flight payload model.",
      [
        tile("link", "Link State", "COMM.link_state", 0, 0, 0),
        tile("snr", "Receive SNR", "COMM.rx_snr", 3, 0, 1),
        tile("payload", "Payload State", "PAYLOAD.state", 6, 0, 0),
        tile("power", "Payload Power", "PAYLOAD.power_draw", 9, 0, 1),
        chart("rssi", "Receive Signal Strength", ["COMM.rx_rssi"], 0, 2),
        chart("tx", "Transmit Power", ["COMM.tx_power"], 6, 2),
        chart("temperature", "Payload Detector Temperature", ["PAYLOAD.detector_temp"], 0, 6),
        chart("data", "Payload Data Collected", ["PAYLOAD.data_collected"], 6, 6),
        matrix(
          "counters",
          "Command & Packet Counters",
          [
            "HK.cmd_recv_count",
            "HK.cmd_exec_count",
            "HK.cmd_reject_count",
            "COMM.packets_tx",
            "COMM.packets_rx",
            "COMM.packets_err"
          ],
          10
        )
      ]
    )
  end

  defp document(
         key,
         title,
         description,
         placements,
         scope \\ %{primary: %{kind: :spacecraft, mode: :one, ids: ["spacecraft-earendil-001"]}}
       ) do
    %Document{
      dashboard_id: "dashboard-earendil-#{key}",
      organization_id: F.organization_id(),
      mission_id: F.mission_id(),
      name: "Earendil — #{title}",
      description: description,
      defaults: %{
        time: %{mode: :live, axis: :receipt_time, refresh_ms: 1_000, window_seconds: 300},
        scope: scope,
        data: %{realm: :flight, source_mode: :primary, allowed_realms: [:flight]},
        limits: %{semantics_mode: :observed, limit_set_name: "DEFAULT"}
      },
      sections: [
        %Section{
          section_id: "telemetry",
          title: "Live Telemetry",
          description: "Local simulation · 1 Hz per packet family · five-minute trends"
        }
      ],
      placements: placements,
      metadata: %{
        tags: ["earendil", "reflect-orbital-demo", "live-telemetry", key],
        fixture: "earendil-dashboards-v1",
        synthetic: true
      }
    }
  end

  defp tile(id, title, observable, x, y, precision) do
    placement = widget(id, "cadence.value_tile", title, [observable], {x, y, 3, 2}, :latest)
    put_in(placement.widget_def.options, %{precision: precision})
  end

  defp chart(id, title, observables, x, y),
    do: widget(id, "cadence.time_series", title, observables, {x, y, 6, 4}, :decimated_envelope)

  defp matrix(id, title, observables, y),
    do: widget(id, "cadence.status_matrix", title, observables, {0, y, 12, 3}, :latest)

  defp widget(id, type, title, observables, {x, y, w, h}, sampling, scope \\ nil) do
    operations? = scope == :operations
    override? = is_map(scope)

    %Placement{
      placement_id: id,
      section_id: "telemetry",
      layout: %{x: x, y: y, w: w, h: h},
      scope_override: if(override?, do: scope, else: nil),
      widget_def: %WidgetDef{
        widget_type_id: type,
        widget_type_version: 1,
        title: title,
        binding: %{
          source: if(operations?, do: :operational_observables, else: :telemetry),
          observables: observables,
          scope_mode: if(override?, do: :override, else: :context),
          data_mode: :context,
          value_type: :engineering,
          sampling: sampling,
          overlays: []
        },
        options:
          if(type == "cadence.time_series",
            do: %{legend: true, legend_mode: "always", shared_tooltip: true, window_seconds: 300},
            else: %{}
          )
      }
    }
  end

  defp save(document, replace?) do
    result =
      case Documents.fetch(F.organization_id(), F.mission_id(), document.dashboard_id) do
        {:error, :dashboard_not_found} ->
          CurrentVersions.create(F.organization_id(), document,
            created_by: "user_environment_admin"
          )

        {:ok, existing} when not replace? ->
          {:ok, existing}

        {:ok, existing} ->
          CurrentVersions.save(
            F.organization_id(),
            F.mission_id(),
            document.dashboard_id,
            document,
            expected_version: Document.version(existing),
            created_by: "user_environment_admin",
            change_summary: "Refresh Earendil demo dashboard"
          )
      end

    case result do
      {:ok, saved} -> saved
      error -> raise "#{document.name}: #{inspect(error, limit: 30)}"
    end
  end
end
