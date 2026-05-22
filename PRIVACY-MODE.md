# Privacy Mode

This fork disables every feature that requires a `zed.dev` account: hosted
AI models, edit predictions (Zeta), collaboration, channels, calls, project
sharing, identified telemetry, and the AI onboarding flow. The editor,
language servers, debugger, terminal, local git, themes, extensions, and
"bring-your-own-key" LLM providers (Anthropic, OpenAI, Gemini, xAI,
DeepSeek, Ollama, LMStudio, Bedrock, OpenAI-compatible) keep working
normally.

## What was changed

### Code patch

`crates/zed/src/main.rs` — `authenticate()` stubbed:

```rust
async fn authenticate(_client: Arc<Client>, _cx: &AsyncApp) -> Result<()> {
    // Privacy mode: skip all zed.dev sign-in attempts. See PRIVACY-MODE.md.
    Ok(())
}
```

Previously this called `client.sign_in_with_optional_connect(...)` on
startup when local credentials were present. Stubbing it prevents any
automatic connection to `collab.zed.dev` / `api.zed.dev`.

The action handler in `crates/client/src/client.rs` (`SignIn` action) is
left intact — it only fires when the user manually invokes the sign-in
action, which they will not in privacy mode.

### Required user settings

Add to `~/.config/zed/settings.json` (or the workspace `.zed/settings.json`):

```json
{
  "disable_ai": true,
  "collaboration_panel": {
    "button": false
  }
}
```

- `disable_ai: true` — gates the agent panel, inline assistant, Zed Cloud
  hosted models, edit prediction Zeta UI, AI onboarding, and the Copilot
  edit-prediction UI through the existing `DisableAiSettings` checks.
- `collaboration_panel.button: false` — hides the title-bar entry point
  for the (now non-functional) collaboration panel.

## What breaks (intentional)

- Hosted AI through Zed Cloud (`language_models/src/provider/cloud.rs`).
- Edit predictions / Zeta (`edit_prediction_ui/`, `edit_prediction_cli/`).
- AI onboarding flow and Zed Pro trial banner (`ai_onboarding/`).
- Collaboration panel, channels, contacts, channel chat, channel notes
  (`collab_ui/`, `collab/`).
- Calls, rooms, project sharing (`call/`, `collab_ui/src/collab_panel.rs`).
- CLA enforcement (irrelevant without collab RPC).
- ACP auth-gated agents that route through `zed.dev`
  (`agent_ui/src/conversation_view.rs`).
- Identified telemetry — telemetry still runs but without
  `set_authenticated_user_info` since `current_user()` stays `None`.

## What keeps working

- Editor core, LSP, debugger, terminal, local git.
- Settings, themes, key bindings, Vim mode.
- Extension installation from the public registry.
- BYO-key LLM providers: Anthropic, OpenAI, Gemini, xAI, DeepSeek, Ollama,
  LMStudio, Bedrock, any OpenAI-compatible endpoint. Configure their API
  keys via the standard agent settings UI.
- GitHub Copilot (separate GitHub auth, not `zed.dev`).
- ChatGPT subscription provider (separate OpenAI auth, not `zed.dev`).
- Co-authored-by git commits — falls back to your local `user.name` /
  `user.email` from git config when `current_user()` is `None`.

## How to revert

Restore the original `authenticate()` body in `crates/zed/src/main.rs`:

```rust
async fn authenticate(client: Arc<Client>, cx: &AsyncApp) -> Result<()> {
    if stdout_is_a_pty() {
        if client::IMPERSONATE_LOGIN.is_some() {
            client.sign_in_with_optional_connect(false, cx).await?;
        } else if client.has_credentials(cx).await {
            client.sign_in_with_optional_connect(true, cx).await?;
        }
    } else if client.has_credentials(cx).await {
        client.sign_in_with_optional_connect(true, cx).await?;
    }

    Ok(())
}
```

Then remove the `disable_ai` and `collaboration_panel.button` entries
from settings if you want collab and hosted AI surfaces back.

## Verifying

Build with the project's linter wrapper:

```sh
./script/clippy
```

After launch, confirm:

- No network requests to `collab.zed.dev` or `api.zed.dev` appear in
  packet capture / proxy logs.
- `current_user()` returns `None` (collab panel shows logged-out state).
- BYO-key LLM providers still answer in the agent panel once a key is
  configured.

## CI workflows

Upstream ships 45 GitHub Actions workflows under `.github/workflows/`.
Even when their job-level `if: github.repository_owner == 'zed-industries'`
guard short-circuits the work, the workflow run still shows up in the
fork's Actions tab on every push / cron / PR / issue event, and a few
workflows have no owner guard at all. To keep the fork quiet:

- 43 upstream workflows are deleted (release pipeline, community
  management, extension publishing, collab deploy, AI evals, docs
  deploy, etc.).
- `run_tests.yml` is rewritten as a macOS-only job: `cargo fmt --check`,
  `./script/clippy`, and `cargo nextest run --workspace` on
  `macos-latest`, gated on `github.repository_owner == 'diegorv'`.
- `release_nightly.yml` is rewritten to bundle a single unsigned macOS
  aarch64 `.dmg` on a daily cron + `workflow_dispatch`, gated the same
  way. The artifact is unsigned because the fork has no Apple Developer
  credentials; macOS Gatekeeper will block first launch — right-click
  the `.app` and choose "Open" once to allow it.

GitHub's Dependabot/Dependency Graph is a separate feature from
workflows. Disable it under `Settings → Code security and analysis` on
the fork if you also want that quiet.

### Rebase conflicts on fork-managed paths

The fork owns a handful of paths that upstream also touches:

- `.github/workflows/` — 43 files deleted, two rewritten.
- `README.md` — replaced with a fork-warning README.
- `README-UPSTREAM.md` — the unmodified upstream README (renamed from
  `README.md`).
- `PRIVACY-MODE.md` and `privacy/` — fork-only, never conflict.

Upstream frequently regenerates the workflow YAMLs from
`xtask::workflows` and may update its `README.md`, so every sync would
otherwise produce conflicts in those paths. `privacy/sync-upstream.bash`
auto-resolves them by reapplying the fork's view: files present in the
fork's `HEAD` are restored via `git checkout --ours`, and files the fork
previously deleted are re-deleted. Any conflict outside the fork-managed
paths stops the script for manual resolution.

## Notes

- This is a one-way switch at the startup entry point. It does not
  remove the underlying code, so any future upstream merge keeps the
  features available — re-apply the stub after merging.
- If a future upstream change adds a second auto sign-in call outside
  `authenticate()`, this stub will not block it. Watch for new callers
  of `sign_in_with_optional_connect` in startup paths during merges.
