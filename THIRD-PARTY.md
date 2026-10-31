# Third-party software

Lucky's custom editor and Windows packaging code are MIT licensed. The shipped runtime and optional AI connector are unmodified upstream software; their original licenses and attribution remain in `licenses/`.

| Component | Pinned release | Source | License |
| --- | --- | --- | --- |
| Godot Windows x64 runtime | 4.7.2-stable, commit ed1daf0bf | https://github.com/godotengine/godot/tree/4.7.2-stable | MIT; bundled dependencies have additional notices in GODOT-COPYRIGHT.txt |
| Optional Codex app-server package | rust-v0.166.0, Windows x64 | https://github.com/openai/codex/tree/rust-v0.166.0 | Apache-2.0; CODEX-LICENSE.txt and CODEX-NOTICE.txt |

The optional connector contains its upstream companion executables and search utility. No language model, subscription, account credentials, provider endorsement, or paid plugin is included. The connector is an independent local process used by Lucky's chat panel; inference is supplied by the user's provider account.

All new UI artwork is drawn from simple geometric primitives and text. No third-party proprietary artwork or font files are bundled. Fonts resolve from the host system or Godot's included fallback.

Download origins and checksums are recorded in SOURCE-MANIFEST.json. Portable game exports include the Godot license notices; they do not include the AI connector.
