# Terminal Chat Example

Standalone terminal conversation app built with `TermUI`.

Features:

- chat with an LLM (Anthropic Messages API, Opus by default)
- `/search <query>` web search tool call (Wikipedia API)
- `/cancel` to cancel any in-flight chat/search request
- `/quit` (or `Ctrl+C`) to exit

## Prerequisites

- Elixir 1.19+
- OTP 28+
- `ANTHROPIC_API_KEY` set in your shell if you want LLM responses
- `ANTROPIC_API_KEY` is also accepted for compatibility
- optional: `ANTHROPIC_MODEL` (defaults to `claude-opus-4-1-20250805`)

## Run

```bash
cd examples/terminal_chat
mix deps.get
mix run run.exs
```

## Commands

- type plain text to send a chat prompt
- `/search latest elixir release`
- `/cancel`
- `/quit`
