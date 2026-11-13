terraform {
  required_providers {
    coder      = { source = "coder/coder" }
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

# Runs inside the Coder control-plane pod, so in-cluster config is used.
provider "kubernetes" {}

variable "namespace" {
  type        = string
  description = "Namespace workspace pods are created in."
  default     = "coder"
}

variable "storage_class" {
  type        = string
  description = "StorageClass for the home volume. Empty = the cluster's default StorageClass."
  default     = ""
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Git repository"
  description  = "Optional. Cloned into ~/workspace on first start. Leave empty for data/EDA work (the weather demo)."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 1
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU cores"
  description  = "2 is plenty for pandas on small CSVs."
  type         = "number"
  default      = "2"
  mutable      = true
  order        = 2
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GiB)"
  description  = "4 is plenty for pandas on small CSVs."
  type         = "number"
  default      = "4"
  mutable      = true
  order        = 3
}

# VS Code in the browser, with the Python + Jupyter extensions baked into the
# image. This is where the user opens the notebook the agent built.
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code (notebooks)"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"
  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 15
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  # Coder Agents' working directory. AGENTS.md (and .mcp.json, if any) are
  # discovered at the TOP LEVEL of this directory, and `execute` starts here.
  dir = "/home/coder/workspace"
  # The agent (and Coder Agents' create_workspace) waits for this script, so
  # AGENTS.md and the skill exist before the first chat turn reads context.
  # Keep it fast: the editor is started in the background.
  startup_script_behavior = "blocking"

  # Git author for anything the agent commits; Coder Agents never override it.
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script = <<-EOT
    # NOT `set -e`: a failure in a nice-to-have step must not stop the
    # workspace from coming up.
    set -u
    WS=/home/coder/workspace

    # ---- 1. code -------------------------------------------------------
    # Clone once. On restart the PVC already holds the repo and the agent's work.
    if [ ! -d "$WS" ]; then
      if [ -n "${data.coder_parameter.repo_url.value}" ]; then
        git clone "${data.coder_parameter.repo_url.value}" "$WS" || mkdir -p "$WS"
      else
        mkdir -p "$WS"
      fi
    fi
    mkdir -p "$WS/data" "$WS/notebooks"
    git config --global --add safe.directory "$WS" 2>/dev/null || true

    # ---- 2. context for Coder Agents ------------------------------------
    # From the image (workspace-image/agent-context/). Copied only if missing,
    # so edits made in the workspace survive a restart; delete a file to get
    # the image's version back.
    [ -f "$WS/AGENTS.md" ] || cp /opt/agent-context/AGENTS.md "$WS/AGENTS.md"
    mkdir -p /home/coder/.coder/skills
    for d in /opt/agent-context/skills/*/; do
      name=$(basename "$d")
      [ -d "/home/coder/.coder/skills/$name" ] || cp -r "$d" "/home/coder/.coder/skills/$name"
    done

    # ---- 3. VS Code (notebooks) -----------------------------------------
    SETTINGS=/home/coder/.local/share/code-server/User/settings.json
    if [ ! -f "$SETTINGS" ]; then
      mkdir -p "$(dirname "$SETTINGS")"
      cat > "$SETTINGS" <<'JSON'
    {
      "python.defaultInterpreterPath": "/usr/bin/python3.12",
      "jupyter.kernels.excludePythonEnvironments": [],
      "security.workspace.trust.enabled": false,
      "workbench.startupEditor": "none",
      "telemetry.telemetryLevel": "off",
      "chat.disableAIFeatures": true,
      "workbench.secondarySideBar.defaultVisibility": "hidden",
      "files.exclude": {"**/.ipynb_checkpoints": true}
    }
    JSON
    fi
    nohup code-server --auth none --disable-telemetry --disable-update-check \
      --extensions-dir /opt/code-server/extensions \
      --bind-addr 127.0.0.1:13337 >/tmp/code-server.log 2>&1 &
  EOT

  metadata {
    display_name = "Running as UID"
    key          = "uid"
    script       = "id -u"
    interval     = 600
    timeout      = 5
  }
}

# Persists across workspace stop/start. Everything outside /home/coder is
# ephemeral.
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-home-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class != "" ? var.storage_class : null
    resources {
      requests = { storage = "10Gi" }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = lower(data.coder_workspace.me.name)
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/instance" = lower(data.coder_workspace.me.name)
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = lower(data.coder_workspace.me.name)
        }
      }
      spec {
        # NOTE: deliberately NO security_context, at pod or container level.
        # restricted-v2 assigns UID, GID and fsGroup from the project's range;
        # setting them -- as the upstream Kubernetes template does -- gets the
        # pod rejected by SCC admission.

        # The workspace never talks to the Kubernetes API, and holds no model
        # URL or API key. Data arrives through MCP tools called by the agent
        # in the control plane; the workspace only runs the analysis code.
        automount_service_account_token = false

        container {
          name  = "dev"
          image = "image-registry.openshift-image-registry.svc:5000/coder/coder-workspace:latest"

          # entrypoint.sh named EXPLICITLY: a Kubernetes `command` overrides the
          # image's ENTRYPOINT, so without it the arbitrary-UID passwd fixup
          # silently never runs. It ends in `exec "$@"`.
          command = [
            "/usr/local/bin/entrypoint.sh",
            "/bin/bash", "-c", coder_agent.main.init_script,
          ]

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          # The agent is CGO-free Go, so user.Current() falls back to $USER;
          # without it the agent never reports healthy.
          env {
            name  = "USER"
            value = "coder"
          }
          env {
            name  = "HOME"
            value = "/home/coder"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "${data.coder_parameter.cpu.value}"
              memory = "${data.coder_parameter.memory.value}Gi"
            }
          }

          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
          }
        }
      }
    }
  }
}
