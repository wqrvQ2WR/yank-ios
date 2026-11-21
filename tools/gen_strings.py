#!/usr/bin/env python3
"""안드로이드 strings.xml(5개 언어) + iOS 전용 문구 -> Yank/Resources/Localizable.xcstrings"""
import json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
res = root.parent / "yank-android/app/src/main/res"
langs = {"en": "values", "ko": "values-ko", "ja": "values-ja", "es": "values-es", "zh-Hans": "values-zh-rCN"}

def conv(v: str) -> str:
    v = v.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n").replace("\\@", "@")
    v = re.sub(r"%(\d+)\$s", r"%\1$@", v)
    v = re.sub(r"%(\d+)\$d", r"%\1$lld", v)
    v = re.sub(r"%s", "%@", v)
    v = re.sub(r"%d", "%lld", v)
    return v

table = {}
for code, d in langs.items():
    for s in ET.parse(res / d / "strings.xml").getroot().iter("string"):
        table.setdefault(s.get("name"), {})[code] = conv(s.text or "")

# iOS 에만 있거나 iOS 에서 뜻이 달라지는 문구
extra = {
    "format_audio_m4a": {"en": "Audio only (M4A)", "ko": "음원만 (M4A)", "ja": "音声のみ (M4A)", "es": "Solo audio (M4A)", "zh-Hans": "仅音频 (M4A)"},
    "settings_save_to_photos": {"en": "Also save videos to Photos", "ko": "사진 앱에도 저장", "ja": "写真アプリにも保存", "es": "Guardar también en Fotos", "zh-Hans": "同时保存到照片"},
    "settings_save_to_photos_desc": {"en": "Files are always kept in the Files app under On My iPhone > Yank. Videos can also be added to Photos.", "ko": "파일은 항상 파일 앱의 나의 iPhone > Yank 에 보관됩니다. 영상은 사진 앱에도 넣을 수 있어요.", "ja": "ファイルは常にファイルアプリの「このiPhone内 > Yank」に保存されます。動画は写真アプリにも追加できます。", "es": "Los archivos siempre se guardan en la app Archivos, en En mi iPhone > Yank. Los vídeos también pueden ir a Fotos.", "zh-Hans": "文件始终保存在“文件”App 的“我的 iPhone > Yank”中。视频还可以添加到照片。"},
    "settings_filename_template_ios_desc": {"en": "Supports %(title)s, %(uploader)s, %(id)s, %(ext)s", "ko": "%(title)s, %(uploader)s, %(id)s, %(ext)s 를 쓸 수 있어요", "ja": "%(title)s, %(uploader)s, %(id)s, %(ext)s が使えます", "es": "Admite %(title)s, %(uploader)s, %(id)s, %(ext)s", "zh-Hans": "支持 %(title)s、%(uploader)s、%(id)s、%(ext)s"},
    "settings_keep_open_hint": {"en": "iOS pauses apps in the background. Keep Yank open while downloading.", "ko": "iOS는 백그라운드 앱을 멈춰요. 받는 동안에는 Yank 를 열어 두세요.", "ja": "iOSはバックグラウンドのアプリを停止します。ダウンロード中はYankを開いたままにしてください。", "es": "iOS pausa las apps en segundo plano. Mantén Yank abierta mientras descarga.", "zh-Hans": "iOS 会暂停后台应用。下载时请保持 Yank 在前台。"},
    "photos_saved": {"en": "Saved to Photos and Files", "ko": "사진·파일에 저장됨", "ja": "写真とファイルに保存済み", "es": "Guardado en Fotos y Archivos", "zh-Hans": "已保存到照片和文件"},
    "files_saved": {"en": "Saved to Files", "ko": "파일 앱에 저장됨", "ja": "ファイルに保存済み", "es": "Guardado en Archivos", "zh-Hans": "已保存到文件"},
    "sub_auto_desc": {"en": "Checked when you open Yank (about once an hour). Videos already there when you subscribe are skipped.", "ko": "Yank 를 열 때 확인해요(약 1시간에 한 번). 구독 전에 올라와 있던 영상은 받지 않아요.", "ja": "Yankを開いたときに確認します(約1時間に1回)。登録前の動画は取得しません。", "es": "Se comprueba al abrir Yank (cada hora aprox.). Los vídeos anteriores a la suscripción se omiten.", "zh-Hans": "打开 Yank 时检查(约每小时一次)。订阅前已有的视频不会下载。"},
    "state_server": {"en": "Preparing on server", "ko": "서버에서 준비 중", "ja": "サーバーで準備中", "es": "Preparando en el servidor", "zh-Hans": "服务器准备中"},
    "via_server": {"en": "via server", "ko": "서버 경유", "ja": "サーバー経由", "es": "vía servidor", "zh-Hans": "经服务器"},
    "error_blocked_no_server": {"en": "YouTube blocked this video for direct download. Set up the Yank server in Settings.", "ko": "유튜브가 이 영상의 직접 받기를 막았어요. 설정에서 Yank 서버를 연결하세요.", "ja": "YouTubeがこの動画の直接ダウンロードを拒否しました。設定でYankサーバーを接続してください。", "es": "YouTube bloqueó la descarga directa de este vídeo. Configura el servidor Yank en Ajustes.", "zh-Hans": "YouTube 阻止了此视频的直接下载。请在设置中连接 Yank 服务器。"},
    "settings_server": {"en": "Yank server (for blocked videos)", "ko": "Yank 서버 (막힌 영상용)", "ja": "Yankサーバー (ブロックされた動画用)", "es": "Servidor Yank (vídeos bloqueados)", "zh-Hans": "Yank 服务器(用于被阻止的视频)"},
    "settings_server_use": {"en": "Use server when direct download is blocked", "ko": "직접 받기가 막히면 서버 사용", "ja": "直接ダウンロードが拒否されたらサーバーを使う", "es": "Usar servidor si la descarga directa se bloquea", "zh-Hans": "直接下载被阻止时使用服务器"},
    "settings_server_url": {"en": "Server address", "ko": "서버 주소", "ja": "サーバーアドレス", "es": "Dirección del servidor", "zh-Hans": "服务器地址"},
    "settings_server_token": {"en": "Token", "ko": "토큰", "ja": "トークン", "es": "Token", "zh-Hans": "令牌"},
    "settings_server_desc": {"en": "A server you run (yank-pi) downloads with yt-dlp and sends the file back. Needs Tailscale on this iPhone when away from home.", "ko": "직접 돌리는 서버(yank-pi)가 yt-dlp 로 받아서 파일을 보내 줘요. 밖에서는 이 iPhone 에서 테일스케일을 켜 둬야 해요.", "ja": "自分で動かすサーバー(yank-pi)がyt-dlpでダウンロードしてファイルを送ります。外出先ではこのiPhoneでTailscaleをオンにしてください。", "es": "Un servidor propio (yank-pi) descarga con yt-dlp y envía el archivo. Fuera de casa necesitas Tailscale activo en este iPhone.", "zh-Hans": "你自己运行的服务器(yank-pi)用 yt-dlp 下载并回传文件。外出时需在此 iPhone 上开启 Tailscale。"},
    "settings_server_test": {"en": "Test connection", "ko": "연결 확인", "ja": "接続を確認", "es": "Probar conexión", "zh-Hans": "测试连接"},
    "server_ok": {"en": "Connected", "ko": "연결됐어요", "ja": "接続できました", "es": "Conectado", "zh-Hans": "已连接"},
    "server_fail": {"en": "Connection failed: %@", "ko": "연결 실패: %@", "ja": "接続失敗: %@", "es": "Error de conexión: %@", "zh-Hans": "连接失败: %@"},
}
for k, v in extra.items():
    table[k] = v

strings = {}
for k in sorted(table):
    strings[k] = {"localizations": {c: {"stringUnit": {"state": "translated", "value": v}} for c, v in table[k].items()}}
out = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
(root / "Yank/Resources").mkdir(parents=True, exist_ok=True)
(root / "Yank/Resources/Localizable.xcstrings").write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
print(len(strings), "keys")
