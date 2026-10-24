from pathlib import Path
import re

base = Path("build_app/android/app")
manifest = base / "src/main/AndroidManifest.xml"
text = manifest.read_text()

permissions = [
    "INTERNET", "RECORD_AUDIO", "MODIFY_AUDIO_SETTINGS", "BLUETOOTH_CONNECT",
    "WAKE_LOCK", "POST_NOTIFICATIONS", "FOREGROUND_SERVICE",
    "FOREGROUND_SERVICE_MICROPHONE",
]
for permission in permissions:
    line = f'    <uses-permission android:name="android.permission.{permission}"/>'
    if line not in text:
        text = text.replace("</manifest>", line + "\n</manifest>", 1)

text = text.replace(
    "<application",
    '<application android:usesCleartextTraffic="true"',
    1,
) if "android:usesCleartextTraffic" not in text else text

service = (
    '        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"\n'
    '            android:foregroundServiceType="microphone" android:exported="false"/>\n'
)
if "com.pravera.flutter_foreground_task.service.ForegroundService" not in text:
    text = text.replace("</application>", service + "    </application>", 1)
manifest.write_text(text)

gradle_candidates = [
    base / "build.gradle",
    base / "build.gradle.kts",
]
app_gradle = next((p for p in gradle_candidates if p.exists()), None)
if app_gradle is None:
    raise SystemExit("Could not find Android app Gradle build file")

g = app_gradle.read_text()
g, c1 = re.subn(r"(?m)^(\s*minSdkVersion\s+).+$", r"\g<1>21", g)
g, c2 = re.subn(r"(?m)^(\s*minSdk\s*=\s*).+$", r"\g<1>21", g)
g, c3 = re.subn(r"(?m)^(\s*compileSdkVersion\s+).+$", r"\g<1>36", g)
g, c4 = re.subn(r"(?m)^(\s*compileSdk\s*=\s*).+$", r"\g<1>36", g)
if c1 + c2 == 0:
    raise SystemExit("Could not find minSdk setting in " + str(app_gradle))
if c3 + c4 == 0:
    raise SystemExit("Could not find compileSdk setting in " + str(app_gradle))
app_gradle.write_text(g)

props = Path("build_app/android/gradle.properties")
existing = props.read_text() if props.exists() else ""
setting = "android.ndk.suppressMinSdkVersionError=21"
if setting not in existing:
    props.write_text(existing.rstrip() + "\n" + setting + "\n")

print("Android patched: minSdk=21, compileSdk=36, NDK compatibility configured")
