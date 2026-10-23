#!/usr/bin/env python3
"""OrbStack-only Cadence resilience lab. Uses Python's standard library and kubectl."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STATE = ROOT / "var/chaos"
NAMESPACE = "cadence-chaos"
CONTEXT = "orbstack"
MISSION = "mission-earendil-demo"


def command(args, *, data=None, capture=True, check=True, timeout=600):
    return subprocess.run(args, input=data, text=True, capture_output=capture,
                          check=check, timeout=timeout, cwd=ROOT)


def kube(*args, **kwargs):
    return command(["kubectl", "--context", CONTEXT, "-n", NAMESPACE, *args], **kwargs)


def apply(items):
    kube("apply", "-f", "-", data=json.dumps({"apiVersion": "v1", "kind": "List", "items": items}),
         capture=False)


def resource(kind, name, spec=None, api="v1", **extra):
    obj = {"apiVersion": api, "kind": kind,
           "metadata": {"name": name, "namespace": NAMESPACE}, **extra}
    if spec is not None:
        obj["spec"] = spec
    return obj


def labels(name):
    return {"app": name, "cadence-lab": "true"}


def env(values):
    return [{"name": key, "value": str(value)} for key, value in values.items()]


def field_env(name, path):
    return {"name": name, "valueFrom": {"fieldRef": {"fieldPath": path}}}


def service(name, ports):
    return resource("Service", name, {"selector": labels(name), "ports": [
        {"name": f"tcp-{port}", "port": port, "targetPort": port} for port in ports]})


def volume(name, size):
    return resource("PersistentVolumeClaim", name, {
        "accessModes": ["ReadWriteOnce"], "resources": {"requests": {"storage": size}}})


def deployment(name, container, replicas=1, persistent=False):
    storage = {"persistentVolumeClaim": {"claimName": name}} if persistent else {
        "emptyDir": {"sizeLimit": "4Gi"}}
    return resource("Deployment", name, {
        "replicas": replicas, "selector": {"matchLabels": labels(name)},
        "strategy": {"type": "Recreate"} if persistent else {
            "type": "RollingUpdate", "rollingUpdate": {"maxUnavailable": 0, "maxSurge": 1}},
        "minReadySeconds": 10, "progressDeadlineSeconds": 600,
        "template": {"metadata": {"labels": labels(name)}, "spec": {
            "automountServiceAccountToken": False, "terminationGracePeriodSeconds": 90,
            "securityContext": {"fsGroup": 10001},
            "containers": [container], "volumes": [{"name": "data", **storage}]}}}, "apps/v1")


def container(name, image, memory="1Gi", cpu="2"):
    return {"name": name, "image": image, "imagePullPolicy": "IfNotPresent",
            "resources": {"requests": {"cpu": "100m", "memory": "128Mi"},
                          "limits": {"cpu": cpu, "memory": memory}},
            "volumeMounts": [{"name": "data", "mountPath": "/data"}]}


def settings():
    path = STATE / "images.json"
    return json.loads(path.read_text()) if path.exists() else {
        "server": "cadence-chaos:baseline", "simulator": "cadence-chaos-simulator:baseline"}


def manifests(images):
    config = resource("ConfigMap", "cadence", data={
        "CADENCE_CHAOS_LAB": "true", "PHX_HOST": "cadence.cadence-chaos.svc.cluster.local",
        "PHX_URL_SCHEME": "http", "PHX_URL_PORT": "4001", "PORT": "4001",
        "POOL_SIZE": "10", "ERL_FLAGS": "+S 2:2", "RELEASE_DISTRIBUTION": "name",
        "CADENCE_STORAGE_PATH": "/data", "CADENCE_DRAIN_FILE": "/tmp/cadence-draining",
        "CADENCE_INGRESS_JOURNAL_ENABLED": "true",
        "CADENCE_INGRESS_JOURNAL_MAX_BYTES": "1073741824",
        "CADENCE_QUESTDB_HTTP_ENDPOINT": "http://questdb:9000", "CADENCE_QUESTDB_HOST": "questdb",
        "EARENDIL_PROVIDER_URL": "http://simulator:4101", "EARENDIL_INGRESS_HOST": "cadence",
        "EARENDIL_BIND_HOST": "0.0.0.0", "EARENDIL_DEMO_EMAIL": "admin@cadence.test",
        "EARENDIL_DEMO_PROVIDER_TOKEN": "earendil-local-provider",
        "OTEL_SERVICE_NAME": "cadence-chaos",
        "OTEL_EXPORTER_OTLP_ENDPOINT": os.getenv("LAB_OTEL_ENDPOINT", "http://host.docker.internal:4318"),
        "CADENCE_OTEL_METRICS_EXPORT_INTERVAL_MS": "5000",
        "CADENCE_OTEL_METRICS_SAMPLE_INTERVAL_MS": "5000",
    })
    postgres = container("postgres", "postgres:17.6", "1Gi")
    postgres["env"] = env({"POSTGRES_DB": "cadence_chaos", "POSTGRES_USER": "cadence",
                           "PGDATA": "/data/pgdata"}) + [{"name": "POSTGRES_PASSWORD",
        "valueFrom": {"secretKeyRef": {"name": "cadence", "key": "POSTGRES_PASSWORD"}}}]
    postgres["readinessProbe"] = {"exec": {"command": ["pg_isready", "-U", "cadence", "-d", "cadence_chaos"]}}
    questdb = container("questdb", "questdb/questdb:9.4.3", "1Gi")
    questdb["volumeMounts"][0]["mountPath"] = "/var/lib/questdb"
    questdb["readinessProbe"] = {"httpGet": {"path": "/exec?query=select%201", "port": 9000}, "initialDelaySeconds": 5}
    simulator = container("simulator", images["simulator"])
    simulator["env"] = env({"CADENCE_CHAOS_LAB": "true", "ERL_FLAGS": "+S 2:2"}) + [field_env("POD_NAMESPACE", "metadata.namespace")]
    simulator["readinessProbe"] = {"httpGet": {"path": "/health", "port": 4101}}
    app = container("cadence", images["server"], os.getenv("LAB_APP_MEMORY", "4Gi"))
    app["resources"]["requests"]["memory"] = "512Mi"
    app["envFrom"] = [{"configMapRef": {"name": "cadence"}}, {"secretRef": {"name": "cadence"}}]
    app["env"] = [field_env("POD_NAME", "metadata.name"), field_env("POD_IP", "status.podIP"),
                  field_env("POD_UID", "metadata.uid"),
                  field_env("POD_NAMESPACE", "metadata.namespace")] + env({
        "RELEASE_NODE": "cadence@$(POD_IP)",
        # Shared immutable archives; exclusive journal directories per pod.
        # A container restart recovers its journal. Replacement keeps the old
        # directory for investigation; runtime handoff is a separate contract.
        "CADENCE_INGRESS_JOURNAL_PATH": "/data/journal/$(POD_UID)",
        "OTEL_RESOURCE_ATTRIBUTES": "deployment.environment.name=chaos-lab,k8s.namespace.name=$(POD_NAMESPACE),k8s.pod.name=$(POD_NAME),service.instance.id=$(POD_NAME)"})
    app["securityContext"] = {"runAsNonRoot": True, "runAsUser": 10001,
                              "allowPrivilegeEscalation": False, "capabilities": {"drop": ["ALL"]}}
    app["startupProbe"] = {"httpGet": {"path": "/health/live", "port": 4001}, "failureThreshold": 120, "periodSeconds": 5}
    app["livenessProbe"] = {"httpGet": {"path": "/health/live", "port": 4001}, "periodSeconds": 10, "timeoutSeconds": 3}
    app["readinessProbe"] = {"httpGet": {"path": "/health/ready", "port": 4001}, "periodSeconds": 2, "timeoutSeconds": 2, "failureThreshold": 1}
    app["lifecycle"] = {"preStop": {"exec": {"command": ["sh", "-c", "touch /tmp/cadence-draining; sleep 10"]}}}
    traffic = container("traffic", images["simulator"])
    traffic["env"] = env({"CADENCE_CHAOS_LAB": "true", "ERL_FLAGS": "+S 2:2", "LAB_RATE_HZ": os.getenv("LAB_RATE_HZ", "1.0")}) + [field_env("POD_NAMESPACE", "metadata.namespace")]
    traffic["command"] = ["bin/cadence_simulator", "eval", 'Code.eval_file("/lab/scripts/traffic.exs")']
    traffic_deployment = deployment("traffic", traffic)
    # A generator update must not create concurrent TCP writers for the same
    # synthetic source. Keep this deployment unchanged during app experiments.
    traffic_deployment["spec"]["strategy"] = {"type": "Recreate"}
    app_deployment = deployment("cadence", app, replicas=3)
    app_deployment["spec"]["template"]["spec"]["securityContext"]["fsGroupChangePolicy"] = "OnRootMismatch"
    app_deployment["spec"]["template"]["spec"]["volumes"] = [
        {"name": "data", "persistentVolumeClaim": {"claimName": "cadence-archives"}}]
    return {
        "infra": [config, volume("cadence-archives", "8Gi"), volume("postgres", "8Gi"), service("postgres", [5432]),
                  deployment("postgres", postgres, persistent=True), volume("questdb", "8Gi"),
                  service("questdb", [9000, 8812]), deployment("questdb", questdb, persistent=True),
                  volume("simulator", "1Gi"), service("simulator", [4101]),
                  deployment("simulator", simulator, persistent=True)],
        "app": [service("cadence", [4001, *range(42100, 42110)]), app_deployment,
                resource("PodDisruptionBudget", "cadence", {"minAvailable": 2, "selector": {"matchLabels": labels("cadence")}}, "policy/v1")],
        "traffic": [traffic_deployment],
    }


def init_namespace():
    obj = {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": NAMESPACE,
           "labels": {"cadence-lab": "true"},
           "annotations": {"chaos-mesh.org/inject": "enabled"}}}
    apply([obj])
    # Reuse credentials on every invocation; never rotate a live database password implicitly.
    existing = kube("get", "secret", "cadence", check=False)
    if existing.returncode == 0:
        return
    password = secrets.token_urlsafe(32)
    values = {"POSTGRES_PASSWORD": password,
              "DATABASE_URL": f"ecto://cadence:{password}@postgres/cadence_chaos",
              "SECRET_KEY_BASE": secrets.token_urlsafe(64),
              "CADENCE_OPPORTUNITY_CAPABILITY_SECRET": secrets.token_urlsafe(48),
              "RELEASE_COOKIE": secrets.token_urlsafe(48),
              "CADENCE_ADMIN_EMAIL": "admin@cadence.test", "CADENCE_ADMIN_PASSWORD": secrets.token_urlsafe(24)}
    path = STATE / "credentials.json"
    fd = os.open(path, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(values, output, indent=2)
    apply([resource("Secret", "cadence", type="Opaque", stringData=values)])


def wait_deployment(name):
    kube("rollout", "status", f"deployment/{name}", "--timeout=600s", capture=False, timeout=620)


def migration(image):
    name = f"migrate-{int(time.time())}"
    app = manifests({**settings(), "server": image})["app"][1]["spec"]["template"]["spec"]
    item = app["containers"][0]
    for key in ("startupProbe", "readinessProbe", "livenessProbe", "lifecycle"):
        item.pop(key, None)
    item["command"] = ["bin/cadence_web", "eval", "CadenceWeb.Release.migrate()"]
    app["restartPolicy"] = "Never"
    apply([resource("Job", name, {"backoffLimit": 0, "activeDeadlineSeconds": 600,
           "ttlSecondsAfterFinished": 86400, "template": {"spec": app}}, "batch/v1")])
    result = kube("wait", "--for=condition=complete", f"job/{name}", "--timeout=600s", check=False, timeout=620)
    kube("logs", f"job/{name}", capture=False)
    if result.returncode:
        raise RuntimeError(f"Migration {name} did not complete; old application pods were not updated")


def pod_names():
    pods = json.loads(kube("get", "pods", "-l", "app=cadence", "-o", "json").stdout)["items"]
    return [p["metadata"]["name"] for p in pods if not p["metadata"].get("deletionTimestamp") and
            any(c["type"] == "Ready" and c["status"] == "True" for c in p["status"].get("conditions", []))]


def rpc(pod, expression, capture=False):
    return kube("exec", pod, "--", "bin/cadence_web", "rpc", expression, capture=capture, timeout=1800)


def script_expression(name):
    encoded = base64.b64encode((HERE / "scripts" / name).read_bytes()).decode()
    return f'Code.eval_string(Base.decode64!("{encoded}"))'


def seed():
    pod = pod_names()[0]
    for action in ("questdb", "seed", "activate", "contacts"):
        print(f"Preparing {action} on {pod}", flush=True)
        rpc(pod, f'System.put_env("LAB_ACTION", "{action}"); Code.eval_file("/lab/scripts/seed.exs")')
    # Explicitly recover the persisted activation on all replicas before starting traffic.
    for pod in pod_names():
        rpc(pod, f'IO.inspect(Cadence.Control.Missions.ensure_started("{MISSION}"))')


def warm():
    for pod in pod_names():
        warm_pod(pod)


def warm_pod(pod, capture=False):
    print(f"Recovering ten live-source partitions on {pod}", flush=True)
    return rpc(pod, f'''
      {{snapshot, _}} = {script_expression("memory_snapshot.exs")}
      owner = self()
      sampler = spawn_link(fn ->
        loop = fn loop, peak ->
          current = snapshot.()
          peak = if current.beam.total > peak.beam.total, do: current, else: peak
          receive do
            :stop -> send(owner, {{:memory_peak, peak, current}})
          after
            500 -> loop.(loop, peak)
          end
        end
        loop.(loop, snapshot.())
      end)
      {{:ok, _}} = Cadence.Control.Missions.ensure_started("{MISSION}")
      for scid <- 1..10 do
        source = "spacecraft_runtime:spacecraft-earendil-" <> String.pad_leading(to_string(scid), 3, "0")
        partition = %Cadence.Runtime.PartitionKey{{affinity: :source_endpoint, value: source}}
        {{:ok, _}} = GenServer.call(Cadence.Runtime.MissionRuntime.coordinator_name("{MISSION}"),
          {{:partition_snapshot, partition}}, 600_000)
      end
      send(sampler, :stop)
      receive do
        {{:memory_peak, peak, last}} ->
          IO.puts("LAB_RECOVERY_MEMORY=" <> Jason.encode!(%{{peak: peak, last: last}}))
      after
        5_000 -> raise "Memory sampler did not finish"
      end
      IO.puts("Recovered all ten source partitions")
    ''', capture=capture)


def startup(replicas):
    """Measure simultaneous cold startup on an already seeded, stopped deployment."""
    for name in ("cadence", "traffic"):
        deployment = json.loads(kube("get", "deployment", name, "-o", "json").stdout)
        if deployment["spec"].get("replicas", 1) != 0 or deployment.get("status", {}).get("replicas", 0):
            raise RuntimeError("Startup requires cadence and traffic scaled to zero with all pods stopped")

    directory = STATE / "runs" / (dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-startup")
    directory.mkdir(parents=True)
    started = time.monotonic()
    summary = {"replicas": replicas, "dataset": database_name(), "passed": False}
    try:
        kube("scale", "deployment/cadence", f"--replicas={replicas}", capture=False)
        wait_deployment("cadence")
        summary["kubernetes_ready_seconds"] = time.monotonic() - started
        pods = pod_names()
        if len(pods) != replicas:
            raise RuntimeError("Not all requested replicas are Ready")
        # Recover the same ten partitions on every replica concurrently. cgroup peak
        # counters include allocations before RPC becomes available.
        with ThreadPoolExecutor(max_workers=replicas) as executor:
            futures = {pod: executor.submit(warm_pod, pod, True) for pod in pods}
            for pod, future in futures.items():
                result = future.result()
                (directory / f"recovery-{pod}.txt").write_text(result.stdout + result.stderr)
        summary["all_partitions_ready_seconds"] = time.monotonic() - started
        snapshots = {}
        for pod in pods:
            expression = f'{{snapshot, _}} = {script_expression("memory_snapshot.exs")}; IO.puts("LAB_MEMORY=" <> Jason.encode!(snapshot.()))'
            result = rpc(pod, expression, capture=True)
            line = next(line for line in result.stdout.splitlines() if line.startswith("LAB_MEMORY="))
            snapshots[pod] = json.loads(line.split("=", 1)[1])
        summary["memory"] = snapshots
        statuses = json.loads(kube("get", "pods", "-l", "app=cadence", "-o", "json").stdout)
        (directory / "pods.json").write_text(json.dumps(statuses, indent=2))
        summary["restart_count"] = sum(status.get("restartCount", 0) for pod in statuses["items"]
                                       for status in pod.get("status", {}).get("containerStatuses", []))
        summary["oom_kills"] = sum(int(dict(line.split() for line in snapshot["cgroup"]["memory.events"].splitlines()).get("oom_kill", 0))
                                   for snapshot in snapshots.values())
        summary["passed"] = summary["restart_count"] == 0 and summary["oom_kills"] == 0
    finally:
        summary["elapsed_seconds"] = time.monotonic() - started
        (directory / "summary.json").write_text(json.dumps(summary, indent=2))
        print(json.dumps({"artifacts": str(directory), "passed": summary["passed"]}), flush=True)
    return 0 if summary["passed"] else 1


def renew_contacts():
    """Operator recovery between experiments; never part of a continuity verdict."""
    kube("scale", "deployment/traffic", "--replicas=0", capture=False)
    kube("wait", "--for=delete", "pod", "-l", "app=traffic", "--timeout=120s", timeout=140)
    pods = pod_names()
    expression = f'''
      unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
        System.get_env("POD_NAMESPACE") == "{NAMESPACE}", do: raise("Not the lab")
      contacts = Cadence.Contacts.list_scheduled_contacts("org-reflect-orbital-demo", "{MISSION}")
        |> Enum.filter(fn c -> c.metadata["fixture"] == "earendil-live-dashboards" and
          c.lifecycle_state in [:scheduled, :realized] end)
      Enum.each(contacts, fn c ->
        {{:ok, _}} = Cadence.Contacts.cancel_scheduled_contact(
          "org-reflect-orbital-demo", "{MISSION}", c.scheduled_contact_id, [])
      end)
      IO.puts("LAB_CONTACT_IDS=" <> Jason.encode!(Enum.map(contacts, &(&1.scheduled_contact_id <> "_run"))))
    '''
    result = rpc(pods[0], expression, capture=True)
    encoded = next(line.removeprefix("LAB_CONTACT_IDS=") for line in result.stdout.splitlines()
                   if line.startswith("LAB_CONTACT_IDS="))
    for pod in pods:
        print(f"Waiting for synthetic contact shutdown on {pod}", flush=True)
        rpc(pod, f'for id <- Jason.decode!({json.dumps(encoded)}), do: '
                 f':ok = Cadence.Control.Contacts.stop_realized_contact_sync("{MISSION}", id)')
    print("Creating fresh synthetic contact identities", flush=True)
    rpc(pods[0], 'System.put_env("LAB_ACTION", "contacts"); Code.eval_file("/lab/scripts/seed.exs")')
    kube("scale", "deployment/traffic", "--replicas=1", capture=False)
    wait_deployment("traffic")


def sql(query):
    return kube("exec", "deployment/postgres", "--", "psql", "-X", "-U", "cadence", "-d", database_name(),
                "-v", "ON_ERROR_STOP=1", "-Atc", query, timeout=30).stdout.strip()


def database_name():
    path = STATE / "dataset.json"
    return json.loads(path.read_text())["database"] if path.exists() else "cadence_chaos"


def new_dataset():
    """Preserve a failed dataset and start a separate synthetic rehearsal."""
    for name in ("cadence", "traffic"):
        deployment_value = json.loads(kube("get", f"deployment/{name}", "-o", "json").stdout)
        if deployment_value["spec"]["replicas"] != 0:
            raise RuntimeError("Pause cadence and traffic before creating a separate dataset")
        kube("wait", "--for=delete", "pod", "-l", f"app={name}", "--timeout=120s", timeout=140)
    previous = database_name()
    name = "cadence_chaos_" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%S")
    kube("exec", "deployment/postgres", "--", "createdb", "-U", "cadence", name)
    secret = json.loads(kube("get", "secret/cadence", "-o", "json").stdout)
    old_url = base64.b64decode(secret["data"]["DATABASE_URL"]).decode()
    url = urllib.parse.urlsplit(old_url)._replace(path="/" + name).geturl()
    # Secret bytes travel over stdin, never command arguments or printed output.
    secret["data"]["DATABASE_URL"] = base64.b64encode(url.encode()).decode()
    kube("replace", "-f", "-", data=json.dumps(secret))
    credentials_path = STATE / "credentials.json"
    if credentials_path.exists():
        credentials = json.loads(credentials_path.read_text())
        credentials["DATABASE_URL"] = url
        credentials_path.write_text(json.dumps(credentials, indent=2))
    dataset = {"database": name, "preserved_database": previous}
    (STATE / "dataset.json").write_text(json.dumps(dataset, indent=2))
    print(json.dumps(dataset))


def sample():
    result = {"at": dt.datetime.now(dt.timezone.utc).isoformat()}
    start = time.monotonic()
    try:
        url = os.getenv("LAB_URL", "http://cadence.cadence-chaos.svc.cluster.local:4001")
        with urllib.request.urlopen(url + "/health/ready", timeout=3) as response:
            result["http_status"] = response.status
    except Exception as error:
        result["http_status"] = getattr(error, "code", 0)
        result["http_error"] = str(error)
    result["http_ms"] = round((time.monotonic() - start) * 1000, 2)
    try:
        result["telemetry"] = json.loads(sql(f"""
          SELECT coalesce(json_agg(t), '[]') FROM (
            SELECT scid, count(*) AS records,
                   extract(epoch from now() - max(receipt_time)) AS age_seconds
            FROM protocol_archive_record_entries WHERE mission_id = '{MISSION}'
              AND record_kind = 'transfer_frame_record' AND scid BETWEEN 1 AND 10
            GROUP BY scid ORDER BY scid
          ) t;
        """))
    except Exception as error:
        result["telemetry"] = []
        result["database_error"] = str(error)
    return result


def healthy(sample_value, freshness):
    rows = sample_value["telemetry"]
    return sample_value["http_status"] == 200 and {row["scid"] for row in rows} == set(range(1, 11)) and all(
        0 <= row["age_seconds"] <= freshness for row in rows)


def injection_observed(experiment):
    status = experiment.get("status", {})
    return any(condition["type"] == "AllInjected" and condition["status"] == "True"
               for condition in status.get("conditions", [])) or any(
                   record.get("injectedCount", 0) > 0
                   for record in status.get("experiment", {}).get("containerRecords", []))


def continuity_passed(initially_healthy, diagnostic, injected, samples):
    return initially_healthy and not diagnostic and injected and bool(samples) and all(
        sample_value["continuity_ok"] for sample_value in samples)


def archive_locations(keys=None, checksums=None):
    if keys is None:
        keys = json.loads(sql(f"""
          SELECT coalesce(json_agg(object_key), '[]') FROM (
            SELECT DISTINCT ON (scid) 'protocol_record_archive/' || object_key AS object_key FROM protocol_archive_record_entries
            WHERE mission_id = '{MISSION}' AND record_kind = 'transfer_frame_record'
              AND scid BETWEEN 1 AND 10 ORDER BY scid, receipt_time DESC
          ) t;
        """))
        keys += json.loads(sql(f"""
          SELECT coalesce(json_agg(object_key), '[]') FROM (
            SELECT DISTINCT ON (metadata ->> 'journal_stream_id') 'ingress_archive/' || object_key AS object_key
            FROM ingress_archive_evidence_entries WHERE mission_id = '{MISSION}'
              AND metadata ? 'journal_stream_id' ORDER BY metadata ->> 'journal_stream_id', receipt_time DESC
          ) t;
        """))
    locations = {key: [] for key in keys}
    if checksums is None:
        checksums = {}
    paths = {"/data/" + key: key for key in keys}
    for pod in pod_names():
        result = kube("exec", pod, "--", "sh", "-c",
                      'for file do if [ -f "$file" ]; then sha256sum "$file" || exit; fi; done',
                      "archive-check", *paths, check=False, timeout=30)
        if result.returncode:
            raise RuntimeError(f"Could not inspect archive storage on {pod}")
        for line in result.stdout.splitlines():
            digest, path = line.split(maxsplit=1)
            locations[paths[path]].append(pod)
            checksums.setdefault(paths[path], {})[pod] = digest
    return locations


def active_receivers():
    """Shared archive access is not evidence that a pod receives live traffic."""
    counts = {}
    for pod in pod_names():
        result = kube("exec", pod, "--", "sh", "-c", "cat /proc/net/tcp /proc/net/tcp6")
        counts[pod] = count_ingress_connections(result.stdout)
    return counts


def count_ingress_connections(tables):
    count = 0
    for line in tables.splitlines():
        fields = line.split()
        if len(fields) > 3 and fields[3] == "01":
            port = int(fields[1].split(":")[1], 16)
            count += 42100 <= port < 42110
    return count


def capture_observability(directory, since):
    start = int(dt.datetime.fromisoformat(since).timestamp())
    end = int(time.time())
    metrics = os.getenv("LAB_METRICS_URL", "http://localhost:4000").rstrip("/")
    logs = os.getenv("LAB_LOGS_URL", "http://localhost:3100").rstrip("/")
    traces = os.getenv("LAB_TRACES_URL", "http://localhost:3200").rstrip("/")
    queries = {
        "otel-memory.json": (metrics + "/v1/prometheus/api/v1/query_range", {
            "query": 'beam_memory_usage_bytes{service_name="cadence-chaos",memory_type="total"}',
            "start": start, "end": end, "step": "5s"}),
        "otel-ownership.json": (metrics + "/v1/prometheus/api/v1/query_range", {
            "query": 'cadence_runtime_partition_ownership_total{service_name="cadence-chaos"}',
            "start": start, "end": end, "step": "5s"}),
        "otel-freshness.json": (metrics + "/v1/prometheus/api/v1/query_range", {
            "query": 'cadence_telemetry_freshness_seconds{service_name="cadence-chaos"}',
            "start": start, "end": end, "step": "5s"}),
        "otel-logs.json": (logs + "/loki/api/v1/query_range", {
            "query": '{service_name="cadence-chaos"}', "start": start * 1_000_000_000,
            "end": end * 1_000_000_000, "limit": 1000}),
        "otel-traces.json": (traces + "/api/search", {
            "q": '{resource.service.name="cadence-chaos"}', "start": start,
            "end": end, "limit": 100}),
    }
    errors = []
    for filename, (url, params) in queries.items():
        try:
            with urllib.request.urlopen(url + "?" + urllib.parse.urlencode(params), timeout=10) as response:
                result = json.load(response)
            (directory / filename).write_text(json.dumps(result))
            if result.get("status") == "error":
                errors.append(f"Observability query failed: {filename}")
        except Exception as error:
            errors.append(f"Could not capture {filename}: {error}")
    return errors


def capture_artifacts(directory, since):
    errors = []
    for filename, args in {
        "deployments.json": ("get", "deployment/cadence", "deployment/traffic", "-o", "json"),
        "pods.json": ("get", "pods", "-o", "json"), "events.txt": ("get", "events", "--sort-by=.lastTimestamp"),
        "node-events.json": ("get", "events", "-A", "--field-selector", "involvedObject.kind=Node", "-o", "json"),
        "cadence.log": ("logs", "-l", "app=cadence", "--all-containers", "--prefix", "--tail=2000", "--max-log-requests=10"),
        "traffic.log": ("logs", "deployment/traffic", "--tail=1000"),
        "traffic-sockets.txt": ("exec", "deployment/traffic", "--", "cat", "/proc/net/tcp", "/proc/net/tcp6"),
        "experiments.json": ("get", "podchaos,networkchaos", "-o", "json"),
    }.items():
        if args[0] == "logs":
            args = (*args, f"--since-time={since}")
        result = kube(*args, check=False)
        (directory / filename).write_text(result.stdout + result.stderr)
        if result.returncode:
            errors.append(f"Could not capture {filename}")
    for pod in pod_names():
        expression = f'''
          {{snapshot, _}} = {script_expression("memory_snapshot.exs")}
          IO.puts("LAB_MEMORY=" <> Jason.encode!(snapshot.()))
          coordinator = GenServer.whereis(Cadence.Runtime.MissionRuntime.coordinator_name("{MISSION}"))
          counts = Map.new(1..10, fn scid ->
            spacecraft = "spacecraft-earendil-" <> String.pad_leading(to_string(scid), 3, "0")
            values = Cadence.Telemetry.CurrentValueStore.latest_values_for_mission(
              "{MISSION}", spacecraft_id: spacecraft)
            {{spacecraft, length(values)}}
          end)
          IO.puts(Jason.encode!(%{{node: to_string(Node.self()),
            peers: Enum.map(Node.list(), &to_string/1), coordinator_registered: is_pid(coordinator),
            latest_point_counts: counts, memory: :erlang.memory(:total)}}))
        '''
        result = kube("exec", pod, "--", "bin/cadence_web", "rpc", expression,
                      timeout=30, check=False)
        (directory / f"runtime-{pod}.txt").write_text(result.stdout + result.stderr)
        if result.returncode:
            errors.append(f"Could not capture runtime on {pod}")
    return errors + capture_observability(directory, since)


def semantic_sequence_audit():
    result = kube("exec", pod_names()[0], "--", "bin/cadence_web", "rpc",
                  'Code.eval_file("/lab/scripts/semantic_sequence_audit.exs")', timeout=150)
    return json.loads(next(line.removeprefix("LAB_SEMANTIC_AUDIT=") for line in result.stdout.splitlines()
                           if line.startswith("LAB_SEMANTIC_AUDIT=")))


def journal_snapshot():
    pods = json.loads(kube("get", "pods", "-l", "app=cadence", "-o", "json").stdout)["items"]
    owners = {pod["metadata"]["uid"]: pod["metadata"]["name"] for pod in pods}
    result = rpc(pod_names()[0], script_expression("journal_snapshot.exs"), capture=True)
    snapshot = json.loads(next(line.removeprefix("LAB_JOURNAL_SNAPSHOT=") for line in result.stdout.splitlines()
                               if line.startswith("LAB_JOURNAL_SNAPSHOT=")))
    for stream in snapshot["streams"]:
        stream["existing_pod"] = owners.get(stream["pod_uid"])
    return snapshot


def run_experiment(args):
    if args.seconds < 60:
        raise ValueError("Use at least 60 seconds to include a baseline and recovery window")
    initial = sample()
    initial_audit = semantic_sequence_audit()
    initially_healthy = healthy(initial, args.freshness) and initial_audit["regressions"] == 0
    ready_replicas = len(pod_names())
    if ready_replicas < args.minimum_ready_replicas and not args.diagnostic:
        raise RuntimeError(f"Need {args.minimum_ready_replicas} Ready replicas before measuring; found {ready_replicas}")
    if not initially_healthy and args.experiment != "baseline" and not args.diagnostic:
        raise RuntimeError("Baseline is unhealthy: require HTTP 200, all ten fresh feeds, and no semantic state regressions before injection")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = STATE / "runs" / f"{stamp}-{args.experiment}"
    directory.mkdir(parents=True)
    (directory / "initial.json").write_text(json.dumps(initial, indent=2))
    (directory / "semantic-sequence-audit-before.json").write_text(json.dumps(initial_audit, indent=2))
    (directory / "journals-before.json").write_text(json.dumps(journal_snapshot(), indent=2))
    for pod in pod_names():
        result = rpc(pod, f'{{snapshot, _}} = {script_expression("memory_snapshot.exs")}; '
                     'IO.puts("LAB_MEMORY=" <> Jason.encode!(snapshot.()))', capture=True)
        (directory / f"memory-before-{pod}.txt").write_text(result.stdout)
    hashes_before = {}
    archive_before = archive_locations(checksums=hashes_before)
    (directory / "archive-before.json").write_text(json.dumps(archive_before, indent=2))
    (directory / "archive-hashes-before.json").write_text(json.dumps(hashes_before, indent=2))
    (directory / "dataset.json").write_text(json.dumps({"database": database_name()}))
    receivers = active_receivers()
    (directory / "receivers-before.json").write_text(json.dumps(receivers, indent=2))
    target_pod = max(receivers, key=receivers.get) if any(receivers.values()) else None
    target_holds_archive = target_pod is not None and any(target_pod in pods for pods in archive_before.values())
    if target_pod is None and args.diagnostic:
        ready_pods = pod_names()
        target_pod = ready_pods[0] if ready_pods else None
    if args.experiment not in ("baseline", "rollout") and target_pod is None:
        raise RuntimeError("No pod has an established synthetic ingress connection; cannot target an active receiver")
    samples = []
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    injected = False
    action = None
    start = time.monotonic()
    fault_path = HERE / "experiments" / f"{args.experiment}.yaml"
    try:
        with (directory / "samples.jsonl").open("w") as output:
            while time.monotonic() - start < args.seconds:
                elapsed = time.monotonic() - start
                if elapsed >= 15 and not injected:
                    injected = True
                    if args.experiment == "rollout":
                        action = kube("rollout", "restart", "deployment/cadence").stdout
                    elif args.experiment != "baseline":
                        kube("delete", "-f", str(fault_path), "--ignore-not-found", "--wait=true")
                        experiment = json.loads(kube("create", "--dry-run=client", "-f", str(fault_path), "-o", "json").stdout)
                        experiment["spec"]["selector"]["pods"] = {NAMESPACE: [target_pod]}
                        apply([experiment])
                        action = f"Requested {args.experiment} on {target_pod}"
                    (directory / "action.json").write_text(json.dumps({"at_seconds": elapsed, "result": action,
                        "target_pod": target_pod, "target_holds_archive": target_holds_archive}, indent=2))
                current = sample()
                current["elapsed_seconds"] = round(time.monotonic() - start, 2)
                current["continuity_ok"] = healthy(current, args.freshness)
                samples.append(current)
                output.write(json.dumps(current) + "\n")
                output.flush()
                print(json.dumps(current), flush=True)
                time.sleep(2)
    finally:
        try:
            artifact_errors = capture_artifacts(directory, started_at)
            if fault_path.exists():
                # Injection counts retain evidence after a timed fault recovers.
                experiment = json.loads(kube("get", "-f", str(fault_path), "-o", "json").stdout)
                injected = injection_observed(experiment)
        finally:
            if fault_path.exists():
                kube("delete", "-f", str(fault_path), "--ignore-not-found", "--wait=true", check=False)
    wait_deployment("cadence")
    hashes_after = {}
    try:
        archive_after = archive_locations(archive_before, checksums=hashes_after)
    except RuntimeError as error:
        artifact_errors.append(str(error))
        archive_after = {key: [] for key in archive_before}
    (directory / "archive-after.json").write_text(json.dumps(archive_after, indent=2))
    (directory / "archive-hashes-after.json").write_text(json.dumps(hashes_after, indent=2))
    changed_objects = [key for key in hashes_before if
                       len(set(hashes_before[key].values()) | set(hashes_after.get(key, {}).values())) != 1]
    missing_objects = [key for key, holders in archive_after.items() if not holders]
    final_ready_replicas = len(pod_names())
    unshared_objects = [key for key, holders in archive_after.items() if len(holders) != final_ready_replicas]
    audit = None
    try:
        audit = semantic_sequence_audit()
        (directory / "semantic-sequence-audit.json").write_text(json.dumps(audit, indent=2))
    except Exception as error:
        artifact_errors.append(f"Could not audit semantic sequence history: {error}")
    try:
        (directory / "journals-after.json").write_text(json.dumps(journal_snapshot(), indent=2))
        (directory / "receivers-after.json").write_text(json.dumps(active_receivers(), indent=2))
    except Exception as error:
        artifact_errors.append(f"Could not capture journal/receiver handoff state: {error}")
    initially_missing = [key for key, holders in archive_before.items() if not holders]
    source_drops = sum(int(count) for count in re.findall(
        r"dropping (\d+) packets", (directory / "traffic.log").read_text()))
    passed = continuity_passed(initially_healthy, args.diagnostic, injected, samples)
    latency = sorted(s["http_ms"] for s in samples)
    observed_seconds = samples[-1]["elapsed_seconds"] - samples[0]["elapsed_seconds"] if len(samples) > 1 else 0
    frames = lambda value: sum(row["records"] for row in value["telemetry"])
    frame_rate = (frames(samples[-1]) - frames(samples[0])) / observed_seconds if observed_seconds > 0 else None
    summary = {"experiment": args.experiment, "samples": len(samples),
               "initial_ready_replicas": ready_replicas,
               "final_ready_replicas": final_ready_replicas,
               "semantic_sequence_audit": audit,
               "initially_healthy": initially_healthy, "diagnostic_only": args.diagnostic,
               "http_failures": sum(s["http_status"] != 200 for s in samples),
               "continuity_failures": sum(not s["continuity_ok"] for s in samples),
               "freshness_threshold_seconds": args.freshness, "continuity_passed": passed,
               "action_observed": injected,
               "archive_objects_checked": len(archive_after),
               "initially_missing_archive_objects": initially_missing,
               "missing_archive_objects": missing_objects,
               "newly_missing_archive_objects": [key for key in missing_objects if key not in initially_missing],
               "changed_archive_objects": changed_objects,
               "archive_objects_not_on_every_replica": unshared_objects,
               "source_dropped_outputs": source_drops,
               "artifact_errors": artifact_errors,
               "resilience_passed": passed and bool(archive_after) and not missing_objects and not unshared_objects and not changed_objects and source_drops == 0 and audit is not None and audit["regressions"] == 0 and not artifact_errors,
               "archived_frames_per_second": frame_rate,
               "http_p95_ms": latency[min(int(len(latency) * 0.95), len(latency) - 1)] if latency else None,
               "production_delivery_certified": False,
               "limitations": ["Ten live spacecraft; 500 configured", "Single physical Kubernetes node",
                               "Sampled readiness/freshness do not prove lossless or exactly-once delivery",
                               "No uplink or command delivery exercise",
                               "Shared archive PVC is local to the OrbStack node",
                               "Retained pod journals do not yet have replacement-pod handoff"]}
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Evidence: {directory}")
    print(json.dumps(summary, indent=2))
    return 0 if summary["resilience_passed"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("build", "seed", "warm", "traffic", "renew-contacts", "new-dataset", "mesh", "status", "stop", "render"):
        sub.add_parser(name)
    bootstrap = sub.add_parser("up")
    bootstrap.add_argument("--replicas", type=int, choices=range(1, 7), default=3)
    cold_start = sub.add_parser("startup", help="Simultaneously start a seeded, stopped deployment and record recovery memory")
    cold_start.add_argument("--replicas", type=int, choices=range(1, 7), default=3)
    scaling = sub.add_parser("scale")
    scaling.add_argument("replicas", type=int, choices=range(1, 7))
    rollout = sub.add_parser("deploy")
    rollout.add_argument("image", help="An already-built immutable image tag; migration runs first")
    run = sub.add_parser("run")
    run.add_argument("experiment", choices=["baseline", "rollout", "pod-kill", "pod-failure", "network-delay", "database-partition"])
    run.add_argument("--seconds", type=int, default=180)
    run.add_argument("--freshness", type=float, default=10)
    run.add_argument("--minimum-ready-replicas", type=int, choices=range(1, 7), default=3)
    run.add_argument("--diagnostic", action="store_true",
                     help="Allow injection from an unhealthy baseline to diagnose the lab; never yields a passing verdict")
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    os.chmod(STATE, 0o700)
    images = settings()
    if args.action == "render":
        print(json.dumps(manifests(images), indent=2))
    elif args.action == "build":
        sha = command(["git", "rev-parse", "--short", "HEAD"]).stdout.strip()
        tag = f"{sha}-{int(time.time())}"
        for target, repository in (("server", "cadence-chaos"), ("simulator", "cadence-chaos-simulator")):
            images[target] = f"{repository}:{tag}"
            command(["docker", "--context", CONTEXT, "build", "-f", "dev/chaos/Dockerfile", "--target", target,
                     "-t", images[target], "."], capture=False, timeout=3600)
        (STATE / "images.json").write_text(json.dumps(images, indent=2))
    elif args.action == "up":
        command(["orb", "start", "k8s"], capture=False)
        init_namespace()
        objects = manifests(images)
        apply(objects["infra"])
        for name in ("postgres", "questdb", "simulator"):
            wait_deployment(name)
        migration(images["server"])
        objects["app"][1]["spec"]["replicas"] = args.replicas
        apply(objects["app"])
        wait_deployment("cadence")
    elif args.action == "startup":
        return startup(args.replicas)
    elif args.action == "seed":
        seed()
    elif args.action == "warm":
        warm()
    elif args.action == "new-dataset":
        new_dataset()
    elif args.action == "traffic":
        apply(manifests(images)["traffic"])
        wait_deployment("traffic")
    elif args.action == "renew-contacts":
        renew_contacts()
    elif args.action == "scale":
        kube("scale", "deployment/cadence", f"--replicas={args.replicas}", capture=False)
        wait_deployment("cadence")
    elif args.action == "deploy":
        migration(args.image)
        app = manifests(images)["app"][1]["spec"]["template"]["spec"]["containers"][0]
        patch = {"spec": {"template": {"spec": {"containers": [{
            "name": "cadence", "image": args.image, "resources": app["resources"]}]}}}}
        kube("patch", "deployment/cadence", "--type=strategic", "-p", json.dumps(patch), capture=False)
        wait_deployment("cadence")
        images["server"] = args.image
        (STATE / "images.json").write_text(json.dumps(images, indent=2))
    elif args.action == "mesh":
        command(["helm", "repo", "add", "chaos-mesh", "https://charts.chaos-mesh.org"], capture=False)
        command(["helm", "repo", "update", "chaos-mesh"], capture=False)
        command(["helm", "upgrade", "--install", "chaos-mesh", "chaos-mesh/chaos-mesh", "--version", "2.8.5",
                 "--kube-context", CONTEXT, "--namespace", "chaos-mesh", "--create-namespace", "-f",
                 str(HERE / "chaos-values.yaml"), "--wait", "--timeout", "5m"], capture=False)
    elif args.action == "status":
        kube("get", "pods,services,pvc,podchaos,networkchaos", capture=False)
        print(json.dumps(sample(), indent=2))
    elif args.action == "stop":
        # Preserve database volumes and experiments' recorded evidence.
        kube("delete", "podchaos,networkchaos", "--all", "--wait=true", capture=False)
        kube("scale", "deployment", "--all", "--replicas=0", capture=False)
    elif args.action == "run":
        with (STATE / "experiment.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError("Another lab experiment is still running") from error
            return run_experiment(args)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stdout or "", error.stderr or "", file=sys.stderr)
        sys.exit(1)
