# Status

## Tested with

| Component | Version |
|---|---|
| OpenShift | 4.22 (single node) |
| Red Hat OpenShift AI | 3.5.2 |
| Red Hat Connectivity Link (MCP gateway) | 1.5.0 (`mcp-gateway` 1.0.2) |
| Coder | 2.39.1 (Community edition, Helm chart pinned in `coder/deploy.sh`) |
| Workspace image | UBI 9, Python 3.12, code-server 4.145, Python + Jupyter extensions from Open VSX |

## Verified end to end

- The MCP gateway runs on OpenShift AI's `data-science-gateway-class`.
  `scripts/mcp-check.sh` passes (initialize → tools/list → a real tools/call).
- Coder runs under the `restricted-v2` SCC with an arbitrary UID, and so do the
  workspaces it creates from the *Python EDA Notebooks* template.
- A full Coder Agents run through the gateway:
  1. The agent called `list_templates` → `create_workspace` and created its own
     workspace.
  2. It used the gateway's `discover_tools`, then made three `weather_history`
     calls.
  3. It saved the CSVs byte-identical to `analysis/data/` and verified their
     checksums.
  4. It read the `eda-notebook` skill and built an executed notebook: 0 errors,
     every finding matching `analysis/results.md`.

The model in the verified run was an OpenAI-compatible endpoint with tool calling
and a 40,000-token context. Serving a model on OpenShift AI behind
Models-as-a-Service (`model/`) follows the standard
[rhoai-maas-guide](https://github.com/rh-aiservices-bu/rhoai-maas-guide) flow.

## Known limitations

- **Coder blocks MCP servers on private IPs** (since 2.39.1). Inside the cluster
  the gateway Route resolves to a private address, so `coder/deploy.sh` exempts
  exactly that address with `CODER_MCP_ALLOWED_PRIVATE_CIDRS`. Whether the same
  check applies to a model provider on a private IP (MaaS at `maas.<domain>`) has
  not been tested.
- **The MCP gateway and the 2026 MCP protocol.** Connectivity Link 1.5 shows a
  server's tools only to clients on the protocol version it negotiated with that
  server, and Coder 2.39 uses the earlier version. The weather server therefore
  refuses the `2026-07-28` protocol (`ClassicProtocolOnly` in
  `mcp/weather/server.py`; set `MCP_ALLOW_2026=1` to lift it later).
- **Smaller models** may try to run commands before a workspace exists. The
  deployment instruction in QUICKSTART step 6.5 prevents this.
- **Context window**: Coder Agents ask for up to 32,000 output tokens per
  request, so the model needs a context of about 40,000 tokens or more, or a
  lower *Max Output Tokens* in Coder.
- **Open-Meteo** is the one external call (weather data). Its free tier is for
  non-commercial use.
