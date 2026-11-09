import json
import subprocess
import pandas as pd
import re
import tomllib
import tomli_w

manifest = json.loads(subprocess.run(["wally", "manifest-to-json"],stdout = subprocess.PIPE).stdout)

with open("wally.toml", "rb") as f:
	config = tomllib.load(f)

for package_name, package_version in manifest["dependencies"].items():
	package_type = package_version.rsplit("@", 1)[0]
	# print(package_type)
	search_result = subprocess.run(["wally", "search", package_type], stdout = subprocess.PIPE, text = True).stdout
	decode = search_result.encode(encoding='ascii',errors='replace')
	regex = re.compile(r'\x1B\[[0-9;]*[a-zA-Z]')
	clean_text = regex.sub('', search_result)
	
	package_search_result = clean_text[1:-2].split("\n")
	if package_search_result[0] == "":
		continue
	config["dependencies"][package_name] = package_search_result[0]
	print(config["dependencies"][package_name])
	# package_search_result[1]	
	
with open("wally.toml", "wb") as f:
	tomli_w.dump(config, f)
	
subprocess.run(["wally", "install"])
subprocess.run(["rojo", "sourcemap", "default.project.json", "--output", "sourcemap.json", "--include-non-scripts"])
subprocess.run(["wally-package-types", "--sourcemap", "sourcemap.json", "Packages/"])
subprocess.run(["wally-package-types", "--sourcemap", "sourcemap.json", "ServerPackages/"])
subprocess.run(["rojo", "serve"])