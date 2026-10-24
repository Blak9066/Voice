import re, glob
base = 'build_app/android/app/'
mp = base + 'src/main/AndroidManifest.xml'
s = open(mp).read()
names = ['INTERNET', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS', 'BLUETOOTH_CONNECT', 'WAKE_LOCK',
         'POST_NOTIFICATIONS', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MICROPHONE']
perms = ''.join(f'    <uses-permission android:name="android.permission.{n}"/>\n' for n in names)
s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
s = s.replace('<application', perms + '    <application', 1)
service = ('        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"\n'
           '            android:foregroundServiceType="microphone" android:exported="false"/>\n    ')
s = s.replace('</application>', service + '</application>', 1)
open(mp, 'w').write(s)

for gp in glob.glob(base + 'build.gradle*'):
    g = open(gp).read()
    g = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 24', g)
    open(gp, 'w').write(g)
print('patched')
