"""아키텍처 경계 테스트 — 계층 규칙이 말로만 남지 않게 CI에서 강제한다.

규칙:
1. 앱 계층(denoise.py, voice/clone_say.py, web/server.py)은
   ffmpeg/모델을 직접 만지지 않는다 — subprocess 금지, core 호출만.
2. core/ 는 앱 프레임워크(flask)와 앱 계층 모듈을 모른다.
   (표준 입출력 UX도 앱 몫 — core에는 print가 없어야 한다)
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

APP_LAYER = ["denoise.py", "voice/clone_say.py", "web/server.py",
             "web/profiles.py", "web/dnjobs.py"]
CORE_LAYER = ["core/audio.py", "core/denoise.py", "core/clone.py",
              "core/metrics.py", "core/prosody.py", "core/__init__.py"]


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def test_app_layer_never_touches_subprocess_or_ffmpeg():
    for rel in APP_LAYER:
        src = read(rel)
        assert "import subprocess" not in src, f"{rel}: 앱 계층에서 subprocess 금지"
        assert not re.search(r'"ffmpeg"|\'ffmpeg\'', src), \
            f"{rel}: 앱 계층에서 ffmpeg 직접 호출 금지 (core를 쓸 것)"
        assert "arnndn" not in src, f"{rel}: 필터 체인은 core.denoise 소관"
        assert "mlx_audio" not in src, f"{rel}: 모델 실행은 core.clone 소관"


def test_app_layer_imports_core():
    for rel in APP_LAYER:
        assert "from core" in read(rel), f"{rel}: core를 통해서만 처리해야 함"


def test_core_is_framework_free():
    for rel in CORE_LAYER:
        src = read(rel)
        assert "flask" not in src.lower(), f"{rel}: core는 웹 프레임워크를 모른다"
        assert "argparse" not in src, f"{rel}: CLI 파싱은 앱 계층 몫"
        assert not re.search(r"^\s*print\(", src, re.M), \
            f"{rel}: core에는 print 금지 (UX는 앱 계층 몫)"


def test_core_never_imports_app_layer():
    for rel in CORE_LAYER:
        src = read(rel)
        for banned in ("from web", "import web", "from voice", "import voice"):
            assert banned not in src, f"{rel}: core → 앱 계층 역방향 의존 금지"
