defmodule Cadence.Dev.ScaleRun do
  @moduledoc false

  alias Cadence.Dev.ReflectOrbital.{Activation, Fixture, LiveContacts}
  alias Cadence.Observability.ScaleSampler.Host
  alias CadenceSimulator.Load.Shape
  alias Mix.Tasks.Cadence.Scale.Run, as: Sampler
  alias Mix.Tasks.CadenceSimulator.Load, as: SimulatorLoad

  @root Path.expand("..", __DIR__)
  @contact_setup_seconds 1_800
  @contact_setup_timeout to_timeout(minute: 30)
  @measure_command ~S'''
  exec elixir --hidden --sname "scale_$$" --cookie "${CADENCE_ERLANG_COOKIE:?missing stack cookie}" \
    -S mix run --no-start -r dev/scale_run.exs -e 'Cadence.Dev.ScaleRun.measure(System.argv())' -- "$@"
  '''
  @switches [
    spacecraft: :integer,
    shape: :string,
    duration: :integer,
    label: :string,
    per_site: :integer,
    dedicated_runner: :boolean,
    module: :keep,
    reset: :boolean
  ]

  def boot(args) do
    opts = options!(args)
    if Mix.env() != :dev, do: Mix.raise("Run the scale stack with MIX_ENV=dev")

    unless System.find_executable("docker"),
      do: Mix.raise("The scale stack requires Docker for QuestDB")

    env = [{"EARENDIL_SPACECRAFT_COUNT", Integer.to_string(opts[:spacecraft])}]
    stack_command = if opts[:reset], do: "reset", else: "up"
    # System.cmd resolves a relative program through PATH only, so give dev/stack's full path.
    command!(Path.join(@root, "dev/stack"), [stack_command], env)

    command!("mise", ["exec", "--", "bash", "-c", @measure_command, "scale" | args], env)
  end

  def measure(args) do
    opts = options!(args)
    node = Sampler.connect!("cadence_#{System.fetch_env!("CADENCE_DEV_SLOT")}")
    duration = opts[:duration]
    label = opts[:label]
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")
    scale_id = "scale-#{stamp}-#{System.pid()}"
    out = Path.join(@root, "var/scale/#{stamp}-#{label}.jsonl")
    page = report_path(label)

    :ok = :erpc.call(node, Phoenix.CodeReloader, :reload, [CadenceWeb.Endpoint], 120_000)

    for file <- ~w(fixture activation live_contacts) do
      source = Path.join(__DIR__, "reflect_orbital/#{file}.exs")
      :erpc.call(node, Code, :compile_file, [source], 120_000)
    end

    sampler_opts = Keyword.take(opts, [:duration, :label, :module]) ++ [out: out]
    logger_level = :erpc.call(node, Logger, :level, [])
    :ok = :erpc.call(node, Logger, :configure, [[level: :warning]])

    try do
      activate(node, opts[:spacecraft])
      sites = :erpc.call(node, Fixture, :site_count, [])

      scids =
        for {scid, _site} <- Shape.fleet(opts[:spacecraft], sites),
            Shape.in_contact?(scid, sites, opts[:shape], opts[:per_site]),
            do: scid

      Mix.shell().info("Preparing #{length(scids)} live TCP paths across #{sites} sites")

      contacts =
        :erpc.call(
          node,
          LiveContacts,
          :run,
          [
            duration + @contact_setup_seconds,
            scids,
            [scale_id: scale_id, spacecraft: opts[:spacecraft]]
          ],
          @contact_setup_timeout
        )

      expires_in =
        Enum.min_by(contacts, & &1.ends_at, DateTime).ends_at |> DateTime.diff(DateTime.utc_now())

      if expires_in < duration + 120,
        do: Mix.raise("TCP contact windows will expire before the run finishes")

      sampler_opts =
        if opts[:dedicated_runner] do
          Keyword.put(sampler_opts, :pre_run_host, :erpc.call(node, Host, :sample, []))
        else
          sampler_opts
        end

      target = %{
        ports: Map.new(contacts, &{&1.scid, &1.port}),
        sites: sites,
        measure: &Sampler.sample(node, sampler_opts, &1)
      }

      load = SimulatorLoad.run(load_args(opts), target)
      write_report(page, out, opts, sites, load)

      if load.paths_sending != load.paths_expected,
        do: Mix.raise("Only #{load.paths_sending}/#{load.paths_expected} TCP paths made progress")
    after
      cleanup(node, scale_id, logger_level)
    end
  end

  defp activate(node, spacecraft) do
    Mix.shell().info("Activating the #{spacecraft}-spacecraft Earendil fleet")
    %{spacecraft: ^spacecraft} = :erpc.call(node, Activation, :run, [true, spacecraft], :infinity)
  end

  defp cleanup(node, scale_id, logger_level) do
    case :rpc.call(node, LiveContacts, :stop_scale_run, [scale_id], @contact_setup_timeout) do
      [] ->
        :ok

      errors ->
        Mix.shell().error(
          "Scale contact cleanup for #{scale_id} returned #{inspect(errors, limit: 10)}"
        )
    end

    :rpc.call(node, Logger, :configure, [[level: logger_level]], 5_000)
  end

  defp options!(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} ->
        validate!(opts)

      _ ->
        Mix.raise(
          "Usage: mix cadence.scale.run --spacecraft N --shape average|peak --duration S [--label LABEL] [--per-site 8|16] [--dedicated-runner] [--reset]"
        )
    end
  end

  defp validate!(opts) do
    craft = Keyword.fetch!(opts, :spacecraft)
    shape = Keyword.get(opts, :shape, "peak")
    duration = Keyword.get(opts, :duration)
    per_site = Keyword.get(opts, :per_site, 8)
    label = Keyword.get(opts, :label, "#{shape}-#{craft}")

    case Shape.validate(craft, shape, per_site) do
      :ok -> :ok
      {:error, reason} -> Mix.raise(String.replace(reason, "--craft", "--spacecraft"))
    end

    unless duration in 1..(28_800 - @contact_setup_seconds),
      do: Mix.raise("--duration must be between 1 and #{28_800 - @contact_setup_seconds} seconds")

    unless Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/, label),
      do: Mix.raise("--label may contain letters, digits, hyphens, and underscores")

    if File.exists?(report_path(label)),
      do: Mix.raise("A scale report already exists for today's date and label #{label}")

    Keyword.merge(opts, shape: shape, per_site: per_site, label: label)
  end

  defp command!(executable, args, env) do
    {_, status} =
      System.cmd(executable, args, cd: @root, env: env, into: IO.stream(:stdio, :line))

    if status != 0, do: Mix.raise("#{executable} failed with exit status #{status}")
  end

  defp load_args(opts) do
    [
      "--craft",
      to_string(opts[:spacecraft]),
      "--shape",
      opts[:shape],
      "--per-site",
      to_string(opts[:per_site]),
      "--duration",
      to_string(opts[:duration])
    ]
  end

  defp report_path(label), do: Path.join(@root, "docs/scale/#{Date.utc_today()}-#{label}.md")

  defp write_report(path, out, opts, sites, load) do
    %{
      meta: meta,
      rows: rows,
      elapsed_ms: elapsed_ms,
      counters: counters,
      metrics: metrics,
      storage: storage
    } =
      load.summary

    per_row = metrics |> Map.drop(Map.keys(counters)) |> Enum.sort()

    report = [
      capacity_heading(load.summary.host_capacity, meta.host.logical_cpus, opts[:label]),
      "- Fleet size #{opts[:spacecraft]}, #{sites} sites, #{opts[:shape]} load shape\n",
      per_site_line(opts),
      "- Requested duration #{opts[:duration]} s, sampled #{Float.round(elapsed_ms / 1_000, 2)} s " <>
        "across #{rows} rows\n",
      "- Simulator paths sending #{load.paths_sending}/#{load.paths_expected}\n",
      "- Simulator frames sent #{load.frames_sent}, target #{load.frames_per_second_expected} frames/s\n",
      Sampler.host_findings(load.summary, opts[:spacecraft]),
      "- Sampler JSONL \`#{Path.relative_to(out, @root)}\`\n",
      "- Summary JSON \`#{Path.relative_to(load.summary_path, @root)}\`\n\n",
      "## Run settings\n\n| Setting | Value |\n| --- | --- |\n",
      meta_rows(meta),
      "\n## Counter totals and rates per second\n\nRates use each row's elapsed time.\n\n" <>
        "| Metric | Total | p50/s | p99/s | Max/s |\n| --- | ---: | ---: | ---: | ---: |\n",
      for {key, %{total: total, per_second: stats}} <- Enum.sort(counters) do
        "| `#{key}` | #{cell(total)} | #{cell(stats.p50)} | #{cell(stats.p99)} | #{cell(stats.max)} |\n"
      end,
      "\n## Other per-row metrics\n\n| Metric | p50 | p99 | Max |\n| --- | ---: | ---: | ---: |\n",
      for {key, stats} <- per_row do
        "| \`#{key}\` | #{cell(stats.p50)} | #{cell(stats.p99)} | #{cell(stats.max)} |\n"
      end,
      "\n## Storage growth\n\n| Database | Table | Rows | Bytes |\n| --- | --- | ---: | ---: |\n",
      for {db, tables} <- Enum.sort(storage), {table, delta} <- Enum.sort(tables) do
        rows = if delta, do: delta[:rows_inserted] || delta[:rows]
        bytes = if delta, do: delta[:bytes]
        "| #{db} | \`#{table}\` | #{cell(rows)} | #{cell(bytes)} |\n"
      end
    ]

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, report, [:exclusive])
    Mix.shell().info("Wrote #{Path.relative_to(path, @root)}")
  end

  defp capacity_heading(capacity, cores, label) do
    classification =
      if capacity.classification == :baseline, do: "Baseline", else: "Ceiling check"

    load = capacity.max_load_one || "unavailable"

    swap =
      if capacity.max_swap_percent,
        do: "#{Float.round(capacity.max_swap_percent * 1.0, 1)}%",
        else: "unavailable"

    "# #{classification} — max 1-min load #{load} (#{cores} logical cores), max swap #{swap} — #{label}\n\n"
  end

  defp per_site_line(opts) do
    if opts[:shape] == "average",
      do: "- Active craft per site up to #{opts[:per_site]}\n",
      else: ""
  end

  defp meta_rows(meta, prefix \\ "") do
    for {key, value} <- Enum.sort(meta) do
      name = "#{prefix}#{key}"

      if is_map(value),
        do: meta_rows(value, name <> "."),
        else: "| `#{name}` | #{cell(value)} |\n"
    end
  end

  defp cell(nil), do: "—"
  defp cell(value), do: value |> to_string() |> String.replace("|", "\\|")
end
