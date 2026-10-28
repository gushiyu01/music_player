"""Smoke test the actual release APK on an Actions Android emulator."""
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
evidence = root / 'artifacts' / 'device'
evidence.mkdir(parents=True, exist_ok=True)
package = 'io.github.gushiyu01.music_player'

def adb(*args, binary=False):
    return subprocess.check_output(['adb', *args], text=not binary, timeout=60)

def screenshot(name):
    (evidence / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))

def ui():
    adb('shell', 'uiautomator', 'dump', '/sdcard/music-window.xml')
    value = adb('shell', 'cat', '/sdcard/music-window.xml')
    (evidence / 'latest-ui.xml').write_text(value, encoding='utf-8')
    return ET.fromstring(value)

def tap_label(label):
    document = ui()
    for node in document.iter('node'):
        text = node.attrib.get('text', '') + ' ' + node.attrib.get('content-desc', '')
        if label in text:
            points = [int(v) for v in re.findall(r'\d+', node.attrib['bounds'])]
            adb('shell', 'input', 'tap', str((points[0] + points[2]) // 2), str((points[1] + points[3]) // 2))
            return
    raise AssertionError(f'Cannot find accessible UI label: {label}')

try:
    adb('install', '-r', str(root / 'build/app/outputs/flutter-apk/app-release.apk'))
    adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    time.sleep(8)
    screenshot('01-library')
    tap_label('晨光')
    time.sleep(5)
    sessions = adb('shell', 'dumpsys', 'media_session')
    (evidence / 'foreground-media-session.txt').write_text(sessions, encoding='utf-8')
    assert package in sessions, 'App did not create a system media session'
    assert re.search(r'state=3\b', sessions), 'Demo did not enter playing state'
    screenshot('02-playing')
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(4)
    sessions = adb('shell', 'dumpsys', 'media_session')
    (evidence / 'background-media-session.txt').write_text(sessions, encoding='utf-8')
    assert re.search(r'state=3\b', sessions), 'Playback stopped after leaving the app'
    adb('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PAUSE')
    time.sleep(2)
    sessions = adb('shell', 'dumpsys', 'media_session')
    assert re.search(r'state=2\b', sessions), 'System pause did not pause the player'
    adb('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PLAY')
    time.sleep(2)
    sessions = adb('shell', 'dumpsys', 'media_session')
    assert re.search(r'state=3\b', sessions), 'System play did not resume the player'
    adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    time.sleep(2)
    tap_label('云间 · 原创合成试听')
    time.sleep(2)
    screenshot('03-player')
    tap_label('播放队列')
    time.sleep(1)
    screenshot('04-queue')
    print('Release APK installed and launched; demo playback, background playback and system pause/resume passed.')
finally:
    (evidence / 'logcat.txt').write_text(adb('logcat', '-d', '-t', '1200'), encoding='utf-8')
