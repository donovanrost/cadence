defmodule CadenceWeb.OpsContactRequirementNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.ContactRequirements

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    spacecraft =
      Cadence.SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)

    starts_at = DateTime.utc_now() |> DateTime.add(15 * 60, :second) |> DateTime.truncate(:second)

    form =
      to_form(
        %{
          "spacecraft_id" =>
            spacecraft |> List.first() |> then(&if(&1, do: &1.spacecraft_id, else: "")),
          "contact_intent" => "payload_downlink",
          "earliest_start" => datetime_local(starts_at),
          "latest_end" => starts_at |> DateTime.add(24 * 60 * 60, :second) |> datetime_local(),
          "success_measure" => "minimum_data_volume",
          "minimum_duration_seconds" => "600",
          "preferred_duration_seconds" => "900",
          "minimum_data_volume_bytes" => "1000000000",
          "contact_count" => "1",
          "minimum_separation_seconds" => "0",
          "priority" => "high",
          "allowed_providers" => "",
          "excluded_providers" => "",
          "allowed_stations" => "",
          "excluded_stations" => "",
          "rationale" => ""
        },
        as: :contact_requirement
      )

    {:ok,
     socket
     |> assign(:page_title, "Declare Contact Need")
     |> assign(:ops_nav_item, :requirements)
     |> assign(:spacecraft, spacecraft)
     |> assign(:form, form)
     |> assign(:form_error, nil)}
  end

  @impl true
  def handle_event("validate", %{"contact_requirement" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params, as: :contact_requirement))
     |> assign(:form_error, nil)}
  end

  def handle_event("save", %{"contact_requirement" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, attrs} <- requirement_attrs(params),
         {:ok, requirement, _version} <-
           ContactRequirements.create(scope, mission.mission_id, attrs) do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
       )}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :contact_requirement))
         |> assign(:form_error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-contact-requirement-new-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-5xl">
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/requirements"}
              class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
            >
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Requirements
            </.link>
            <p class="mt-4 font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
              Need / outcome-first declaration
            </p>
            <h1 class="mt-1 text-2xl font-bold tracking-tight">What does the mission need?</h1>
            <p class="mt-2 max-w-3xl text-sm text-base-content/60">
              Describe success and the acceptable horizon. Provider, station, and route choices remain planning concerns—not part of the need itself.
            </p>
          </div>
        </header>

        <div class="mx-auto max-w-5xl p-5 lg:p-7">
          <.form
            for={@form}
            id="contact-requirement-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-5"
          >
            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-5 py-3">
                <p class="hud-label">01 / Mission outcome</p>
                <p class="mt-1 text-sm text-base-content/55">The operator-readable reason this contact must exist.</p>
              </div>
              <div class="grid gap-x-5 p-5 md:grid-cols-2">
                <.input
                  id="requirement-spacecraft"
                  field={@form[:spacecraft_id]}
                  type="select"
                  label="Spacecraft"
                  options={Enum.map(@spacecraft, &{&1.display_name, &1.spacecraft_id})}
                  required
                />
                <.input
                  id="requirement-intent"
                  field={@form[:contact_intent]}
                  type="select"
                  label="Contact intent"
                  options={[
                    {"Payload downlink", "payload_downlink"},
                    {"Health and safety", "health_and_safety"},
                    {"TT&C maintenance", "ttc_maintenance"},
                    {"Commissioning", "commissioning"}
                  ]}
                />
                <.input
                  id="requirement-success-measure"
                  field={@form[:success_measure]}
                  type="select"
                  label="Success means"
                  options={[
                    {"Minimum data volume", "minimum_data_volume"},
                    {"Minimum contact duration", "minimum_duration"},
                    {"Number of contacts", "contact_count"},
                    {"Any eligible contact", "any_contact"}
                  ]}
                />
                <.input
                  id="requirement-priority"
                  field={@form[:priority]}
                  type="select"
                  label="Operational priority"
                  options={[{"Routine", "routine"}, {"High", "high"}, {"Critical", "critical"}]}
                />
              </div>
            </section>

            <section class="border border-base-300 bg-base-200/20">
              <div class="border-b border-base-300 px-5 py-3">
                <p class="hud-label">02 / Acceptable horizon</p>
                <p class="mt-1 text-sm text-base-content/55">All times are coordinated universal time.</p>
              </div>
              <div class="grid gap-x-5 p-5 md:grid-cols-2">
                <.input
                  id="requirement-earliest-start"
                  field={@form[:earliest_start]}
                  type="datetime-local"
                  label="Earliest start (UTC)"
                  required
                />
                <.input
                  id="requirement-latest-end"
                  field={@form[:latest_end]}
                  type="datetime-local"
                  label="Latest end (UTC)"
                  required
                />
                <div :if={@form[:success_measure].value == "minimum_data_volume"}>
                  <.input
                    id="requirement-minimum-data-volume"
                    field={@form[:minimum_data_volume_bytes]}
                    type="number"
                    label="Minimum data volume (bytes)"
                    min="1"
                  />
                </div>
                <div :if={@form[:success_measure].value in ["minimum_duration", "minimum_data_volume"]}>
                  <.input
                    id="requirement-minimum-duration"
                    field={@form[:minimum_duration_seconds]}
                    type="number"
                    label="Minimum window duration (seconds)"
                    min="1"
                  />
                </div>
                <.input
                  id="requirement-preferred-duration"
                  field={@form[:preferred_duration_seconds]}
                  type="number"
                  label="Preferred window duration (seconds)"
                  min="1"
                />
                <.input
                  id="requirement-contact-count"
                  field={@form[:contact_count]}
                  type="number"
                  label="Required contact count"
                  min="1"
                />
                <.input
                  id="requirement-minimum-separation"
                  field={@form[:minimum_separation_seconds]}
                  type="number"
                  label="Minimum separation (seconds)"
                  min="0"
                />
              </div>
            </section>

            <details id="requirement-advanced-constraints" class="border border-base-300 bg-base-200/20">
              <summary class="cursor-pointer px-5 py-4 text-sm font-semibold">
                Advanced constraints
                <span class="ml-2 font-normal text-base-content/45">Optional provider and station boundaries</span>
              </summary>
              <div class="grid gap-x-5 border-t border-base-300 p-5 md:grid-cols-2">
                <.input id="requirement-allowed-providers" field={@form[:allowed_providers]} label="Allowed provider IDs" placeholder="provider-a, provider-b" />
                <.input id="requirement-excluded-providers" field={@form[:excluded_providers]} label="Excluded provider IDs" placeholder="provider-c" />
                <.input id="requirement-allowed-stations" field={@form[:allowed_stations]} label="Allowed station refs" placeholder="station-a, station-b" />
                <.input id="requirement-excluded-stations" field={@form[:excluded_stations]} label="Excluded station refs" placeholder="station-c" />
              </div>
            </details>

            <section class="border border-base-300 bg-base-200/20 p-5">
              <.input
                id="requirement-rationale"
                field={@form[:rationale]}
                type="textarea"
                label="Operator rationale"
                placeholder="Why this outcome and horizon are operationally important"
                required
                maxlength="2000"
              />
              <p :if={@form_error} id="contact-requirement-form-error" class="mt-2 text-sm text-error">
                {@form_error}
              </p>
              <div class="mt-4 flex justify-end gap-3">
                <.link navigate={~p"/missions/#{@current_mission.mission_id}/ops/requirements"} class="btn btn-ghost btn-sm">
                  Cancel
                </.link>
                <button id="save-contact-requirement" type="submit" class="btn btn-primary btn-sm font-mono text-xs uppercase tracking-wider">
                  Declare need
                </button>
              </div>
            </section>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp requirement_attrs(params) do
    with {:ok, earliest_start} <- parse_datetime(params["earliest_start"]),
         {:ok, latest_end} <- parse_datetime(params["latest_end"]),
         {:ok, minimum_duration} <- optional_integer(params["minimum_duration_seconds"]),
         {:ok, preferred_duration} <- optional_integer(params["preferred_duration_seconds"]),
         {:ok, minimum_volume} <- optional_integer(params["minimum_data_volume_bytes"]),
         {:ok, contact_count} <- positive_integer(params["contact_count"], 1),
         {:ok, separation} <- nonnegative_integer(params["minimum_separation_seconds"], 0) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         service_direction: :downlink,
         contact_intent: params["contact_intent"],
         earliest_start: earliest_start,
         latest_end: latest_end,
         success_measure: params["success_measure"],
         minimum_duration_seconds: minimum_duration,
         preferred_duration_seconds: preferred_duration,
         minimum_data_volume_bytes: minimum_volume,
         contact_count: contact_count,
         minimum_separation_seconds: separation,
         priority: params["priority"],
         provider_constraints_document: %{
           "allowed" => refs(params["allowed_providers"]),
           "excluded" => refs(params["excluded_providers"])
         },
         station_constraints_document: %{
           "allowed" => refs(params["allowed_stations"]),
           "excluded" => refs(params["excluded_stations"])
         },
         policy_constraints_document: %{},
         approval_policy_document: %{"mode" => "manual"},
         rationale: params["rationale"] || "",
         metadata: %{"source" => "ops_contact_requirement_form"}
       }}
    end
  end

  defp parse_datetime(value) do
    case NaiveDateTime.from_iso8601(value || "") do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      _error -> {:error, :invalid_requirement_time}
    end
  end

  defp optional_integer(value) when value in [nil, ""], do: {:ok, nil}

  defp optional_integer(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_requirement_number}
    end
  end

  defp positive_integer(value, default) when value in [nil, ""], do: {:ok, default}

  defp positive_integer(value, _default) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_requirement_number}
    end
  end

  defp nonnegative_integer(value, default) when value in [nil, ""], do: {:ok, default}

  defp nonnegative_integer(value, _default) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _other -> {:error, :invalid_requirement_number}
    end
  end

  defp refs(value) do
    value
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")

  defp error_message({:invalid_contact_requirement, message}), do: message
  defp error_message(:invalid_requirement_time), do: "Enter a valid UTC start and end time."

  defp error_message(:invalid_requirement_number),
    do: "Numeric outcomes must be positive whole numbers."

  defp error_message(_reason),
    do: "Cadence could not declare this need. Review the outcome and constraints."
end
