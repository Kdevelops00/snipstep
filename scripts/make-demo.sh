#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
reference="${1:?Pass a verified PNG cropped to a public webpage}"
mkdir -p build/demo-modules build/story-assets docs/media
swiftc scripts/DemoCanvas.swift scripts/render-story.swift -o build/render-story
cp "$reference" build/story-assets/reference.png
swiftc -swift-version 6 -parse-as-library -emit-library -static -emit-module -module-name SnipstepCore -target "$(uname -m)-apple-macosx15.2" Sources/SnipstepCore/*.swift -o build/demo-modules/libSnipstepCore.a -emit-module-path build/demo-modules/SnipstepCore.swiftmodule
python3 - <<'PYTHON'
from pathlib import Path
source = Path('Widgets/SnipstepWidgets.swift').read_text().split('@main struct SnipstepWidgetBundle')[0]
source = source.replace('private struct Entry', 'struct Entry').replace('private struct Checklist', 'struct Checklist')
Path('build/DemoWidget.swift').write_text(source)
PYTHON
swiftc -swift-version 6 -parse-as-library -I build/demo-modules -L build/demo-modules -lSnipstepCore MacApp/AppModel.swift MacApp/LibraryView.swift MacApp/SettingsView.swift MacApp/TaskDetail.swift MacApp/BrandMotion.swift MacApp/CaptureController.swift MacApp/CaptureHotKey.swift MacApp/ShortcutRecorder.swift build/DemoWidget.swift scripts/render-demo.swift -o build/render-demo
build/render-demo build/story-assets build/story-assets/reference.png
build/render-story build/story-assets docs/media
