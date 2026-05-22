# Zed — Personal Privacy Fork

> [!CAUTION]
> **This is a personal fork for proof-of-concept work and individual use.**
> It is **not recommended for general use**. zed.dev sign-in is stubbed
> out, which disables hosted AI, edit predictions (Zeta), collaboration,
> channels, calls, project sharing, identified telemetry, and the AI
> onboarding flow.
>
> For the upstream project, see <https://github.com/zed-industries/zed>.

## What this fork is

- The Zed editor with every feature that requires a `zed.dev` account
  switched off at the startup entry point.
- Bring-your-own-key LLM providers (Anthropic, OpenAI, Gemini, xAI,
  DeepSeek, Ollama, LMStudio, Bedrock, OpenAI-compatible), GitHub
  Copilot, and the ChatGPT subscription provider keep working.

## Where things live

- The unmodified upstream README is in [README-UPSTREAM.md](./README-UPSTREAM.md).
- The rationale, required settings, breakage scope, and revert steps
  are in [PRIVACY-MODE.md](./PRIVACY-MODE.md).
- The script that keeps this fork in sync with
  [zed-industries/zed](https://github.com/zed-industries/zed) is at
  [`privacy/sync-upstream.bash`](./privacy/sync-upstream.bash).
