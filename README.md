![Copal_Banner](./assets/copal_banner.png)

# Copal
*[copal.run](https://copal.run)*

**Copal** is a powerful, modular AI Agent Swarm framework written in **Luau**, designed to run on the **Lune** runtime. It orchestrates hierarchies of AI models—from low-cost worker swarms to high-intelligence directors—to solve complex tasks autonomously.

## Features

-   **Hierarchy of Intelligence**:
    -   **Swarm Mode**: A group of cost-effective agents (e.g., `gpt-4o-mini`, `grok-code`) executing subtasks in parallel.
    -   **Director Mode**: A supervisor agent (e.g., `claude-3-5-sonnet`) that plans, delegates, **reviews**, and **retries** work until the goal is met.
    -   **Company Mode**: Top-level CEO orchestration for massive multi-swarm operations.
-   **Interactive TUI**: Beautiful terminal interface with ANSI graphics, masked password entry, and live status updates.
-   **Smart Setup Wizard**:
    -   Auto-fetches available models from your provider.
    -   Search & Filter model lists (type to search!).
    -   Securely encrypts and stores API keys.
-   **Robust Tooling**:
    -   File System (Read/Write/List).
    -   Terminal (Run Commands).
    -   **Inter-Agent Communication**: Agents can `broadcast` messages to collaborate.
    -   **Validation**: Built-in schema checking to prevent hallucinations.
-   **Provider Agnostic**: Works with **OpenRouter**, **OpenCode**, **OpenAI**, or any **Custom** OpenAI-compatible endpoint.

## Installation

Copal requires [Lune](https://lune-org.github.io/docs), a standalone Luau runtime.

1.  **Install Lune** (if not installed):
    ```bash
    # Windows (Scoop)
    scoop bucket add lune https://github.com/CompeyDev/lune-packaging.git
    scoop install lune
    # Rokit
    rokit add lune --global
    # crates.io
    cargo binstall lune
    # or
    cargo install lune --locked
    # macOS/Linux (Homebrew)
    brew install lune
    ```

2.  **Clone the Repository**:
    ```bash
    git clone https://github.com/Naymmmm/copal.git
    cd copal
    ```

3.  **Run Setup**:
    ```bash
    lune run src/main.luau
    ```
    Follow the wizard to select your provider (e.g., OpenRouter) and enter your API key.

Alternatively, you can use the pesde registry, which is recommended.
```bash
# Download pesde
https://github.com/pesde-pkg/pesde/releases/tag/v0.7.2+registry.0.2.3

# chmod +x if on Unix
chmod +x pesde

# Install pesde
pesde self-install

# Run copal
pesde x naymmmm/copal
```

## Usage

### Interactive Mode (Recommended)
Simply run the main script to enter the interactive menu:
```bash
lune run src/main.luau
```
You can select:
1.  **Swarm Mode**: Good for "do this specific thing" tasks.
2.  **Director Mode**: Best for specific goals requiring planning and review.
3.  **Company Mode**: Experimental high-level orchestration.
4.  **Settings**: Change providers, update keys, or switch models.

### CLI Arguments
You can bypass the menu for automation:

```bash
# Run a specific task with a swarm
lune run src/main.luau -- --mode swarm --task "Analyze the src folder and write a report"

# proper planning with Director
lune run src/main.luau -- --mode director --goal "Refactor the authentication module"
```

## Configuration

Copal stores configuration in `~/.copal_config.json` (Home Directory). You can edit this file manually or use the **Settings** menu in the app.

### Supported Providers
-   **OpenRouter** (Recommended for model variety)
-   **OpenAI**
-   **OpenCode**
-   **Custom** (LocalLLM / LM Studio / Ollama) -> Set URL to `http://localhost:1234/v1`

## Troubleshooting

-   **400 Bad Request**: Ensure you are using a model that supports Tool Calling. We have implemented fixes for strict models (like Grok), but some local models may still struggle.
-   **"Tool not found"**: The agent may be hallucinating a tool name. The Director's review loop helps catch this.
-   **Network Errors**: Check your `Custom` provider URL or ensure your API key has credits.

## License
Apache 2.0
