# Any Civitai SDXL model — RunPod Serverless worker

A ready-to-build [RunPod Serverless](https://runpod.io?ref=qpguwapm) worker for **any SDXL-family checkpoint on Civitai or Hugging Face** — SDXL, Pony, Illustrious and NoobAI models. You paste the model's Civitai or Hugging Face link into the `Dockerfile`; the build downloads that model and bakes it into the image. Based on the official [`runpod/worker-comfyui`](https://github.com/runpod-workers/worker-comfyui).

> Some Civitai models are 18+. You download them with your own Civitai account and are responsible for following each model's license.

## What it takes

- A **Checkpoint** whose base model is SDXL, Pony, Illustrious or NoobAI. Flux, SD 1.5, SD 3.5, video models, LoRAs and others are refused at build time with a clear message — they need a different workflow.
- The model's primary SafeTensor file. It is checked by SHA-256 against Civitai and saved as `checkpoints/model.safetensors`; `model.json` next to it records which model and version it is.
- On Hugging Face: a repo with a single-file checkpoint (a `.safetensors` of the whole model at its top, as most SDXL repos have next to their diffusers folders). The smallest one is taken (fp16 rather than fp32); link a file (`…/blob/main/<file>`) to pick another. A repo with only diffusers folders is refused. A gated repo needs `HF_TOKEN=<a Read token>` in `civitai.env`.

No extra nodes, no upscalers — SDXL runs on the ComfyUI of the base image. LoRAs: see [LoRAs](#loras).

## Setup (about 10 minutes + build time)

New to this? Follow the [step-by-step setup guide](https://cobaltpear.github.io/guide.html).

1. **Make your own private copy** — click **Use this template** → **Create a new repository** → choose **Private**.
   (Your Civitai token will be in it, so it must stay private. A Hugging Face model needs no token.)
2. **Fill in two lines** of `Dockerfile` in your copy (✏️ edit → Commit):
   - `PASTE_YOUR_CIVITAI_TOKEN_HERE` → your token (civitai.com → Account settings → Security & Apps → API Keys). Leave it for a Hugging Face model.
   - `PASTE_THE_MODEL_LINK_HERE` → the model's page link, e.g. `https://civitai.com/models/257749?modelVersionId=290640`. A link without `modelVersionId` takes the newest version; a plain version number works too. Or a Hugging Face link, e.g. `https://huggingface.co/SG161222/RealVisXL_V5.0`.

   Using [Cobalt Pear](https://cobaltpear.github.io/)? It gives you two links instead: one makes your private copy, the other opens a new file `civitai.env` with the model filled in — paste your token (none for a Hugging Face model), Commit. That file wins over the `Dockerfile` lines.

   No RunPod account yet? [Sign up here](https://runpod.io?ref=qpguwapm) — a referral link: after you first add $10, RunPod gives you a bonus credit (usually $5–10) and this repo a small credit.
3. **Create the endpoint** — see [Create the endpoint](#create-the-endpoint) below.
4. **Create an API key** — RunPod → Settings → API Keys → **Restricted**, allow only this endpoint.

One endpoint = one model. For another model, make another copy (or change the link and rebuild).

## Create the endpoint

RunPod → **Serverless** → **New Endpoint** → **Deploy from a GitHub repository** → pick your copy (the first time, **Edit connection** lets RunPod see it). Then, top to bottom on the page:

| Where on the page | What to set |
|---|---|
| **Endpoint name** | anything — your copy's name is fine |
| **GPU configuration** | tick a **16 GB** or **24 GB** box (more boxes = easier to get a GPU) |
| **Max workers** | `1` |
| Click **Advanced settings** to open it: | |
| → **Active workers** | `0` — nothing to pay while idle |
| → **GPU count** | `1` |
| → **Idle timeout** | `5` sec — or longer if you make several in a row (see below) |
| → **Enable FlashBoot** | on (the switch) · **Standard** |
| → **Enable execution timeout** | on · **Execution timeout** `600` sec |
| → click **Container configuration** to open it → **Container disk** | `20` GB |

Leave everything else as it is, then **Deploy** at the bottom. The first build takes about 15 minutes.
<!-- cp:initializing first=request -->
The very first request after that waits while a worker pulls the image — this can take a long time. The worker shows **Initializing**. To see what it's doing: endpoint page → **Workers** → click the worker → **Logs** → **System**.

- No error → leave it. A big image can sit on one line for a long time. Lines starting with `INFO` are normal.
- The same error keeps repeating → delete that worker with the 🗑 icon at the right end of its row. RunPod starts a new one.
- Still failing after that → ask us in [Discussions](https://github.com/cobaltpear/cobaltpear.github.io/discussions) with a screenshot of the log, or the whole log.
<!-- /cp:initializing -->

**Making several in a row?**

<!-- cp:several result=result -->
RunPod turns the worker off 5 seconds after each result (**Idle timeout** `5` sec). The next request then waits while a worker starts and loads the model again. It may be the same machine or a different one, so this wait can be short or long.

If you look at a result and send the next one soon after, set **Idle timeout** higher, for example `300` sec (endpoint page → **Manage** → **Edit Endpoint** → **Advanced settings**). The worker then stays on for that long after each result, and the next one starts right away. You pay for that time too, so set it back to `5` when you're done.

In short: `5` sec means you wait at each start and pay nothing while idle. Longer means no wait, and you pay while it waits for you.
<!-- /cp:several -->

## Or run it on Modal

The same worker also runs on [Modal](https://modal.com) — another serverless GPU service, billed by the second — from `modal_app.py` in this repo. It builds the same `Dockerfile` and answers the same requests as on RunPod (`/run`, `/status/<id>`), so a client that calls RunPod endpoints needs only the other address and key.

On your computer, with Python 3.10 or newer, in a copy of your repo (`git clone` it, with your `civitai.env` or `Dockerfile` lines filled in):

```sh
pip install modal
modal setup                                                   # opens a page to sign in to Modal
modal secret create cobaltpear-key CP_KEY=<a long password you make up>
modal deploy modal_app.py                                     # builds, then prints the worker's address
```

- The address ending in `-api….modal.run` is your endpoint; send `Authorization: Bearer <that password>` with each request.
- GPU: the `GPU` line at the top of `modal_app.py` (24 GB by default). A worker turns off 60 s after its last picture.
- Modal needs a payment method on your account to use GPUs. Its prices: [modal.com/pricing](https://modal.com/pricing).
- Updates: run `modal deploy modal_app.py` again.

## Updates

Your copy only holds the token and the link. The build steps (`build.sh`, `handler.py`) are downloaded from this repo on every build, so fixes here reach you when you rebuild.

To rebuild: commit any change to the `main` branch of your copy — RunPod builds again on every push to `main` (the endpoint's **Builds** tab shows it). Nothing to change? Edit `README.md` (✏️), add a line, **Commit changes…** → **Commit changes**.

## Use it

Any client that sends ComfyUI API-format workflows to RunPod works. `pack.json` in this repo holds a plain SDXL workflow (Euler a, 25 steps, CFG 6, clip skip 2) and tells a client where the prompt, negative, seed and size go (format `pack/1`, engine `comfyui`).

Raw request:

```bash
curl -X POST https://api.runpod.ai/v2/<ENDPOINT_ID>/runsync \
  -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" \
  -d "{\"input\": {\"workflow\": $(jq .workflow pack.json | jq '.["6"].inputs.text = "a girl reading a book in a cafe" | .["3"].inputs.seed = 1')}}"
```

The image comes back as base64 in `output.images[0].data`.

Each model has its own best settings — see its Civitai page (sampler, steps, CFG, clip skip, trigger words).

### LoRAs

- **Per picture:** send up to 4 LoRAs with a request: `input.remote_loras` = `[{"name": "remote_<id>.safetensors", "url": "<download link>", "sha256": "<file sha256>"}]` plus a `LoraLoader` reading that name in the workflow — the worker downloads each once and keeps it while it runs. [Cobalt Pear](https://cobaltpear.github.io/) does all of this from a Civitai or Hugging Face link. For more than 4, set the environment variable `REMOTE_LORA_MAX` (e.g. `8`) on your endpoint (**Manage → Edit Endpoint → Environment Variables**).
- **Built in:** put links in the `LORAS` line of your `Dockerfile` — each followed by its strength — and rebuild. They are downloaded once at build time, so a fresh worker doesn't download them again. A request picks which ones it uses with `input.baked_loras` = `[{"link": "<link from LORAS>", "strength": 0.8}]` (`[]` = none); without it every one is used at its `LORAS` strength. One that isn't built in (yet) is left out and named in `output.warning`, and `output.built_in` lists the built-in LoRAs. Put their trigger words in your prompt yourself. To accept only built-in LoRAs, set `REMOTE_LORA_MAX` to `0`.
- Pick LoRAs made for SDXL (Pony, Illustrious …) — the worker warns (`output.warning`) when one doesn't fit.

### Compatible clients

- [Cobalt Pear](https://cobaltpear.github.io/) — a one-page web app. Paste the same Civitai link under **Models → Custom**: it reads the creator's settings from Civitai and sets steps, CFG, sampler, clip skip and negative for that model. Everything stays in your browser. [Try the demo](https://cobaltpear.github.io/demo/) without RunPod.

<!-- cp:page-changes -->
RunPod and Civitai change their pages from time to time. If a button or step here looks different from what you see, tell us in [Discussions](https://github.com/cobaltpear/cobaltpear.github.io/discussions) and we'll update this guide.
<!-- /cp:page-changes -->

Questions or ideas: [Discussions](https://github.com/cobaltpear/cobaltpear.github.io/discussions).

## License

AGPL-3.0 ([LICENSE](LICENSE)). This worker is based on [runpod-workers/worker-comfyui](https://github.com/runpod-workers/worker-comfyui) (AGPL-3.0), and `handler.py` is a changed copy of its handler. The models you build into it keep their own licenses.
