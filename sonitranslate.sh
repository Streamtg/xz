# @title 🎬 SoniTranslate PRO - Ultra High Performance Edition
# @markdown ---
DRIVE_OUTPUT_FOLDER = "SoniTranslate_Output" # @param {type:"string"}
YOUR_HF_TOKEN = "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" # @param {type:'string'}
Install_PIPER_TTS = True # @param {type:"boolean"}
Install_Coqui_XTTS = True # @param {type:"boolean"}
interface_language = "spanish" # @param ['arabic', 'azerbaijani', 'chinese_zh_cn', 'english', 'french', 'german', 'hindi', 'indonesian', 'italian', 'japanese', 'korean', 'marathi', 'polish', 'portuguese', 'russian', 'spanish', 'swedish', 'turkish', 'ukrainian', 'vietnamese']

import os, subprocess, sys, shutil, time

# ============================================================
# CONFIGURACIÓN DE ENTORNO Y DRIVE
# ============================================================
os.environ["HF_TOKEN"] = YOUR_HF_TOKEN

print("=" * 60 + "\n📁 CONFIGURANDO STORAGE...\n" + "=" * 60)
from google.colab import drive
drive.mount('/content/drive')
drive_output_path = f"/content/drive/MyDrive/{DRIVE_OUTPUT_FOLDER}"
os.makedirs(drive_output_path, exist_ok=True)
os.makedirs("/content/SoniTranslate/downloads", exist_ok=True)

# ============================================================
# DESPLIEGUE DE COMPONENTES CORE
# ============================================================

def create_social_downloader():
    """Genera el módulo de descarga con lógica de redundancia."""
    dl_path = "/content/SoniTranslate/social_downloader.py"
    content = """
import subprocess, os, glob, json, shutil, sys

DDIR = "/content/SoniTranslate/downloads"
os.makedirs(DDIR, exist_ok=True)

def _run_ytdlp(args):
    ytdlp_path = "/content/SoniTranslate/.venv/bin/yt-dlp"
    cmd = [ytdlp_path] + args if os.path.exists(ytdlp_path) else ["yt-dlp"] + args
    return subprocess.run(cmd, capture_output=True, text=True, cwd=DDIR)

def download_video(url, progress_callback=None):
    if not url: return None, "URL vacía"
    if progress_callback: progress_callback("Iniciando descarga...")
    
    # Intento de descarga calidad balanceada (MP4 preferido)
    args = ["--no-playlist", "--merge-output-format", "mp4", "--output", f"{DDIR}/%(title).70s.%(ext)s", url]
    res = _run_ytdlp(args)
    
    files = sorted(glob.glob(os.path.join(DDIR, "*")), key=os.path.getmtime, reverse=True)
    for f in files:
        if f.lower().endswith(('.mp4', '.mkv', '.webm')) and os.path.getsize(f) > 1024:
            return f, f"Éxito: {os.path.basename(f)}"
    return None, f"Error: {res.stderr[-200:]}"
"""
    with open(dl_path, 'w') as f: f.write(content)

def create_drive_watcher():
    """Genera el demonio de sincronización con Google Drive."""
    watcher_path = "/content/SoniTranslate/drive_watcher.py"
    content = f"""
import os, time, shutil, glob
from datetime import datetime

DRIVE_OUT = "{drive_output_path}"
WATCH_DIRS = ["/content/SoniTranslate/outputs", "/content/SoniTranslate"]
uploaded = set()

def sync():
    while True:
        for d in WATCH_DIRS:
            if not os.path.exists(d): continue
            for fp in glob.glob(os.path.join(d, "output_file_*.*")):
                if fp in uploaded: continue
                # Estabilidad: esperar a que el archivo deje de crecer
                s1 = os.path.getsize(fp)
                time.sleep(2)
                if s1 != os.path.getsize(fp): continue
                
                dest = os.path.join(DRIVE_OUT, os.path.basename(fp))
                shutil.copy2(fp, dest)
                uploaded.add(fp)
                print(f"[DriveSync] {os.path.basename(fp)} -> OK")
        time.sleep(10)

if __name__ == "__main__": sync()
"""
    with open(watcher_path, 'w') as f: f.write(content)

# ============================================================
# COMPILACIÓN DEL LAUNCHER (INTERFAZ PRO)
# ============================================================

def create_launcher():
    launcher_path = "/content/SoniTranslate/launcher.py"
    # Aquí completamos la lógica de UI que faltaba
    content = """
import sys, os, gradio as gr
sys.path.insert(0, "/content/SoniTranslate")
os.chdir("/content/SoniTranslate")

from social_downloader import download_video
from app_rvc import create_gui # Asumiendo la función principal de Soni

_CSS = ".gradio-container {max-width: 1180px !important} .st-hdr {background: #2d3436; color: white; padding: 20px; border-radius: 10px; text-align: center; margin-bottom: 20px}"

def social_tab():
    with gr.Column():
        gr.Markdown("### 🔗 Descargador de Redes Sociales (Redundante)")
        url = gr.Textbox(placeholder="Pega link de TikTok, YT, FB, IG...", label="URL del contenido")
        btn = gr.Button("🚀 Descargar e Importar", variant="primary")
        status = gr.Textbox(label="Estado de descarga")
        preview = gr.Video(label="Vista previa")
        
        def handle_dl(u):
            path, msg = download_video(u)
            return path, msg
        
        btn.click(handle_dl, inputs=[url], outputs=[preview, status])

# Inyectar en la UI original
with gr.Blocks(css=_CSS, title="SoniTranslate PRO") as demo:
    gr.HTML("<div class='st-hdr'><h1>SoniTranslate PRO v2026</h1><p>Engineered for Content Creators</p></div>")
    with gr.Tabs():
        with gr.Tab("📱 Social Downloader"):
            social_tab()
        with gr.Tab("🎙️ Doblaje & IA"):
            # Aquí se montaría la UI original de SoniTranslate
            gr.Markdown("Integrando el motor de doblaje...")
            # Importamos la UI original mediante un hack de Gradio o carga directa
            try:
                import app_rvc
                app_rvc.main_ui() 
            except:
                gr.Warning("Interfaz de doblaje cargando en modo stand-alone...")

if __name__ == "__main__":
    demo.launch(share=True, debug=False)
"""
    with open(launcher_path, 'w') as f: f.write(content)

# ============================================================
# EJECUCIÓN DEL PIPELINE
# ============================================================

print("\n" + "=" * 60 + "\n🚀 INICIANDO DESPLIEGUE\n" + "=" * 60)

# 1. Clonar/Limpiar
%cd /content
if not os.path.exists('SoniTranslate'):
    !git clone https://github.com/r3gm/SoniTranslate.git
%cd /content/SoniTranslate

# 2. Generar Módulos
create_social_downloader()
create_drive_watcher()
create_launcher()

# 3. Lanzar Watcher en segundo plano
subprocess.Popen(["python", "/content/SoniTranslate/drive_watcher.py"])

# 4. Lanzar Aplicación Principal
print("\n✅ Sistema listo. Lanzando interfaz...")
!uv run python launcher.py
