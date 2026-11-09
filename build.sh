#!/bin/sh
# SDXL Universal (any SDXL checkpoint from Civitai or Hugging Face) — everything the worker image needs. The Dockerfile in your copy downloads this file
# from the original repo on every build, so fixes made there reach you with a rebuild.
# The same file serves civitai-sdxl, civitai-illustrious, civitai-noobai and civitai-pony; only the next line differs.
WORKER=sdxl
set -eu
# civitai.env in your copy (made by Cobalt Pear's «Add your token» link) wins over the two Dockerfile lines
if [ -f /setup/civitai.env ]; then
  for k in CIVITAI_TOKEN CIVITAI_MODEL HF_TOKEN; do
    v=$(sed -n "s/^[[:space:]]*$k[[:space:]]*=//p" /setup/civitai.env | tr -d '\r"'"'"' ' | head -n 1)
    [ -z "$v" ] || eval "$k=\$v"
  done
fi
export CIVITAI_TOKEN CIVITAI_MODEL HF_TOKEN WORKER
case "${CIVITAI_MODEL:-}" in ""|PASTE_*) echo "ERROR: put the model in civitai.env (or at the top of the Dockerfile) — its Civitai page link or version number, or its Hugging Face link" >&2; exit 1;; esac

# Find the one file the link means, check it is a checkpoint of this worker's base model, then download it and check its SHA-256.
# Civitai: its API names the file. Hugging Face: the repo's single-file checkpoint (a .safetensors at its top, not the diffusers folders).
# The checkpoint is always saved as model.safetensors — the pack's workflow loads that name.
python3 - <<'PY'
import hashlib, json, os, re, struct, sys, urllib.request
token, link, hf_token, worker = os.environ.get("CIVITAI_TOKEN", ""), os.environ["CIVITAI_MODEL"].strip(), os.environ.get("HF_TOKEN", ""), os.environ["WORKER"]
def fail(msg): sys.exit("ERROR: " + msg)
# SDXL-family base models on Civitai → the worker made for each (they share this file and the SDXL architecture)
TAKES = {"sdxl": "SDXL 1.0 checkpoints (and SDXL Lightning, Turbo and Hyper)", "illustrious": "Illustrious checkpoints", "noobai": "NoobAI checkpoints", "pony": "Pony checkpoints"}
def route(base): return {"Pony": "pony", "Illustrious": "illustrious", "NoobAI": "noobai"}.get(base) or ("sdxl" if base.startswith("SDXL") else None)
def refuse(base):
    other = route(base)
    fail(f"this model's base is {base} — " + (f"use cobaltpear/civitai-{other} for it (this worker takes {TAKES[worker]} only)" if other else f"this worker takes {TAKES[worker]} only"))
# v-pred checkpoints (most are NoobAI-based) need two empty marker tensors that ComfyUI looks for; merges often lose them
def vpred_fix(path, name):
    if not re.search(r"v[-_ .]?pred", name, re.I): return
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]; head = json.loads(f.read(n))
    if "v_pred" in head: print("v-pred: the file says so itself"); return
    end = max(v["data_offsets"][1] for k, v in head.items() if k != "__metadata__")
    for k in ("v_pred", "ztsnr"): head[k] = {"dtype": "F32", "shape": [0], "data_offsets": [end, end]}
    h = json.dumps(head, separators=(",", ":")).encode(); h += b" " * (-len(h) % 8)
    with open(path, "rb") as src, open(path + ".tmp", "wb") as out:
        out.write(struct.pack("<Q", len(h))); out.write(h); src.seek(8 + n)
        while chunk := src.read(1 << 24): out.write(chunk)
    os.replace(path + ".tmp", path); print("v-pred: marked the file as v-prediction (zero terminal SNR), as its name says")
def download(url, dest, sha, name, headers={}):
    h = hashlib.sha256()
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "cobaltpear", **headers}), timeout=600) as r, open(dest, "wb") as out:
        while chunk := r.read(1 << 22): h.update(chunk); out.write(chunk)
    if sha and h.hexdigest() != sha: fail(f"{name} does not match its SHA-256 — try the build again")
    print("SHA-256 OK" if sha else "No SHA-256 listed for this file — not checked")
dest = "/comfyui/models/checkpoints/model.safetensors"
hf = None if "civitai.com" in link or re.fullmatch(r"\d+", link) else \
    re.fullmatch(r"(?:https?://huggingface\.co/)?([\w.-]+/[\w.-]+)(?:/(?:blob|resolve|tree)/[^/]+(?:/(.+?))?)?/?(?:\?.*)?", link)
if hf:
    repo, want = hf.group(1), hf.group(2)
    auth = {"Authorization": "Bearer " + hf_token} if hf_token and not hf_token.startswith("PASTE_") else {}
    def get(url, **kw):
        try: return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "cobaltpear", **auth, **kw}), timeout=60)
        except urllib.error.HTTPError as e:
            fail(f"Hugging Face answered {e.code} for {repo}" + (" — it is gated: accept its license on its page and put HF_TOKEN=<a Read token> in civitai.env" if e.code in (401, 403) else ""))
    info = json.load(get(f"https://huggingface.co/api/models/{repo}?blobs=true"))
    files = [f for f in info.get("siblings", []) if f["rfilename"].endswith(".safetensors") and (f["rfilename"] == want if want else "/" not in f["rfilename"])]
    files = [f for f in files if f.get("size", 0) > 3e9 or want]  # a whole checkpoint, not a VAE or a LoRA
    if not files: fail(f"{repo} has no single-file checkpoint (.safetensors) at its top — it only has diffusers folders, which this worker can't load")
    f = min(files, key=lambda f: f.get("size", 0))  # fp16 rather than fp32
    url = f"https://huggingface.co/{repo}/resolve/main/{f['rfilename']}"
    head = get(url, Range="bytes=0-7").read(); n = struct.unpack("<Q", head)[0]
    keys = json.loads(get(url, Range=f"bytes=8-{7 + n}").read())
    if not any(k.startswith("conditioner.embedders.1.") for k in keys): fail(f"{f['rfilename']} is not an SDXL-family checkpoint — this worker takes {TAKES[worker]} only")
    print(f"Hugging Face: {repo} — {f['rfilename']}")
    print(f"Downloading {f['rfilename']} ({f.get('size', 0) / 1e9:.1f} GB)")
    download(url, dest, (f.get("lfs") or {}).get("sha256", ""), f["rfilename"], auth)
    vpred_fix(dest, repo + "/" + f["rfilename"])
    # Hugging Face doesn't say which SDXL-family base a checkpoint is, so every one of these workers takes any SDXL-architecture file
    json.dump({"repo": repo, "name": repo.split("/")[-1], "file": f["rfilename"], "base": "SDXL"}, open("/comfyui/models/checkpoints/model.json", "w"))
    sys.exit(0)
if not token or token.startswith("PASTE_"): fail("put your Civitai token in civitai.env (or at the top of the Dockerfile)")
def get(path):
    req = urllib.request.Request("https://civitai.com/api/v1/" + path, headers={"Authorization": "Bearer " + token, "User-Agent": "cobaltpear"})
    try: return json.load(urllib.request.urlopen(req, timeout=60))
    except Exception as e: fail(f"could not ask Civitai about {link!r} ({e})")
def signed(f): return f["downloadUrl"] + ("&" if "?" in f["downloadUrl"] else "?") + "token=" + token
def opens(f):  # Early Access files answer 401/403 until you pay Buzz on Civitai
    try: urllib.request.urlopen(urllib.request.Request(signed(f), headers={"Range": "bytes=0-7", "User-Agent": "cobaltpear"}), timeout=120).read(); return True
    except urllib.error.HTTPError as e:
        if e.code in (401, 403): return False
        raise
def checkpoint(v):
    files = [f for f in v.get("files", []) if f.get("type") == "Model" and f.get("metadata", {}).get("format") == "SafeTensor"]
    return next((f for f in files if f.get("primary")), files[0] if files else None)
m = re.search(r"modelVersionId=(\d+)", link) or re.fullmatch(r"(\d+)", link)
if m: version = get(f"model-versions/{m.group(1)}")
else:
    m = re.search(r"/models/(\d+)", link) or fail(f"CIVITAI_MODEL {link!r} is not a Civitai model link")
    vs = get(f"models/{m.group(1)}")["modelVersions"]
    # the newest version made for this worker's base (one model page can hold versions for several bases)
    mine = [v for v in vs if route(v.get("baseModel", "")) == worker]
    if not mine: refuse(vs[0].get("baseModel", "?"))
    v = next((v for v in mine if checkpoint(v) and opens(checkpoint(v))), None) or fail("no SDXL version of this model has a file your token can download (Early Access versions need Buzz on Civitai)")
    version = get(f"model-versions/{v['id']}")
base, kind = version.get("baseModel", ""), version.get("model", {}).get("type", "")
print(f"Civitai: {version.get('model', {}).get('name')} — {version.get('name')} (version {version['id']}, {base}, {kind})")
if kind != "Checkpoint": fail(f"this is a {kind}, not a Checkpoint")
if route(base) != worker: refuse(base)
f = checkpoint(version) or fail("no .safetensors checkpoint file in this version")
if not opens(f): fail("Civitai won't let your token download this version — it may be in Early Access (pay with Buzz on its page) — pick another version")
print(f"Downloading {f['name']} ({f.get('sizeKB', 0) / 1e6:.1f} GB)")
download(signed(f), dest, f.get("hashes", {}).get("SHA256", "").lower(), f["name"])
vpred_fix(dest, f"{version.get('model', {}).get('name')} {version.get('name')} {f['name']}")
json.dump({"version": version["id"], "name": version.get("model", {}).get("name"), "file": f["name"], "base": base}, open("/comfyui/models/checkpoints/model.json", "w"))
PY
# SDXL-family models run on the ComfyUI of the base image as is
