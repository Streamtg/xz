import os
import sys
import subprocess
import shutil
import time
from pathlib import Path

# --- CONFIGURACIÓN DE INGENIERÍA ---
BASE_DIR = Path(__file__).parent.absolute()
DOWNLOADS_DIR = BASE_DIR / "downloads"
OUTPUT_DIR = BASE_DIR / "outputs"
# En CentOS, tu "Drive" será una carpeta local (puedes apuntar a un montaje NFS/Rclone)
LOCAL_BACKUP_DIR = Path.home() / "SoniTranslate_Archive"

# Token de seguridad
os.environ["HF_TOKEN"] = "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"

# Asegurar estructura de directorios
for d in [DOWNLOADS_DIR, OUTPUT_DIR, LOCAL_BACKUP_DIR]:
    d.mkdir(parents=True, exist_ok=True)

# ============================================================
# MÓDULO: DESCARGADOR DE REDES (ABSTRACCIÓN)
# ============================================================
class SocialDownloader:
    @staticmethod
    def download(url):
        print(f"📡 Capturando: {url}")
        # Usamos el ejecutable de yt-dlp del entorno conda
        cmd = [
            sys.executable, "-m", "yt_dlp",
            "--no-playlist",
            "--merge-output-format", "mp4",
            "-o", f"{DOWNLOADS_DIR}/%(title).70s.%(ext)s",
            url
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            files = sorted(DOWNLOADS_DIR.glob("*"), key=os.path.getmtime, reverse=True)
            return str(files[0]) if files else None
        return None

# ============================================================
# MÓDULO: SYNC ENGINE (MONITOR DE SALIDA)
# ============================================================
def start_sync_engine():
    """Ejecuta un thread persistente para respaldar resultados."""
    import threading
    def _sync_worker():
        uploaded = set()
        while True:
            try:
                # Escaneamos archivos de salida final
                for fp in OUTPUT_DIR.glob("output_file_*.*"):
                    if fp not in uploaded:
                        # Esperar estabilidad (evitar copiar archivos a medio procesar)
                        initial_size = fp.stat().st_size
                        time.sleep(3)
                        if initial_size == fp.stat().st_size:
                            shutil.copy2(fp, LOCAL_BACKUP_DIR / fp.name)
                            uploaded.add(fp)
                            print(f"📦 [Backup] {fp.name} -> Sincronizado")
            except Exception as e:
                print(f"⚠️ Error en Sync: {e}")
            time.sleep(10)

    thread = threading.Thread(target=_sync_worker, daemon=True)
    thread.start()

# ============================================================
# INTERFAZ GRADIO (ENGINEERING UI)
# ============================================================
def launch_ui():
    import gradio as gr
    
    # Intentar importar la app original de SoniTranslate
    try:
        sys.path.append(str(BASE_DIR))
        from app_rvc import create_gui
    except ImportError:
        print("❌ No se encontró app_rvc.py. Asegúrate de estar en el repo clonado.")
        return

    with gr.Blocks(title="SoniTranslate PRO - CentOS Server") as demo:
        gr.Markdown(f"# 🎬 SoniTranslate PRO\n**Entorno:** CentOS 7 | **Backup:** {LOCAL_BACKUP_DIR}")
        
        with gr.Tab("📱 Social Importer"):
            url_input = gr.Textbox(label="URL de Video (TikTok, YT, etc.)")
            dl_btn = gr.Button("Descargar e Importar", variant="primary")
            out_video = gr.Video()
            
            def handle_dl(url):
                path = SocialDownloader.download(url)
                return path if path else "Error en la descarga"
            
            dl_btn.click(handle_dl, url_input, out_video)

        with gr.Tab("🎙️ Doblaje IA"):
            # Aquí inyectamos la lógica original del repo
            create_gui()

    demo.launch(server_name="0.0.0.0", server_port=7860)

if __name__ == "__main__":
    print("🚀 Iniciando Motor SoniTranslate...")
    start_sync_engine()
    launch_ui()
