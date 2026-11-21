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
