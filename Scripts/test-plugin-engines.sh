#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
source "$ROOT_DIR/Scripts/test_environment.sh"

FILTER='ProviderPluginRuntimeTests|ProviderPluginParityTests|ProviderPluginDetailsParityTests|ProviderPluginExtensionParityTests|ProviderPluginCurrencyTests|Sub2APIPluginGoldenTests|GitKrakenPluginTests|V0PluginTests|UserProviderPluginPortableTests'

echo "plugin engine A/B: JavaScriptCore"
env -u CODEXBAR_PLUGIN_ENGINE swift test --no-parallel --filter "$FILTER"

echo "plugin engine A/B: QuickJS"
CODEXBAR_PLUGIN_ENGINE=quickjs swift test --skip-build --no-parallel --filter "$FILTER"
