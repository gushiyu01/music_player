"""Smoke test the actual release APK on an Actions Android emulator."""
from pathlib import Path
import re
import subprocess
import sys
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
    output = adb('shell', 'uiautomator', 'dump', '--compressed', '/sdcard/music-window.xml')
    if 'dumped to:' not in output:
        return ET.Element('hierarchy')
    value = adb('shell', 'cat', '/sdcard/music-window.xml')
    (evidence / 'latest-ui.xml').write_text(value, encoding='utf-8')
    return ET.fromstring(value)

def tap_node(node):
    points = [int(v) for v in re.findall(r'\d+', node.attrib['bounds'])]
    adb('shell', 'input', 'tap', str((points[0] + points[2]) // 2), str((points[1] + points[3]) // 2))

def find_label(label, timeout=25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        document = ui()
        titles = [n.attrib.get('text', '') for n in document.iter('node')
                  if n.attrib.get('resource-id') == 'android:id/alertTitle']
        # A cold emulator's launcher can ANR while installing. Handle that
        # external dialog explicitly; an ANR from our app still fails the test.
        if any('Quickstep' in title or 'Launcher3' in title for title in titles):
            for node in document.iter('node'):
                if node.attrib.get('resource-id') == 'android:id/aerr_close':
                    tap_node(node)
                    break
            time.sleep(2)
            continue
        for node in document.iter('node'):
            text = node.attrib.get('text', '') + ' ' + node.attrib.get('content-desc', '')
            if label in text:
                return node
        time.sleep(1)
    raise AssertionError(f'Cannot find accessible UI label: {label}')

def tap_label(label):
    tap_node(find_label(label))

def media_state(expected, name):
    sessions = adb('shell', 'dumpsys', 'media_session')
    (evidence / f'{name}-media-session.txt').write_text(sessions, encoding='utf-8')
    assert package in sessions, 'App did not create a system media session'
    assert re.search(rf'state=(?:[A-Z_]+\()?{expected}\b', sessions), f'Unexpected media state: expected {expected}'

try:
    apk = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/app/outputs/flutter-apk/app-release.apk'
    adb('install', '-r', str(apk))
    adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    time.sleep(8)
    dawn = find_label('晨光')
    screenshot('01-library')
    tap_node(dawn)
    time.sleep(5)
    media_state(3, 'foreground')
    screenshot('02-playing')
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(4)
    media_state(3, 'background')
    adb('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PAUSE')
    time.sleep(2)
    media_state(2, 'system-pause')
    adb('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PLAY')
    time.sleep(2)
    media_state(3, 'system-resume')
    adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    time.sleep(2)
    tap_label('云间 · 原创合成试听')
    time.sleep(2)
    screenshot('03-player')
    # A live progress slider continuously changes the accessibility tree.
    # Pause after proving system resume so UIAutomator can obtain an idle dump.
    adb('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PAUSE')
    time.sleep(2)
    media_state(2, 'before-queue')
    tap_label('播放队列')
    time.sleep(1)
    find_label('接下来播放')
    screenshot('04-queue')
    adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    time.sleep(1)
    tap_label('下载当前歌曲')
    time.sleep(3)
    # A process restart proves this is a persistent file, rather than a live
    # network stream or an in-memory download record.
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'svc', 'wifi', 'disable')
    adb('shell', 'svc', 'data', 'disable')
    adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    time.sleep(5)
    tap_label('本地')
    time.sleep(1)
    tap_label('原创试听')
    time.sleep(1)
    screenshot('05-local-downloads')
    tap_label('晨光')
    time.sleep(4)
    media_state(3, 'offline-after-restart')
    # Pause so accessibility can settle, then verify the source badge emitted
    # only when MusicHandler selects AudioSource.file (not the demo asset).
    adb('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PAUSE')
    time.sleep(1)
    tap_label('云间 · 原创合成试听')
    find_label('本地文件 · 离线播放')
    screenshot('06-offline-player')
    print('Release APK: playback, background/system controls, queue, persistent download and offline file playback after process restart passed.')
finally:
    adb('shell', 'svc', 'wifi', 'enable')
    adb('shell', 'svc', 'data', 'enable')
    (evidence / 'logcat.txt').write_text(adb('logcat', '-d', '-t', '1200'), encoding='utf-8')
