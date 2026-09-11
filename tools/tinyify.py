#!/usr/bin/env python3

# Setup:
# pip install Pillow tinify

import argparse
import importlib
import os
import sys
from pathlib import Path

Image = None
PngInfo = None
tinify = None

META_OPTIMIZED = "TINYIFY_OPTIMIZED"
META_METHOD = "TINYIFY_METHOD"
META_ORIGINAL_SIZE = "TINYIFY_ORIGINAL_SIZE"


def get_pillow_modules():
	global Image, PngInfo
	if Image is None or PngInfo is None:
		try:
			from PIL import Image as pillow_image
			from PIL.PngImagePlugin import PngInfo as png_info_class
		except ImportError:
			print("[Error] Pillow is required. Install with: pip install Pillow")
			sys.exit(1)
		Image = pillow_image
		PngInfo = png_info_class
	return Image, PngInfo


def get_tinify_module(api_key: str):
	global tinify
	if tinify is None:
		try:
			tinify = importlib.import_module("tinify")
		except ImportError:
			return None
	tinify.key = api_key
	return tinify


# TINY_PNY_API_KEY is a typo for TINY_PNG_API_KEY that is what C:\GitHub\.env actually spells, so
# it is accepted rather than silently ignored, which is why the TinyPNG engine never engaged.
API_KEY_NAMES = {"TINY_PNG_API_KEY", "TINYPNG_API_KEY", "TINY_PNY_API_KEY"}


def find_env_file(project_root: Path):
	"""The .env beside the project, or the shared one in the directory the repositories sit in."""
	for candidate in (project_root / ".env", *(p / ".env" for p in project_root.parents)):
		if candidate.exists():
			return candidate
	return None


def load_api_key(project_root: Path):
	for name in API_KEY_NAMES:
		key = os.getenv(name)
		if key:
			return key.strip()

	env_path = find_env_file(project_root)
	if env_path is None:
		return None

	try:
		with env_path.open("r", encoding="utf-8") as env_file:
			for raw_line in env_file:
				line = raw_line.strip()
				if not line or line.startswith("#") or "=" not in line:
					continue

				name, value = line.split("=", 1)
				var_name = name.strip()
				if var_name not in API_KEY_NAMES:
					continue

				cleaned = value.strip().strip('"').strip("'")
				if cleaned:
					return cleaned
	except OSError as error:
		print(f"[Warning] Could not read .env file: {error}")

	return None


def iter_png_files(root_dir_path: Path):
	for file_path in root_dir_path.rglob("*"):
		if file_path.is_file() and file_path.suffix.lower() == ".png":
			yield file_path


def build_png_text_metadata(image, method: str, original_size: tuple[int, int]):
	_, png_info_class = get_pillow_modules()
	png_info = png_info_class()

	for key, value in image.info.items():
		if isinstance(value, str):
			png_info.add_text(key, value)

	png_info.add_text(META_OPTIMIZED, "1")
	png_info.add_text(META_METHOD, method)
	png_info.add_text(META_ORIGINAL_SIZE, f"{original_size[0]}x{original_size[1]}")
	return png_info


def local_optimize_file(png_path: Path, max_size: int):
	image_module, _ = get_pillow_modules()
	with image_module.open(png_path) as image:
		original_size = image.size
		largest_edge = max(original_size)
		resized = False

		if largest_edge > max_size:
			scale_ratio = max_size / float(largest_edge)
			new_width = max(1, int(round(original_size[0] * scale_ratio)))
			new_height = max(1, int(round(original_size[1] * scale_ratio)))
			processed = image.resize((new_width, new_height), image_module.Resampling.LANCZOS)
			resized = True
		else:
			processed = image.copy()

		png_info = build_png_text_metadata(image, "local", original_size)
		processed.save(png_path, format="PNG", optimize=True, pnginfo=png_info)

	return original_size, processed.size, resized, "local"


def tinypng_optimize_file(png_path: Path, max_size: int, tinify_module):
	image_module, _ = get_pillow_modules()
	with image_module.open(png_path) as image:
		original_size = image.size
		largest_edge = max(original_size)

	source = tinify_module.from_file(str(png_path))
	if largest_edge > max_size:
		source = source.resize(method="fit", width=max_size, height=max_size)
	source.to_file(str(png_path))

	with image_module.open(png_path) as output_image:
		optimized_size = output_image.size
		png_info = build_png_text_metadata(output_image, "tinypng", original_size)
		output_image.save(png_path, format="PNG", optimize=True, pnginfo=png_info)

	resized = optimized_size != original_size
	return original_size, optimized_size, resized, "tinypng"


def optimize_pngs(root_dir_path: Path, max_size: int, engine: str, api_key):
	image_module, _ = get_pillow_modules()

	if not root_dir_path.exists() or not root_dir_path.is_dir():
		print(f"[Error] Root directory '{root_dir_path}' does not exist or is not a directory.")
		sys.exit(1)

	root_dir_path = root_dir_path.resolve()
	png_files = list(iter_png_files(root_dir_path))
	if not png_files:
		print(f"No .png files found in '{root_dir_path}'.")
		return

	use_tinypng = engine in {"auto", "tinypng"} and api_key is not None
	tinify_module = get_tinify_module(api_key) if use_tinypng else None
	if engine == "tinypng" and tinify_module is None:
		print("[Error] TinyPNG engine requested, but tinify is not installed.")
		print("Install with: pip install tinify")
		sys.exit(1)

	if use_tinypng and tinify_module is None:
		print("[Warning] tinify is not installed. Falling back to local Pillow optimization.")
		use_tinypng = False

	if engine == "tinypng" and api_key is None:
		print("[Error] TinyPNG engine requested, but no API key found in env/.env.")
		sys.exit(1)

	print("Engine: TinyPNG + local fallback" if use_tinypng else "Engine: Local Pillow")
	print(f"Found {len(png_files)} .png files to process.")

	processed_count = 0
	resized_count = 0
	skipped_count = 0
	fallback_count = 0
	fail_count = 0

	tiny_errors = {
		"AccountError",
		"ClientError",
		"ServerError",
		"ConnectionError",
	}

	for png_file in png_files:
		rel_path = png_file.relative_to(root_dir_path)

		try:
			with image_module.open(png_file) as image:
				if image.info.get(META_OPTIMIZED) == "1":
					skipped_count += 1
					print(f"Skipped: {rel_path} (already optimized)")
					continue

			if use_tinypng:
				try:
					original_size, optimized_size, was_resized, method = tinypng_optimize_file(
						png_file,
						max_size,
						tinify_module,
					)
				except Exception as error:
					if type(error).__name__ in tiny_errors:
						print(f"[Warning] TinyPNG failed for '{rel_path}': {error}")
						print("[Warning] Falling back to local Pillow for this file.")
						original_size, optimized_size, was_resized, method = local_optimize_file(
							png_file,
							max_size,
						)
						fallback_count += 1
					else:
						raise
			else:
				original_size, optimized_size, was_resized, method = local_optimize_file(
					png_file,
					max_size,
				)

			if was_resized:
				resized_count += 1
				print(
					f"Resized ({method}): {rel_path} "
					f"({original_size[0]}x{original_size[1]} -> "
					f"{optimized_size[0]}x{optimized_size[1]})"
				)
			else:
				print(f"Optimized ({method}): {rel_path} ({original_size[0]}x{original_size[1]})")
			processed_count += 1
		except OSError as error:
			print(f"[Error] Failed to process '{rel_path}': {error}")
			fail_count += 1
		except Exception as error:
			print(f"[Error] Unexpected failure for '{rel_path}': {error}")
			fail_count += 1

	print("\nTinyify summary:")
	print(f"Processed: {processed_count}")
	print(f"Resized: {resized_count}")
	print(f"Skipped: {skipped_count}")
	if fallback_count > 0:
		print(f"Fallback to local: {fallback_count}")
	if fail_count > 0:
		print(f"Failed: {fail_count}")


def main():
	project_root = Path(__file__).resolve().parent.parent

	parser = argparse.ArgumentParser(
		description=(
			"Recursively optimize PNG files in place, cap max edge, and tag files "
			"with metadata so they are skipped on future runs."
		)
	)
	parser.add_argument(
		"root",
		type=str,
		nargs="?",
		default=str(project_root),
		help="Root directory to scan recursively (default: repository root)",
	)
	parser.add_argument(
		"--max-size",
		type=int,
		default=512,
		help="Maximum size in pixels for the largest image edge (default: 512)",
	)
	parser.add_argument(
		"--engine",
		choices=["auto", "local", "tinypng"],
		default="auto",
		help="Optimization engine: auto, local, or tinypng (default: auto)",
	)
	args = parser.parse_args()

	if args.max_size <= 0:
		print("[Error] --max-size must be greater than 0.")
		sys.exit(1)

	api_key = load_api_key(project_root)
	optimize_pngs(Path(args.root), max_size=args.max_size, engine=args.engine, api_key=api_key)


if __name__ == "__main__":
	main()

# Example:
# python3 tools/tinyify.py
# python3 tools/tinyify.py --engine tinypng
