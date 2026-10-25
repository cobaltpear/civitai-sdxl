#!/bin/sh
# Any Civitai SDXL model — everything the worker image needs. The Dockerfile in your copy downloads this file
# from the original repo on every build, so fixes made there reach you with a rebuild.
set -eu
# civitai.env in your copy (made by Cobalt Pear's «Add your token» link) wins over the two Dockerfile lines
if [ -f /setup/civitai.env ]; then
  for k in CIVITAI_TOKEN CIVITAI_MODEL; do
    v=$(sed -n "s/^[[:space:]]*$k[[:space:]]*=//p" /setup/civitai.env | tr -d '\r"'"'"' ' | head -n 1)
    [ -z "$v" ] || eval "$k=\$v"
  done
fi
export CIVITAI_TOKEN CIVITAI_MODEL
case "${CIVITAI_TOKEN:-}" in ""|PASTE_*) echo "ERROR: put your Civitai token in civitai.env (or at the top of the Dockerfile)" >&2; exit 1;; esac
case "${CIVITAI_MODEL:-}" in ""|PASTE_*) echo "ERROR: put the model in civitai.env (or at the top of the Dockerfile) — its Civitai page link or version number" >&2; exit 1;; esac

# Ask Civitai which file the link means, check it is an SDXL-family checkpoint, then download it and check its SHA-256.
# The checkpoint is always saved as model.safetensors — the pack's workflow loads that name.
python3 - <<'PY'
import hashlib, json, os, re, sys, urllib.request
token, link = os.environ["CIVITAI_TOKEN"], os.environ["CIVITAI_MODEL"].strip()
def fail(msg): sys.exit("ERROR: " + msg)
def get(path):
    req = urllib.request.Request("https://civitai.com/api/v1/" + path, headers={"Authorization": "Bearer " + token, "User-Agent": "cobaltpear"})
    try: return json.load(urllib.request.urlopen(req, timeout=60))
    except Exception as e: fail(f"could not ask Civitai about {link!r} ({e})")
m = re.search(r"modelVersionId=(\d+)", link) or re.fullmatch(r"(\d+)", link)
if m: version = get(f"model-versions/{m.group(1)}")
else:
    m = re.search(r"/models/(\d+)", link) or fail(f"CIVITAI_MODEL {link!r} is not a Civitai model link")
    version = get(f"models/{m.group(1)}")["modelVersions"][0]   # newest version
    version = get(f"model-versions/{version['id']}")
base, kind = version.get("baseModel", ""), version.get("model", {}).get("type", "")
print(f"Civitai: {version.get('model', {}).get('name')} — {version.get('name')} (version {version['id']}, {base}, {kind})")
if kind != "Checkpoint": fail(f"this is a {kind}, not a Checkpoint")
if not (base.startswith("SDXL") or base in ("Pony", "Illustrious", "NoobAI")): fail(f"this is a {base} model — this worker takes SDXL, Pony, Illustrious and NoobAI checkpoints")
files = [f for f in version["files"] if f.get("type") == "Model" and f.get("metadata", {}).get("format") == "SafeTensor"]
if not files: fail("no .safetensors checkpoint file in this version")
f = next((f for f in files if f.get("primary")), files[0])
sha = f.get("hashes", {}).get("SHA256", "").lower()
url = f["downloadUrl"] + ("&" if "?" in f["downloadUrl"] else "?") + "token=" + token
dest = "/comfyui/models/checkpoints/model.safetensors"
print(f"Downloading {f['name']} ({f.get('sizeKB', 0) / 1e6:.1f} GB)")
h = hashlib.sha256()
with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "cobaltpear"}), timeout=600) as r, open(dest, "wb") as out:
    while chunk := r.read(1 << 22): h.update(chunk); out.write(chunk)
if sha and h.hexdigest() != sha: fail(f"{f['name']} does not match Civitai's SHA-256 — try the build again")
print("SHA-256 OK" if sha else "Civitai lists no SHA-256 for this file — not checked")
json.dump({"version": version["id"], "name": version.get("model", {}).get("name"), "file": f["name"], "base": base}, open("/comfyui/models/checkpoints/model.json", "w"))
PY
# SDXL runs on the ComfyUI of the base image as is
