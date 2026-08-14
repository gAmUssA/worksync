#!/bin/bash
# Regenerates Sources/WorkSyncCore/ExampleConfig.swift from config.example.toml.
# Run this after editing the example; ExampleConfigTests fails if you forget.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
toml = open('config.example.toml').read()
body = toml.replace('\\', '\\\\').replace('"""', '\\"\\"\\"')
out = '''// Generated from config.example.toml by scripts/generate-example-config.sh.
// Do not edit by hand — ExampleConfigTests asserts this matches the file.
//
// Embedded rather than loaded as a bundle resource so `worksync init` cannot
// fail at runtime on a missing resource bundle: first-run UX is the worst
// possible place for a "file not found".

public enum ExampleConfig {
    public static let contents = """
%s
"""
}
''' % body
open('Sources/WorkSyncCore/ExampleConfig.swift','w').write(out)
PY
echo "regenerated Sources/WorkSyncCore/ExampleConfig.swift"
