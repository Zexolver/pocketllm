#!/usr/bin/env python3
"""Patch the `flutter create`-generated android/ project: permissions, foreground service,
extracted native libs (so libllama_server.so can be exec'd), minSdk 28."""
import glob, re, sys

man = "android/app/src/main/AndroidManifest.xml"
s = open(man).read()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
"""
s = s.replace("<application", perms + "    <application", 1)
s = s.replace("<application", '<application android:extractNativeLibs="true" android:usesCleartextTraffic="true"', 1)
svc = """        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="specialUse" android:exported="false">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="local_llm_server"/>
        </service>
    </application>"""
s = s.replace("</application>", svc, 1)
open(man, "w").write(s)

gradle = (glob.glob("android/app/build.gradle.kts") + glob.glob("android/app/build.gradle"))[0]
g = open(gradle).read()
g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", lambda m: "minSdk = 28" if gradle.endswith("kts") else "minSdkVersion 28", g)
pk = "packaging { jniLibs { useLegacyPackaging = true } }" if gradle.endswith("kts") else "packagingOptions { jniLibs { useLegacyPackaging = true } }"
g = re.sub(r"(\nandroid\s*\{)", r"\1\n    " + pk, g, count=1)
open(gradle, "w").write(g)
print("patched", man, gradle)
