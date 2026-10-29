# PocketLLM

Android app (Flutter) that runs GGUF models locally via an embedded llama.cpp `llama-server`.

- **Models**: search Hugging Face (GGUF only), tap a file to download, tap play to load. Quick chips for uncensored / abliterated / roleplay models.
- **Chat**: streaming chat with an editable system prompt / character (defaults to an uncensored RP prompt).
- **Server**: one tap starts an OpenAI-compatible API (`/v1/chat/completions`, `/v1/models`, ...) as a foreground service; optional LAN exposure, port, API key, context size.

Ollama's own API is not implemented; llama-server speaks the OpenAI API, which most clients (SillyTavern, etc.) accept.

## Build

No local Android toolchain needed: push a `v*` tag (or run the workflow manually) and GitHub Actions builds llama-server with the NDK, builds the arm64 APK, and creates a draft release.
