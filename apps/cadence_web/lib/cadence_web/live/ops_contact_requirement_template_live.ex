defmodule CadenceWeb.OpsContactRequirementTemplateLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.ContactRequirementTemplates

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    form =
      to_form(
        %{
          "spacecraft_id" => "",
          "schedule_type" => "fixed_interval",
          "anchor_at" => datetime_local(now),
          "time_utc" => Calendar.strftime(now, "%H:%M:%S"),
          "interval_minutes" => "360",
          "window_offset_minutes" => "0",
          "window_duration_minutes" => "30",
          "contact_intent" => "payload_downlink",
          "success_measure" => "minimum_duration",
          "minimum_duration_seconds" => "600",
          "preferred_duration_seconds" => "900",
          "minimum_data_volume_bytes" => "",
          "contact_count" => "1",
          "minimum_separation_seconds" => "0",
          "priority" => "high",
          "approval_mode" => "manual",
          "maximum_occurrences_per_run" => "100",
          "maximum_lookback_hours" => "168",
          "rationale" => ""
        },
        as: :template
      )

    socket =
      socket
      |> assign(:page_title, "Recurring Contact Needs")
      |> assign(:ops_nav_item, :planning)
      |> assign(:organization_admin?, organization_admin?(socket.assigns.current_scope))
      |> assign(:form, form)
      |> stream_configure(:templates, dom_id: &"requirement-template-#{&1.id}")
      |> load_templates()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate-template", %{"template" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :template))}
  end

  def handle_event("create-template", %{"template" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, attrs} <- template_attrs(params),
         {:ok, _template, _version} <-
           ContactRequirementTemplates.create(scope, mission.mission_id, attrs) do
      {:noreply,
       socket
       |> load_templates()
       |> put_flash(:info, "Recurring Requirement Template activated.")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_event("pause-template", %{"id" => template_id}, socket) do
    transition_template(socket, template_id, :pause)
  end

  def handle_event("activate-template", %{"id" => template_id}, socket) do
    transition_template(socket, template_id, :activate)
  end

  def handle_event("close-template", %{"id" => template_id}, socket) do
    transition_template(socket, template_id, :close)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-requirement-templates-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-[100rem]">
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning"}
              class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
            >
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Fleet planning
            </.link>
            <div class="mt-4">
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
                Recurring demand definition
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">Requirement Templates</h1>
              <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                Define a UTC recurrence once. Each due occurrence materializes exactly one ordinary Contact Requirement with immutable provenance.
              </p>
            </div>
          </div>
        </header>

        <div class="mx-auto grid max-w-[100rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.15fr)_minmax(26rem,0.85fr)] lg:p-7">
          <section class="min-w-0 border border-base-300 bg-base-200/15">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <div>
                <p class="hud-label">Template ledger</p>
                <p class="mt-1 text-sm text-base-content/55">Lifecycle and current immutable schedule version.</p>
              </div>
              <span class="font-mono text-xs text-base-content/45">{@template_count}</span>
            </div>

            <div :if={@template_empty?} id="requirement-templates-empty" class="px-6 py-16 text-center">
              <.icon name="hero-arrow-path-rounded-square" class="mx-auto h-8 w-8 text-primary/35" />
              <h2 class="mt-4 text-base font-semibold">No recurring contact needs</h2>
              <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/55">
                Use a template for routine downlinks. One-off operational needs remain ordinary Requirements.
              </p>
            </div>

            <div id="requirement-templates" phx-update="stream">
              <div id="requirement-templates-stream-empty" class="hidden only:block"></div>
              <div
                :for={{dom_id, item} <- @streams.templates}
                id={dom_id}
                class="border-b border-base-300 p-4 last:border-b-0"
              >
                <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class={template_state_class(item.template.lifecycle_state)}>
                        {item.template.lifecycle_state}
                      </span>
                      <span class="font-mono text-[0.6rem] text-base-content/40">
                        v{item.version.version}
                      </span>
                    </div>
                    <h2 class="mt-2 truncate text-sm font-semibold">
                      {item.version.spacecraft_id} · {humanize(item.version.requirement_document["contact_intent"])}
                    </h2>
                    <p class="mt-1 text-xs text-base-content/55">
                      {schedule_sentence(item.version.schedule_document)}
                    </p>
                    <p class="mt-2 break-all font-mono text-[0.56rem] text-base-content/35">
                      {item.version.content_sha256}
                    </p>
                  </div>
                  <div :if={@organization_admin?} class="flex shrink-0 gap-2">
                    <button
                      :if={item.template.lifecycle_state == :active}
                      id={"pause-template-#{item.id}"}
                      type="button"
                      phx-click="pause-template"
                      phx-value-id={item.id}
                      class="btn btn-ghost btn-xs"
                    >
                      Pause
                    </button>
                    <button
                      :if={item.template.lifecycle_state == :paused}
                      id={"activate-template-#{item.id}"}
                      type="button"
                      phx-click="activate-template"
                      phx-value-id={item.id}
                      class="btn btn-ghost btn-xs text-success"
                    >
                      Activate
                    </button>
                    <button
                      :if={item.template.lifecycle_state != :closed}
                      id={"close-template-#{item.id}"}
                      type="button"
                      phx-click="close-template"
                      phx-value-id={item.id}
                      class="btn btn-ghost btn-xs text-error"
                    >
                      Close
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <aside class="min-w-0">
            <section
              :if={@organization_admin?}
              id="requirement-template-editor"
              class="border border-base-300 bg-base-200/15"
            >
              <div class="border-b border-base-300 px-4 py-3">
                <p class="hud-label">Create recurring need</p>
                <p class="mt-1 text-xs text-base-content/50">UTC schedule → ordinary Requirements</p>
              </div>
              <.form
                for={@form}
                id="requirement-template-form"
                phx-change="validate-template"
                phx-submit="create-template"
                class="space-y-5 p-4"
              >
                <.input
                  id="template-spacecraft"
                  field={@form[:spacecraft_id]}
                  type="select"
                  label="Spacecraft"
                  options={[{"Choose spacecraft", ""} | @spacecraft_options]}
                  required
                />

                <div>
                  <p class="hud-label">Recurrence</p>
                  <div class="mt-3 grid gap-3 sm:grid-cols-2">
                    <.input
                      id="template-schedule-type"
                      field={@form[:schedule_type]}
                      type="select"
                      label="Schedule"
                      options={[{"Fixed interval", "fixed_interval"}, {"Daily UTC", "daily"}]}
                    />
                    <.input id="template-anchor-at" field={@form[:anchor_at]} type="datetime-local" label="Starts (UTC)" required />
                    <.input
                      :if={@form[:schedule_type].value == "fixed_interval"}
                      id="template-interval-minutes"
                      field={@form[:interval_minutes]}
                      type="number"
                      min="1"
                      label="Every minutes"
                      required
                    />
                    <.input
                      :if={@form[:schedule_type].value == "daily"}
                      id="template-time-utc"
                      field={@form[:time_utc]}
                      type="time"
                      step="1"
                      label="Daily at UTC"
                      required
                    />
                    <.input id="template-window-offset" field={@form[:window_offset_minutes]} type="number" label="Window offset minutes" required />
                    <.input id="template-window-duration" field={@form[:window_duration_minutes]} type="number" min="1" label="Window duration minutes" required />
                  </div>
                </div>

                <div>
                  <p class="hud-label">Mission outcome</p>
                  <div class="mt-3 grid gap-3 sm:grid-cols-2">
                    <.input id="template-contact-intent" field={@form[:contact_intent]} type="text" label="Contact intent" required />
                    <.input
                      id="template-success-measure"
                      field={@form[:success_measure]}
                      type="select"
                      label="Success measure"
                      options={[
                        {"Minimum duration", "minimum_duration"},
                        {"Minimum data volume", "minimum_data_volume"},
                        {"Contact count", "contact_count"},
                        {"Any eligible", "any_eligible"}
                      ]}
                    />
                    <.input
                      :if={@form[:success_measure].value in ["minimum_duration", "minimum_data_volume"]}
                      id="template-minimum-duration"
                      field={@form[:minimum_duration_seconds]}
                      type="number"
                      min="1"
                      label="Minimum seconds"
                    />
                    <.input
                      :if={@form[:success_measure].value == "minimum_data_volume"}
                      id="template-minimum-data-volume"
                      field={@form[:minimum_data_volume_bytes]}
                      type="number"
                      min="1"
                      label="Minimum bytes"
                    />
                    <.input id="template-contact-count" field={@form[:contact_count]} type="number" min="1" label="Contact count" required />
                    <.input
                      id="template-priority"
                      field={@form[:priority]}
                      type="select"
                      label="Priority"
                      options={[{"Critical", "critical"}, {"High", "high"}, {"Normal", "normal"}, {"Low", "low"}]}
                    />
                    <.input
                      id="template-approval-mode"
                      field={@form[:approval_mode]}
                      type="select"
                      label="Approval"
                      options={[{"Manual", "manual"}, {"Bounded automatic", "bounded_automatic"}]}
                    />
                  </div>
                </div>

                <details id="requirement-template-outcome-details" class="border border-base-300">
                  <summary class="cursor-pointer px-3 py-2 text-xs font-semibold">
                    Duration and separation preferences
                  </summary>
                  <div class="grid gap-3 border-t border-base-300 p-3 sm:grid-cols-2">
                    <.input id="template-preferred-duration" field={@form[:preferred_duration_seconds]} type="number" min="1" label="Preferred seconds" />
                    <.input id="template-minimum-separation" field={@form[:minimum_separation_seconds]} type="number" min="0" label="Separation seconds" required />
                  </div>
                </details>

                <details id="requirement-template-catchup" class="border border-base-300">
                  <summary class="cursor-pointer px-3 py-2 text-xs font-semibold">
                    Catch-up guardrails
                  </summary>
                  <div class="grid gap-3 border-t border-base-300 p-3 sm:grid-cols-2">
                    <.input id="template-max-occurrences" field={@form[:maximum_occurrences_per_run]} type="number" min="1" label="Max per run" required />
                    <.input id="template-max-lookback" field={@form[:maximum_lookback_hours]} type="number" min="0" label="Lookback hours" required />
                  </div>
                </details>

                <.input id="template-rationale" field={@form[:rationale]} type="textarea" label="Operational rationale" required />

                <button id="create-requirement-template" type="submit" class="btn btn-primary btn-sm w-full">
                  Activate template
                </button>
              </.form>
            </section>

            <p
              :if={not @organization_admin?}
              id="requirement-template-admin-required"
              class="border-l-2 border-warning px-3 text-xs text-warning"
            >
              Organization administrator authority is required to manage recurring demand.
            </p>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_templates(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    rows =
      scope.organization_id
      |> ContactRequirementTemplates.list(mission.mission_id)
      |> Enum.map(fn {template, version} ->
        %{
          id: template.contact_requirement_template_id,
          template: template,
          version: version
        }
      end)

    spacecraft_options =
      scope.organization_id
      |> Cadence.SpacecraftStore.list_spacecraft(mission.mission_id)
      |> Enum.map(&{&1.display_name, &1.spacecraft_id})

    socket
    |> assign(:template_count, length(rows))
    |> assign(:template_empty?, rows == [])
    |> assign(:template_rows, rows)
    |> assign(:spacecraft_options, spacecraft_options)
    |> stream(:templates, rows, reset: true)
  end

  defp transition_template(socket, template_id, action) do
    %{current_scope: scope, current_mission: mission, template_rows: rows} = socket.assigns

    case Enum.find(rows, &(&1.id == template_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found.")}

      item ->
        result =
          case action do
            :pause ->
              ContactRequirementTemplates.pause(
                scope,
                mission.mission_id,
                template_id,
                item.template.current_version,
                "Paused from recurring demand workspace"
              )

            :activate ->
              ContactRequirementTemplates.activate(
                scope,
                mission.mission_id,
                template_id,
                item.template.current_version,
                "Reactivated from recurring demand workspace"
              )

            :close ->
              ContactRequirementTemplates.close(
                scope,
                mission.mission_id,
                template_id,
                item.template.current_version,
                "Closed from recurring demand workspace"
              )
          end

        case result do
          {:ok, _template} ->
            {:noreply,
             socket
             |> load_templates()
             |> put_flash(:info, "Template lifecycle updated.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, action_error(reason))}
        end
    end
  end

  defp template_attrs(params) do
    with {:ok, anchor} <- parse_datetime(params["anchor_at"]),
         {:ok, window_offset_minutes} <- integer(params["window_offset_minutes"]),
         {:ok, window_duration_minutes} <- positive_integer(params["window_duration_minutes"]),
         {:ok, minimum_duration} <- optional_positive_integer(params["minimum_duration_seconds"]),
         {:ok, preferred_duration} <-
           optional_positive_integer(params["preferred_duration_seconds"]),
         {:ok, minimum_volume} <- optional_positive_integer(params["minimum_data_volume_bytes"]),
         {:ok, contact_count} <- positive_integer(params["contact_count"]),
         {:ok, separation} <- non_negative_integer(params["minimum_separation_seconds"]),
         {:ok, maximum_occurrences} <- positive_integer(params["maximum_occurrences_per_run"]),
         {:ok, lookback_hours} <- non_negative_integer(params["maximum_lookback_hours"]),
         {:ok, schedule} <-
           schedule_document(
             params,
             anchor,
             window_offset_minutes,
             window_duration_minutes
           ) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         schedule_document: schedule,
         requirement_document: %{
           "service_direction" => "downlink",
           "contact_intent" => params["contact_intent"],
           "success_measure" => params["success_measure"],
           "minimum_duration_seconds" => minimum_duration,
           "preferred_duration_seconds" => preferred_duration,
           "minimum_data_volume_bytes" => minimum_volume,
           "contact_count" => contact_count,
           "minimum_separation_seconds" => separation,
           "priority" => params["priority"],
           "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
           "station_constraints_document" => %{"allowed" => [], "excluded" => []},
           "policy_constraints_document" => %{},
           "approval_policy_document" => %{"mode" => params["approval_mode"]},
           "rationale" => params["rationale"],
           "metadata" => %{}
         },
         catch_up_policy_document: %{
           "maximum_occurrences_per_run" => maximum_occurrences,
           "maximum_lookback_seconds" => lookback_hours * 3_600
         }
       }}
    else
      {:error, _reason} -> {:error, :invalid_requirement_template_form}
    end
  end

  defp schedule_document(params, anchor, offset_minutes, duration_minutes) do
    base = %{
      "type" => params["schedule_type"],
      "anchor_at" => DateTime.to_iso8601(anchor),
      "ends_at" => nil,
      "window_offset_seconds" => offset_minutes * 60,
      "window_duration_seconds" => duration_minutes * 60
    }

    case params["schedule_type"] do
      "fixed_interval" ->
        with {:ok, interval_minutes} <- positive_integer(params["interval_minutes"]) do
          {:ok, Map.put(base, "interval_seconds", interval_minutes * 60)}
        end

      "daily" ->
        case Time.from_iso8601(params["time_utc"] || "") do
          {:ok, time} -> {:ok, Map.put(base, "time_utc", Time.to_iso8601(time))}
          {:error, _reason} -> {:error, :invalid_daily_time}
        end

      _other ->
        {:error, :invalid_schedule_type}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      {:error, _reason} -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_datetime}

  defp integer(value) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, :invalid_integer}
    end
  end

  defp positive_integer(value) do
    with {:ok, integer} <- integer(value),
         true <- integer > 0 do
      {:ok, integer}
    else
      _reason -> {:error, :invalid_positive_integer}
    end
  end

  defp non_negative_integer(value) do
    with {:ok, integer} <- integer(value),
         true <- integer >= 0 do
      {:ok, integer}
    else
      _reason -> {:error, :invalid_non_negative_integer}
    end
  end

  defp optional_positive_integer(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_positive_integer(value), do: positive_integer(value)

  defp schedule_sentence(%{"type" => "fixed_interval"} = schedule) do
    "Every #{div(schedule["interval_seconds"], 60)} min · #{div(schedule["window_duration_seconds"], 60)} min window"
  end

  defp schedule_sentence(%{"type" => "daily"} = schedule) do
    "Daily at #{schedule["time_utc"]} · #{div(schedule["window_duration_seconds"], 60)} min window"
  end

  defp organization_admin?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end

  defp template_state_class(:active),
    do:
      "border border-success/35 bg-success/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-success"

  defp template_state_class(:paused),
    do:
      "border border-warning/35 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-warning"

  defp template_state_class(_state),
    do:
      "border border-base-300 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-base-content/45"

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")
  defp action_error(:forbidden), do: "Organization administrator authority is required."
  defp action_error(:invalid_requirement_template_form), do: "Review the schedule and outcome."
  defp action_error(_reason), do: "The recurring Requirement Template could not be changed."
end
