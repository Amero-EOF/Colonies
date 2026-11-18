
import subprocess
		
subprocess.run(["wally", "install"])
subprocess.run(["rojo", "sourcemap", "default.project.json", "--output", "sourcemap.json", "--include-non-scripts"])
subprocess.run(["wally-package-types", "--sourcemap", "sourcemap.json", "Packages/"])
subprocess.run(["wally-package-types", "--sourcemap", "sourcemap.json", "ServerPackages/"])

subprocess.run(["rojo", "serve"])
