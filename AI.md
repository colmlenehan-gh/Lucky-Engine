# Lucky AI beta

Lucky contains a chat sidebar inside the editor window. The implemented transport is the open-source Codex app-server protocol, using a compatible connector executable and a signed-in ChatGPT account. Setup offers the official Codex app-server connector as an optional offline component. Lucky does not request an API key, download a model, intercept another application's window, or scrape a website. Having ChatGPT installed does not by itself guarantee that a compatible app-server executable or reusable sign-in is present.

## Connect

1. Open a Lucky project, then open AI.
2. Press Connect. Lucky first checks the optional bundled connector, then PATH and standard per-user Codex/ChatGPT installation folders.
3. If discovery fails, choose the executable in AI settings. Select `codex-app-server.exe` or `codex.exe`, not the desktop application's UI executable or a command wrapper.
4. Use Sign in if the account is not already available. The user-initiated sign-in opens the provider's authentication page; the chat stays in Lucky.

The optional connector is upstream Codex app-server v0.166.0 with its companion executables. It occupies approximately 460 MB and does not contain a local language model. Setup can omit it when a compatible installation already exists. Subscription eligibility, organization policy, connectivity, usage limits and the connector version control availability. Existing API-key accounts are not accepted by this integration. No authenticated inference was performed during package creation. The official connector was tested for initialization and public model metadata using an empty isolated configuration directory.

## Models, effort and speed

Lucky asks the connected app-server for its model catalog, input modalities and supported reasoning efforts. Names are not manufactured or used to suggest an unavailable model is supported. The exact catalog is account-dependent. Fast is enabled only when the selected model advertises the priority/fast service tier. It requests `serviceTier: "priority"`; switching it off clears the previous turn's tier. A faster tier can use more of the subscription allowance, and actual speed and eligibility remain provider-controlled. This mapping was checked against the bundled connector's public catalog and request validation; live inference speed was not measured.

Claude Code, Cursor, Grok and OpenCode require separate supported adapters and their own account authorization. They are not functional providers in this beta. GPT, Fable and other labels cannot be interchanged merely by changing a dropdown.

## Attachments and plugins

PNG, JPEG, WebP and GIF images use app-server local-image input. Text/code attachments up to 256 KB are included as text. Other binary formats are rejected, rather than silently pretending to upload them. Selected files are sent to the connected AI service when the user presses Send.

Configured MCP servers are discovered from the provider's existing configuration using `mcpServerStatus/list`. Their availability and sign-in state remain controlled by that provider. Lucky can add an HTTPS MCP server by name and URL and request OAuth for a configured server. Adding a server updates the connected provider's shared `mcp_servers` configuration, then reloads it. Reusing a server name updates that entry's URL; it is not isolated to one Lucky project. Local stdio server installation and arbitrary plugin-package installation are not part of this beta.

Chats use read-only project access and deny execution/file-change approval requests. This beta provides assistance and code suggestions; it does not automatically apply edits. Existing MCP tools remain subject to provider configuration and server permissions. Review a server's permissions before enabling it in Codex.

## Sources and distribution

- [Official app-server documentation](https://learn.chatgpt.com/docs/app-server): transport, authentication, models, turns, streaming events and MCP discovery.
- [Sign in with ChatGPT integration guidance](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server): the supported direction for deeper integrations.
- [Official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference): advertised service tiers and Fast-to-priority mapping.
- [Upstream Codex source and releases](https://github.com/openai/codex): source and distribution for the optional connector.
- [Godot OS process API](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-execute-with-pipe): local nonblocking process pipes.

This local open-source beta uses app-server authentication as documented. Commercial or hosted distribution requires reviewing OpenAI's integration requirements and adopting Sign in with ChatGPT where required. No claim of affiliation with any AI provider is made.
