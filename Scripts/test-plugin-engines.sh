#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
source "$ROOT_DIR/Scripts/test_environment.sh"

FILTER='ProviderPluginRuntimeTests|ProviderPluginParityTests|ProviderPluginDetailsParityTests|ProviderPluginExtensionParityTests|ProviderPluginCurrencyTests|ProviderPluginMemoryTests|ClaudePlatformPluginTests|Sub2APIPluginGoldenTests|ParallelPluginTests|GitKrakenPluginTests|V0PluginTests|UserProviderPluginPortableTests'

echo "plugin engine A/B: JavaScriptCore"
(
  unset CODEXBAR_PLUGIN_ENGINE
  codexbar_run_swift_test_with_private_home swift test --no-parallel --filter "$FILTER"
)

echo "plugin engine A/B: QuickJS"
CODEXBAR_PLUGIN_ENGINE=quickjs codexbar_run_swift_test_with_private_home \
  swift test --skip-build --no-parallel --filter "$FILTER"
