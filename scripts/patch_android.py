"""Apply scanner plugin Android minimum/compile SDK levels to flutter create output.

The project deliberately generates its Android skeleton with your installed
Flutter stable SDK, then patches the scanner requirements. This avoids shipping
stale Gradle wrapper/binary files in the editable source ZIP.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
for path in [root / 'android/app/build.gradle.kts', root / 'android/app/build.gradle']:
    if not path.exists():
        continue
    source = path.read_text()
    updates = [
        (r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36'),
        (r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'),
        (r'compileSdkVersion\s+flutter\.compileSdkVersion', 'compileSdkVersion 36'),
        (r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'),
    ]
    for find, replace in updates:
        source = re.sub(find, replace, source)
    path.write_text(source)
    print('Patched', path)
    break
else:
    raise SystemExit('Run flutter create . --platforms=android first')

# Set a human-readable launcher label and prepare the optional HTTPS AI endpoint.
manifest = root / 'android/app/src/main/AndroidManifest.xml'
if manifest.exists():
    content = manifest.read_text()
    content = re.sub(r'android:label="[^"]*"', 'android:label="NoteCraft AI"', content, count=1)
    if 'android.permission.INTERNET' not in content:
        content = content.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
    manifest.write_text(content)
    print('Patched', manifest)

# The icon files correspond to Android's 5 mipmap densities.
import shutil
for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
    icon = root / 'resources/icons' / density / 'ic_launcher.png'
    if icon.exists():
        dest = root / 'android/app/src/main/res' / ('mipmap-' + density) / 'ic_launcher.png'
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(icon, dest)
print('Launcher icons installed')
