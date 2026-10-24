# VoiceBridge app – setup

1. Install Flutter, then create a fresh project and drop these files in:
       flutter create --org me.voicebridge --project-name voicebridge_app --platforms=android voicebridge_app
       (copy this folder's lib/ and pubspec.yaml over the new project's)
       cd voicebridge_app && flutter pub get

2. Android permissions and foreground microphone service are added by .github/scripts/patch_android.py during CI builds. The minimum Android SDK is 24.

3. Run / build:
       flutter run
       flutter build apk --release
