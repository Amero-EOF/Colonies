"""Nearest-neighbour upscaler for pixel-art textures headed to Roblox.

Roblox bilinear-filters every texture with no option to turn it off, so a
64x64 pixel-art texture turns to mush on import. Upscaling with nearest
neighbour first makes each source pixel a solid NxN block, so the blur only
touches block edges and the art stays crisp.

Each image is scaled by the largest whole-number factor that keeps both sides
within --max-size (default 512). Whole-number factors keep every source pixel
the same size.

Usage:
	python PixelUpscale.py Assets/Models/TownHall.gltf
		-> Assets/Models/TownHall.Roblox.gltf (embedded textures upscaled)
	python PixelUpscale.py texture.png [more.png ...]
		-> texture.Roblox.png
	Options: -o/--output PATH (single input only), --max-size N
"""

import argparse
import base64
import io
import json
import sys
from pathlib import Path

from PIL import Image

NEAREST = 9728


def upscale_factor(width: int, height: int, max_size: int) -> int:
	return max(1, max_size // max(width, height))


def upscale_image(image: Image.Image, max_size: int) -> tuple[Image.Image, int]:
	factor = upscale_factor(image.width, image.height, max_size)
	if factor == 1:
		return image, 1
	return image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST), factor


def to_png_bytes(image: Image.Image) -> bytes:
	buffer = io.BytesIO()
	image.save(buffer, format="PNG", optimize=True)
	return buffer.getvalue()


def default_output(path: Path) -> Path:
	return path.with_name(f"{path.stem}.Roblox{path.suffix}")


def process_png(source: Path, output: Path, max_size: int) -> None:
	with Image.open(source) as image:
		image.load()
		result, factor = upscale_image(image, max_size)
	output.write_bytes(to_png_bytes(result))
	print(f"{source.name}: {image.width}x{image.height} -> {result.width}x{result.height} (x{factor})")


def process_gltf(source: Path, output: Path, max_size: int) -> None:
	gltf = json.loads(source.read_text(encoding="utf-8"))
	textures = {texture.get("source"): texture.get("name", "") for texture in gltf.get("textures", [])}

	for index, entry in enumerate(gltf.get("images", [])):
		uri = entry.get("uri", "")
		label = textures.get(index) or entry.get("name") or f"image{index}"
		if uri.startswith("data:"):
			raw = base64.b64decode(uri.split(",", 1)[1])
		elif uri:
			raw = (source.parent / uri).read_bytes()
		else:
			print(f"{label}: stored in a buffer view, skipped (export as .gltf with embedded textures)")
			continue

		with Image.open(io.BytesIO(raw)) as image:
			image.load()
			result, factor = upscale_image(image, max_size)
		png = to_png_bytes(result)

		if uri.startswith("data:"):
			entry["uri"] = "data:image/png;base64," + base64.b64encode(png).decode("ascii")
		else:
			image_path = output.parent / f"{Path(uri).stem}.Roblox.png"
			image_path.write_bytes(png)
			entry["uri"] = image_path.name
		entry["mimeType"] = "image/png"
		print(f"{label}: {image.width}x{image.height} -> {result.width}x{result.height} (x{factor})")

	# Hint nearest filtering for any viewer that honours it (Roblox does not).
	for sampler in gltf.get("samplers", []):
		sampler["magFilter"] = NEAREST
		sampler["minFilter"] = NEAREST

	output.write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")
	print(f"Wrote {output}")


def main() -> int:
	parser = argparse.ArgumentParser(description="Nearest-neighbour upscale pixel-art textures for Roblox.")
	parser.add_argument("inputs", nargs="+", type=Path, help=".gltf or .png files")
	parser.add_argument("-o", "--output", type=Path, help="output path (single input only)")
	parser.add_argument("--max-size", type=int, default=512, help="largest allowed side in pixels (default 512)")
	args = parser.parse_args()

	if args.output and len(args.inputs) > 1:
		parser.error("--output only works with a single input")

	for source in args.inputs:
		output = args.output or default_output(source)
		suffix = source.suffix.lower()
		if suffix == ".gltf":
			process_gltf(source, output, args.max_size)
		elif suffix == ".png":
			process_png(source, output, args.max_size)
		else:
			print(f"{source}: unsupported file type (use .gltf or .png)", file=sys.stderr)
			return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
