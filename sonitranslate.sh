#!/bin/bash
# ============================================================
# sonitranslate.sh - SoniTranslate con Gradio para CentOS 7
# ============================================================
#
# USO:
#   ./sonitranslate.sh install    # Instalar (primera vez)
#   ./sonitranslate.sh start      # Iniciar servidor Gradio
#   ./sonitranslate.sh status     # Ver estado
#   ./sonitranslate.sh logs       # Ver logs
#   ./sonitranslate.sh stop       # Detener
#   ./sonitranslate.sh help       # Ayuda
#
# ============================================================

set -e

# Configuración
BASE_DIR="${SONITRANSLATE_BASE:-$HOME/sonitranslate}"
CONDA_ENV="sonitranslate"
PYTHON_VERSION="3.10"
WEB_PORT="${SONITRANSLATE_PORT:-7860}"
PID_FILE="$BASE_DIR/.server.pid"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           🎬 SoniTranslate Server - CentOS 7               ║"
    echo "║      Doblaje automático con cola via Gradio                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ============================================================
# CREAR SERVIDOR PYTHON CON GRADIO COMPLETO
# ============================================================

create_server() {
    log_info "Generando servidor Python con Gradio..."
    
    mkdir -p "$BASE_DIR"/{input,output,processing,queue,logs}
    
    cat > "$BASE_DIR/server.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
SoniTranslate Server - Interfaz Gradio completa
Sistema de doblaje automático con cola de procesamiento
Para CentOS 7 sin GPU, usando CPU
"""

import os
import sys
import json
import time
import uuid
import shutil
import signal
import argparse
import threading
import subprocess
import asyncio
import logging
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Optional, List, Dict, Any, Tuple
from enum import Enum
from concurrent.futures import ThreadPoolExecutor

# ============================================================
# CONFIGURACIÓN
# ============================================================

BASE_DIR = Path(os.environ.get('SONITRANSLATE_BASE', Path.home() / 'sonitranslate'))
INPUT_DIR = BASE_DIR / 'input'
OUTPUT_DIR = BASE_DIR / 'output'
PROCESSING_DIR = BASE_DIR / 'processing'
QUEUE_DIR = BASE_DIR / 'queue'
LOGS_DIR = BASE_DIR / 'logs'
DOWNLOADS_DIR = BASE_DIR / 'downloads'

for d in [INPUT_DIR, OUTPUT_DIR, PROCESSING_DIR, QUEUE_DIR, LOGS_DIR, DOWNLOADS_DIR]:
    d.mkdir(parents=True, exist_ok=True)

CONFIG = {
    'hf_token': os.environ.get('HF_TOKEN', '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'),
    'whisper_model': 'base',
    'default_target_lang': 'es',
    'default_voice': 'es-ES-AlvaroNeural',
    'poll_interval': 5,
    'retry_failed': 3,
    'max_file_size_mb': 500,
    'video_extensions': {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.ts', '.m4v'},
    'audio_extensions': {'.mp3', '.wav', '.flac', '.m4a', '.ogg', '.aac', '.wma'},
    'web_port': int(os.environ.get('SONITRANSLATE_PORT', 7860)),
}

# Voces disponibles organizadas por idioma
VOICES = {
    # Español
    'es-ES-AlvaroNeural': '🇪🇸 Álvaro (España, Masculino)',
    'es-ES-ElviraNeural': '🇪🇸 Elvira (España, Femenino)',
    'es-MX-DaliaNeural': '🇲🇽 Dalia (México, Femenino)',
    'es-MX-JorgeNeural': '🇲🇽 Jorge (México, Masculino)',
    'es-AR-ElenaNeural': '🇦🇷 Elena (Argentina, Femenino)',
    'es-AR-TomasNeural': '🇦🇷 Tomás (Argentina, Masculino)',
    'es-CO-GonzaloNeural': '🇨🇴 Gonzalo (Colombia, Masculino)',
    'es-CO-SalomeNeural': '🇨🇴 Salomé (Colombia, Femenino)',
    'es-CL-CatalinaNeural': '🇨🇱 Catalina (Chile, Femenino)',
    'es-CL-LorenzoNeural': '🇨🇱 Lorenzo (Chile, Masculino)',
    'es-PE-AlexNeural': '🇵🇪 Alex (Perú, Masculino)',
    'es-PE-CamilaNeural': '🇵🇪 Camila (Perú, Femenino)',
    # Inglés
    'en-US-GuyNeural': '🇺🇸 Guy (US, Male)',
    'en-US-JennyNeural': '🇺🇸 Jenny (US, Female)',
    'en-US-AriaNeural': '🇺🇸 Aria (US, Female)',
    'en-US-DavisNeural': '🇺🇸 Davis (US, Male)',
    'en-GB-RyanNeural': '🇬🇧 Ryan (UK, Male)',
    'en-GB-SoniaNeural': '🇬🇧 Sonia (UK, Female)',
    'en-AU-NatashaNeural': '🇦🇺 Natasha (Australia, Female)',
    'en-AU-WilliamNeural': '🇦🇺 William (Australia, Male)',
    # Francés
    'fr-FR-HenriNeural': '🇫🇷 Henri (France, Male)',
    'fr-FR-DeniseNeural': '🇫🇷 Denise (France, Female)',
    'fr-CA-AntoineNeural': '🇨🇦 Antoine (Canada, Male)',
    'fr-CA-SylvieNeural': '🇨🇦 Sylvie (Canada, Female)',
    # Alemán
    'de-DE-ConradNeural': '🇩🇪 Conrad (Germany, Male)',
    'de-DE-KatjaNeural': '🇩🇪 Katja (Germany, Female)',
    # Portugués
    'pt-BR-AntonioNeural': '🇧🇷 Antonio (Brasil, Masculino)',
    'pt-BR-FranciscaNeural': '🇧🇷 Francisca (Brasil, Feminino)',
    'pt-PT-DuarteNeural': '🇵🇹 Duarte (Portugal, Masculino)',
    'pt-PT-RaquelNeural': '🇵🇹 Raquel (Portugal, Feminino)',
    # Italiano
    'it-IT-DiegoNeural': '🇮🇹 Diego (Italy, Male)',
    'it-IT-ElsaNeural': '🇮🇹 Elsa (Italy, Female)',
    # Japonés
    'ja-JP-KeitaNeural': '🇯🇵 Keita (Japan, Male)',
    'ja-JP-NanamiNeural': '🇯🇵 Nanami (Japan, Female)',
    # Coreano
    'ko-KR-InJoonNeural': '🇰🇷 InJoon (Korea, Male)',
    'ko-KR-SunHiNeural': '🇰🇷 SunHi (Korea, Female)',
    # Chino
    'zh-CN-YunxiNeural': '🇨🇳 Yunxi (China, Male)',
    'zh-CN-XiaoxiaoNeural': '🇨🇳 Xiaoxiao (China, Female)',
    # Ruso
    'ru-RU-DmitryNeural': '🇷🇺 Dmitry (Russia, Male)',
    'ru-RU-SvetlanaNeural': '🇷🇺 Svetlana (Russia, Female)',
    # Árabe
    'ar-SA-HamedNeural': '🇸🇦 Hamed (Saudi, Male)',
    'ar-SA-ZariyahNeural': '🇸🇦 Zariyah (Saudi, Female)',
    # Hindi
    'hi-IN-MadhurNeural': '🇮🇳 Madhur (India, Male)',
    'hi-IN-SwaraNeural': '🇮🇳 Swara (India, Female)',
    # Turco
    'tr-TR-AhmetNeural': '🇹🇷 Ahmet (Turkey, Male)',
    'tr-TR-EmelNeural': '🇹🇷 Emel (Turkey, Female)',
    # Polaco
    'pl-PL-MarekNeural': '🇵🇱 Marek (Poland, Male)',
    'pl-PL-ZofiaNeural': '🇵🇱 Zofia (Poland, Female)',
    # Holandés
    'nl-NL-MaartenNeural': '🇳🇱 Maarten (Netherlands, Male)',
    'nl-NL-ColetteNeural': '🇳🇱 Colette (Netherlands, Female)',
}

LANGUAGES = {
    'auto': '🔄 Auto-detectar',
    'es': '🇪🇸 Español',
    'en': '🇺🇸 English',
    'fr': '🇫🇷 Français',
    'de': '🇩🇪 Deutsch',
    'it': '🇮🇹 Italiano',
    'pt': '🇧🇷 Português',
    'ru': '🇷🇺 Русский',
    'ja': '🇯🇵 日本語',
    'ko': '🇰🇷 한국어',
    'zh': '🇨🇳 中文',
    'ar': '🇸🇦 العربية',
    'hi': '🇮🇳 हिन्दी',
    'tr': '🇹🇷 Türkçe',
    'pl': '🇵🇱 Polski',
    'nl': '🇳🇱 Nederlands',
    'sv': '🇸🇪 Svenska',
    'da': '🇩🇰 Dansk',
    'no': '🇳🇴 Norsk',
    'fi': '🇫🇮 Suomi',
    'el': '🇬🇷 Ελληνικά',
    'he': '🇮🇱 עברית',
    'th': '🇹🇭 ไทย',
    'vi': '🇻🇳 Tiếng Việt',
    'id': '🇮🇩 Bahasa Indonesia',
    'ms': '🇲🇾 Bahasa Melayu',
    'uk': '🇺🇦 Українська',
    'cs': '🇨🇿 Čeština',
    'ro': '🇷🇴 Română',
    'hu': '🇭🇺 Magyar',
}

WHISPER_MODELS = {
    'tiny': '⚡ Tiny (más rápido, menos preciso)',
    'base': '⚖️ Base (equilibrado, recomendado)',
    'small': '📊 Small (mejor precisión)',
    'medium': '🎯 Medium (alta precisión, lento)',
}

# Logging
log_file = LOGS_DIR / f'server_{datetime.now().strftime("%Y%m%d")}.log'
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(log_file, encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('SoniTranslate')

# ============================================================
# SISTEMA DE COLA
# ============================================================

class JobStatus(Enum):
    PENDING = 'pending'
    PROCESSING = 'processing'
    COMPLETED = 'completed'
    FAILED = 'failed'
    CANCELLED = 'cancelled'

@dataclass
class Job:
    id: str
    input_file: str
    output_file: str
    status: str
    created_at: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    error: Optional[str] = None
    progress: int = 0
    progress_message: str = 'En cola'
    source_language: str = 'auto'
    target_language: str = 'es'
    whisper_model: str = 'base'
    tts_voice: str = 'es-ES-AlvaroNeural'
    original_filename: str = ''
    file_size: int = 0
    duration: Optional[float] = None
    retries: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Job':
        valid = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in data.items() if k in valid})
    
    def save(self):
        with open(QUEUE_DIR / f"{self.id}.json", 'w', encoding='utf-8') as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)
    
    @classmethod
    def load(cls, job_id: str) -> Optional['Job']:
        fp = QUEUE_DIR / f"{job_id}.json"
        if not fp.exists():
            return None
        try:
            with open(fp, 'r', encoding='utf-8') as f:
                return cls.from_dict(json.load(f))
        except:
            return None
    
    def delete(self):
        fp = QUEUE_DIR / f"{self.id}.json"
        if fp.exists():
            fp.unlink()

class QueueManager:
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._lock = threading.Lock()
        return cls._instance
    
    def create_job(self, input_file: Path, target_language: str = 'es',
                   source_language: str = 'auto', whisper_model: str = 'base',
                   tts_voice: str = 'es-ES-AlvaroNeural') -> Job:
        with self._lock:
            job_id = datetime.now().strftime('%H%M%S') + '_' + str(uuid.uuid4())[:4]
            ts = datetime.now().strftime('%Y%m%d_%H%M%S')
            stem = "".join(c for c in input_file.stem if c.isalnum() or c in '-_ ')[:40].strip()
            stem = stem.replace(' ', '_')
            output_file = OUTPUT_DIR / f"{stem}_{target_language}_{ts}.mp4"
            
            job = Job(
                id=job_id,
                input_file=str(input_file.absolute()),
                output_file=str(output_file.absolute()),
                status=JobStatus.PENDING.value,
                created_at=datetime.now().isoformat(),
                source_language=source_language,
                target_language=target_language,
                whisper_model=whisper_model,
                tts_voice=tts_voice,
                original_filename=input_file.name,
                file_size=input_file.stat().st_size if input_file.exists() else 0,
            )
            job.save()
            logger.info(f"✅ Trabajo creado: {job_id} - {input_file.name}")
            return job
    
    def get_all_jobs(self) -> List[Job]:
        jobs = []
        for fp in QUEUE_DIR.glob('*.json'):
            job = Job.load(fp.stem)
            if job:
                jobs.append(job)
        jobs.sort(key=lambda j: j.created_at, reverse=True)
        return jobs
    
    def get_pending_jobs(self) -> List[Job]:
        return [j for j in self.get_all_jobs() if j.status == JobStatus.PENDING.value]
    
    def get_processing_jobs(self) -> List[Job]:
        return [j for j in self.get_all_jobs() if j.status == JobStatus.PROCESSING.value]
    
    def get_next_job(self) -> Optional[Job]:
        with self._lock:
            pending = sorted(
                [j for j in self.get_all_jobs() if j.status == JobStatus.PENDING.value],
                key=lambda j: j.created_at
            )
            if pending:
                job = pending[0]
                job.status = JobStatus.PROCESSING.value
                job.started_at = datetime.now().isoformat()
                job.progress_message = 'Iniciando...'
                job.save()
                return job
        return None
    
    def get_job(self, job_id: str) -> Optional[Job]:
        return Job.load(job_id)
    
    def update_progress(self, job_id: str, progress: int, message: str = ''):
        job = self.get_job(job_id)
        if job:
            job.progress = min(100, max(0, progress))
            if message:
                job.progress_message = message
            job.save()
    
    def complete_job(self, job_id: str, output_file: Optional[str] = None):
        with self._lock:
            job = self.get_job(job_id)
            if job:
                job.status = JobStatus.COMPLETED.value
                job.completed_at = datetime.now().isoformat()
                job.progress = 100
                job.progress_message = '✅ Completado'
                if output_file:
                    job.output_file = output_file
                job.save()
                logger.info(f"✅ Completado: {job_id}")
    
    def fail_job(self, job_id: str, error: str):
        with self._lock:
            job = self.get_job(job_id)
            if job:
                job.retries += 1
                if job.retries < CONFIG['retry_failed']:
                    job.status = JobStatus.PENDING.value
                    job.error = f"Intento {job.retries}: {error}"
                    job.progress_message = f'⚠️ Reintentando ({job.retries}/{CONFIG["retry_failed"]})'
                    logger.warning(f"⚠️ Reintentando {job_id}")
                else:
                    job.status = JobStatus.FAILED.value
                    job.error = error
                    job.progress_message = '❌ Fallido'
                    logger.error(f"❌ Fallido: {job_id} - {error}")
                job.completed_at = datetime.now().isoformat()
                job.save()
    
    def cancel_job(self, job_id: str) -> Tuple[bool, str]:
        with self._lock:
            job = self.get_job(job_id)
            if not job:
                return False, f"Trabajo {job_id} no encontrado"
            if job.status not in [JobStatus.PENDING.value]:
                return False, f"No se puede cancelar (estado: {job.status})"
            job.status = JobStatus.CANCELLED.value
            job.completed_at = datetime.now().isoformat()
            job.progress_message = '🚫 Cancelado'
            job.save()
            logger.info(f"🚫 Cancelado: {job_id}")
            return True, f"Trabajo {job_id} cancelado"
    
    def delete_job(self, job_id: str) -> Tuple[bool, str]:
        job = self.get_job(job_id)
        if not job:
            return False, f"Trabajo {job_id} no encontrado"
        if job.status in [JobStatus.PROCESSING.value]:
            return False, "No se puede eliminar un trabajo en proceso"
        
        # Eliminar archivos asociados
        try:
            if job.status == JobStatus.COMPLETED.value:
                out = Path(job.output_file)
                if out.exists():
                    out.unlink()
        except:
            pass
        
        job.delete()
        return True, f"Trabajo {job_id} eliminado"
    
    def get_stats(self) -> Dict[str, Any]:
        jobs = self.get_all_jobs()
        stats = {s.value: 0 for s in JobStatus}
        stats['total'] = len(jobs)
        total_size = 0
        for job in jobs:
            stats[job.status] += 1
            total_size += job.file_size
        stats['total_size_mb'] = round(total_size / (1024 * 1024), 1)
        return stats
    
    def cleanup_old(self, days: int = 7) -> int:
        cutoff = datetime.now() - timedelta(days=days)
        cleaned = 0
        for job in self.get_all_jobs():
            if job.status in [JobStatus.COMPLETED.value, JobStatus.FAILED.value, JobStatus.CANCELLED.value]:
                try:
                    if job.completed_at:
                        completed = datetime.fromisoformat(job.completed_at)
                        if completed < cutoff:
                            job.delete()
                            cleaned += 1
                except:
                    pass
        return cleaned

queue_manager = QueueManager()

def scan_input_folder() -> Tuple[int, List[str]]:
    """Escanea carpeta input y añade archivos nuevos."""
    extensions = CONFIG['video_extensions'] | CONFIG['audio_extensions']
    existing = {j.original_filename for j in queue_manager.get_all_jobs()}
    
    added = []
    for filepath in INPUT_DIR.iterdir():
        if filepath.is_file() and filepath.suffix.lower() in extensions:
            if filepath.name not in existing:
                try:
                    # Verificar que el archivo está completo
                    size1 = filepath.stat().st_size
                    time.sleep(0.5)
                    size2 = filepath.stat().st_size
                    if size1 == size2 and size2 > 0:
                        queue_manager.create_job(
                            input_file=filepath,
                            target_language=CONFIG['default_target_lang'],
                            whisper_model=CONFIG['whisper_model'],
                            tts_voice=CONFIG['default_voice'],
                        )
                        added.append(filepath.name)
                except Exception as e:
                    logger.error(f"Error añadiendo {filepath}: {e}")
    
    return len(added), added

# ============================================================
# DESCARGADOR DE VIDEOS
# ============================================================

def download_video(url: str, progress_callback=None) -> Tuple[Optional[Path], str]:
    """Descarga video de URL usando yt-dlp."""
    if not url or not url.strip():
        return None, "❌ URL vacía"
    
    url = url.strip()
    
    # Detectar plataforma
    platforms = {
        'tiktok': ['tiktok.com', 'vm.tiktok.com'],
        'youtube': ['youtube.com', 'youtu.be'],
        'facebook': ['facebook.com', 'fb.watch'],
        'instagram': ['instagram.com'],
        'twitter': ['twitter.com', 'x.com'],
        'reddit': ['reddit.com', 'v.redd.it'],
        'twitch': ['twitch.tv'],
        'vimeo': ['vimeo.com'],
    }
    
    platform = 'web'
    for name, domains in platforms.items():
        if any(d in url.lower() for d in domains):
            platform = name
            break
    
    # Limpiar descargas anteriores
    for f in DOWNLOADS_DIR.glob('*'):
        try:
            f.unlink()
        except:
            pass
    
    output_tpl = str(DOWNLOADS_DIR / '%(title).60s.%(ext)s')
    
    # Comandos según plataforma
    base_args = [
        'yt-dlp',
        '--no-warnings',
        '--no-playlist',
        '-o', output_tpl,
        '--retries', '3',
        '--socket-timeout', '30',
    ]
    
    if platform == 'tiktok':
        args = base_args + ['--format', 'best[ext=mp4]/best', url]
    elif platform == 'youtube':
        args = base_args + [
            '--format', 'bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]/best',
            '--merge-output-format', 'mp4',
            url
        ]
    else:
        args = base_args + ['--format', 'best[ext=mp4]/best', url]
    
    try:
        if progress_callback:
            progress_callback(f"⏳ Descargando de {platform}...")
        
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=600,
            cwd=str(DOWNLOADS_DIR)
        )
        
        if result.returncode != 0:
            error = result.stderr[:200] if result.stderr else "Error desconocido"
            return None, f"❌ Error descargando: {error}"
        
        # Buscar archivo descargado
        downloaded = list(DOWNLOADS_DIR.glob('*'))
        video_files = [f for f in downloaded if f.suffix.lower() in CONFIG['video_extensions']]
        
        if not video_files:
            return None, "❌ No se encontró el video descargado"
        
        video_file = video_files[0]
        size_mb = video_file.stat().st_size / (1024 * 1024)
        
        return video_file, f"✅ Descargado de {platform}: {video_file.name} ({size_mb:.1f} MB)"
        
    except subprocess.TimeoutExpired:
        return None, "❌ Timeout descargando (10 min)"
    except Exception as e:
        return None, f"❌ Error: {str(e)}"

# ============================================================
# PROCESADOR DE DOBLAJE
# ============================================================

class DubbingProcessor:
    def __init__(self):
        self.whisper_model = None
        self._current_model = None
        self._stop = threading.Event()
    
    def stop(self):
        self._stop.set()
    
    def _check_stop(self):
        if self._stop.is_set():
            raise InterruptedError("Cancelado")
    
    def _run_ffmpeg(self, args: List[str], desc: str = '') -> Tuple[bool, str]:
        cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'warning'] + args
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
            if result.returncode != 0:
                return False, result.stderr[:300]
            return True, ""
        except subprocess.TimeoutExpired:
            return False, "Timeout FFmpeg"
        except Exception as e:
            return False, str(e)
    
    def _get_duration(self, video_path: Path) -> Optional[float]:
        try:
            result = subprocess.run(
                ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                 '-of', 'default=noprint_wrappers=1:nokey=1', str(video_path)],
                capture_output=True, text=True, timeout=30
            )
            return float(result.stdout.strip()) if result.returncode == 0 else None
        except:
            return None
    
    def process_job(self, job: Job) -> bool:
        logger.info(f"🎬 Procesando: {job.id} - {job.original_filename}")
        
        input_path = Path(job.input_file)
        output_path = Path(job.output_file)
        
        if not input_path.exists():
            queue_manager.fail_job(job.id, f"Archivo no encontrado")
            return False
        
        # Obtener duración
        duration = self._get_duration(input_path)
        if duration:
            job.duration = duration
            job.save()
        
        temp_dir = PROCESSING_DIR / job.id
        temp_dir.mkdir(exist_ok=True)
        
        try:
            # === PASO 1: Extraer audio ===
            self._check_stop()
            queue_manager.update_progress(job.id, 5, '🎵 Extrayendo audio...')
            
            audio_path = temp_dir / 'audio.wav'
            success, error = self._run_ffmpeg(
                ['-i', str(input_path), '-vn', '-acodec', 'pcm_s16le',
                 '-ar', '16000', '-ac', '1', str(audio_path)],
                'extraer audio'
            )
            if not success:
                raise Exception(f"Error extrayendo audio: {error}")
            
            # === PASO 2: Transcribir ===
            self._check_stop()
            queue_manager.update_progress(job.id, 15, f'🎤 Transcribiendo con Whisper ({job.whisper_model})...')
            
            segments, detected_lang = self._transcribe(audio_path, job)
            logger.info(f"   Idioma detectado: {detected_lang}, Segmentos: {len(segments)}")
            
            if not segments:
                raise Exception("No se detectó habla en el archivo")
            
            # === PASO 3: Traducir ===
            self._check_stop()
            queue_manager.update_progress(job.id, 40, f'🌐 Traduciendo a {LANGUAGES.get(job.target_language, job.target_language)}...')
            
            translated = self._translate(segments, job)
            
            # === PASO 4: Generar TTS ===
            self._check_stop()
            queue_manager.update_progress(job.id, 65, f'🔊 Generando voz ({job.tts_voice.split("-")[0]})...')
            
            tts_path = temp_dir / 'tts.mp3'
            self._generate_tts(translated, tts_path, job)
            
            # === PASO 5: Combinar ===
            self._check_stop()
            queue_manager.update_progress(job.id, 85, '🎬 Combinando video y audio...')
            
            success, error = self._combine(input_path, tts_path, output_path)
            if not success:
                raise Exception(f"Error combinando: {error}")
            
            # Verificar resultado
            if not output_path.exists() or output_path.stat().st_size < 1000:
                raise Exception("Archivo de salida inválido")
            
            queue_manager.update_progress(job.id, 100, '✅ Completado')
            queue_manager.complete_job(job.id, str(output_path))
            
            logger.info(f"✅ Completado: {job.id} -> {output_path.name}")
            return True
            
        except InterruptedError:
            queue_manager.fail_job(job.id, "Cancelado por usuario")
            return False
        except Exception as e:
            logger.exception(f"Error procesando {job.id}")
            queue_manager.fail_job(job.id, str(e)[:200])
            return False
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)
    
    def _transcribe(self, audio_path: Path, job: Job) -> Tuple[List[Dict], str]:
        import whisper
        
        if self.whisper_model is None or self._current_model != job.whisper_model:
            logger.info(f"   Cargando modelo Whisper: {job.whisper_model}")
            self.whisper_model = whisper.load_model(job.whisper_model)
            self._current_model = job.whisper_model
        
        lang = None if job.source_language == 'auto' else job.source_language
        result = self.whisper_model.transcribe(str(audio_path), language=lang, verbose=False)
        
        segments = []
        for seg in result.get('segments', []):
            text = seg.get('text', '').strip()
            if text:
                segments.append({
                    'start': seg['start'],
                    'end': seg['end'],
                    'text': text
                })
        
        return segments, result.get('language', 'unknown')
    
    def _translate(self, segments: List[Dict], job: Job) -> List[Dict]:
        if job.source_language == job.target_language:
            return segments
        
        from deep_translator import GoogleTranslator
        translator = GoogleTranslator(source='auto', target=job.target_language)
        
        translated = []
        total = len(segments)
        
        for i, seg in enumerate(segments):
            self._check_stop()
            try:
                text = translator.translate(seg['text'])
                translated.append({
                    'start': seg['start'],
                    'end': seg['end'],
                    'text': text or seg['text']
                })
            except Exception as e:
                logger.warning(f"Error traduciendo segmento {i}: {e}")
                translated.append(seg)
            
            # Actualizar progreso
            progress = 40 + int(25 * (i + 1) / total)
            queue_manager.update_progress(job.id, progress, f'🌐 Traduciendo... {i+1}/{total}')
        
        return translated
    
    def _generate_tts(self, segments: List[Dict], output_path: Path, job: Job):
        import edge_tts
        
        full_text = ' '.join([s['text'] for s in segments])
        if not full_text.strip():
            raise Exception("Sin texto para sintetizar")
        
        async def generate():
            comm = edge_tts.Communicate(full_text, job.tts_voice)
            await comm.save(str(output_path))
        
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
        
        loop.run_until_complete(generate())
        
        if not output_path.exists() or output_path.stat().st_size < 100:
            raise Exception("Error generando audio TTS")
    
    def _combine(self, video: Path, audio: Path, output: Path) -> Tuple[bool, str]:
        # Intentar copiar codec de video
        success, error = self._run_ffmpeg(
            ['-i', str(video), '-i', str(audio),
             '-c:v', 'copy', '-map', '0:v:0', '-map', '1:a:0',
             '-shortest', str(output)],
            'combinar (copy)'
        )
        
        if not success:
            # Re-encodear si falla
            success, error = self._run_ffmpeg(
                ['-i', str(video), '-i', str(audio),
                 '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
                 '-c:a', 'aac', '-b:a', '128k',
                 '-map', '0:v:0', '-map', '1:a:0',
                 '-shortest', str(output)],
                'combinar (reencode)'
            )
        
        return success, error

# ============================================================
# WORKER
# ============================================================

class Worker:
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance.processor = DubbingProcessor()
            cls._instance._running = False
            cls._instance._thread = None
        return cls._instance
    
    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        logger.info("🔄 Worker iniciado")
    
    def stop(self):
        self._running = False
        self.processor.stop()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)
        logger.info("⏹️ Worker detenido")
    
    def is_running(self) -> bool:
        return self._running and self._thread and self._thread.is_alive()
    
    def _loop(self):
        while self._running:
            try:
                # Escanear carpeta input
                count, _ = scan_input_folder()
                if count > 0:
                    logger.info(f"📁 {count} archivo(s) nuevo(s) detectado(s)")
                
                # Procesar siguiente trabajo
                job = queue_manager.get_next_job()
                if job:
                    self.processor.process_job(job)
                else:
                    time.sleep(CONFIG['poll_interval'])
                    
            except Exception as e:
                logger.exception(f"Error en worker: {e}")
                time.sleep(10)

worker = Worker()

# ============================================================
# INTERFAZ GRADIO
# ============================================================

def create_gradio_app():
    import gradio as gr
    
    # CSS mejorado
    css = """
    .gradio-container {
        max-width: 1400px !important;
        margin: 0 auto !important;
    }
    
    .header {
        text-align: center;
        padding: 25px;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border-radius: 16px;
        color: white;
        margin-bottom: 20px;
        box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
    }
    
    .header h1 {
        margin: 0;
        font-size: 32px;
        font-weight: 700;
    }
    
    .header p {
        margin: 8px 0 0;
        opacity: 0.9;
        font-size: 14px;
    }
    
    .stats-container {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
        gap: 12px;
        margin: 15px 0;
    }
    
    .stat-card {
        background: linear-gradient(145deg, #f8f9fa, #e9ecef);
        border-radius: 12px;
        padding: 15px;
        text-align: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    }
    
    .stat-number {
        font-size: 28px;
        font-weight: 700;
        color: #495057;
    }
    
    .stat-label {
        font-size: 12px;
        color: #6c757d;
        margin-top: 4px;
    }
    
    .job-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 13px;
    }
    
    .job-table th {
        background: #f1f3f4;
        padding: 12px 8px;
        text-align: left;
        font-weight: 600;
        border-bottom: 2px solid #dee2e6;
    }
    
    .job-table td {
        padding: 10px 8px;
        border-bottom: 1px solid #e9ecef;
    }
    
    .job-table tr:hover {
        background: #f8f9fa;
    }
    
    .status-pending { color: #f59e0b; }
    .status-processing { color: #3b82f6; }
    .status-completed { color: #10b981; }
    .status-failed { color: #ef4444; }
    .status-cancelled { color: #6b7280; }
    
    .progress-bar {
        background: #e9ecef;
        border-radius: 10px;
        height: 8px;
        overflow: hidden;
    }
    
    .progress-fill {
        height: 100%;
        background: linear-gradient(90deg, #667eea, #764ba2);
        transition: width 0.3s ease;
    }
    
    .file-info {
        background: #f8f9fa;
        border-radius: 8px;
        padding: 12px;
        margin: 10px 0;
        font-size: 13px;
    }
    
    .tip-box {
        background: linear-gradient(145deg, #e8f4fd, #d1e8fa);
        border-left: 4px solid #3b82f6;
        padding: 12px 15px;
        border-radius: 0 8px 8px 0;
        margin: 10px 0;
        font-size: 13px;
    }
    
    @media (max-width: 768px) {
        .header h1 { font-size: 24px; }
        .stats-container { grid-template-columns: repeat(2, 1fr); }
    }
    """
    
    def get_stats_html():
        stats = queue_manager.get_stats()
        worker_status = "🟢 Activo" if worker.is_running() else "🔴 Detenido"
        
        return f"""
        <div class="stats-container">
            <div class="stat-card">
                <div class="stat-number" style="color: #f59e0b;">⏳ {stats['pending']}</div>
                <div class="stat-label">Pendientes</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" style="color: #3b82f6;">🔄 {stats['processing']}</div>
                <div class="stat-label">Procesando</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" style="color: #10b981;">✅ {stats['completed']}</div>
                <div class="stat-label">Completados</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" style="color: #ef4444;">❌ {stats['failed']}</div>
                <div class="stat-label">Fallidos</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">📊 {stats['total']}</div>
                <div class="stat-label">Total</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" style="font-size: 16px;">{worker_status}</div>
                <div class="stat-label">Worker</div>
            </div>
        </div>
        """
    
    def get_jobs_html(filter_status: str = 'all', limit: int = 50):
        jobs = queue_manager.get_all_jobs()
        
        if filter_status and filter_status != 'all':
            jobs = [j for j in jobs if j.status == filter_status]
        
        jobs = jobs[:limit]
        
        if not jobs:
            return "<p style='text-align:center; color:#6c757d; padding:40px;'>📭 No hay trabajos</p>"
        
        status_icons = {
            'pending': ('⏳', 'status-pending'),
            'processing': ('🔄', 'status-processing'),
            'completed': ('✅', 'status-completed'),
            'failed': ('❌', 'status-failed'),
            'cancelled': ('🚫', 'status-cancelled'),
        }
        
        html = """<table class="job-table">
        <thead>
            <tr>
                <th>ID</th>
                <th>Estado</th>
                <th>Archivo</th>
                <th>Progreso</th>
                <th>Idioma</th>
                <th>Mensaje</th>
                <th>Creado</th>
            </tr>
        </thead>
        <tbody>"""
        
        for job in jobs:
            icon, css_class = status_icons.get(job.status, ('?', ''))
            name = job.original_filename
            if len(name) > 35:
                name = name[:32] + '...'
            
            # Barra de progreso
            progress_html = f"""
            <div class="progress-bar" style="width:80px;">
                <div class="progress-fill" style="width:{job.progress}%;"></div>
            </div>
            <span style="font-size:11px;margin-left:5px;">{job.progress}%</span>
            """
            
            created = job.created_at[:16].replace('T', ' ') if job.created_at else '-'
            
            html += f"""
            <tr>
                <td><code>{job.id}</code></td>
                <td class="{css_class}">{icon} {job.status}</td>
                <td title="{job.original_filename}">{name}</td>
                <td>{progress_html}</td>
                <td>{job.target_language.upper()}</td>
                <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;">{job.progress_message or '-'}</td>
                <td style="font-size:11px;">{created}</td>
            </tr>"""
        
        html += "</tbody></table>"
        return html
    
    def upload_and_process(file, target_lang, source_lang, whisper_model, voice):
        if file is None:
            return "❌ No se seleccionó ningún archivo", get_stats_html(), get_jobs_html()
        
        try:
            # Copiar a input
            src = Path(file.name if hasattr(file, 'name') else file)
            dest = INPUT_DIR / src.name
            
            # Evitar duplicados
            if dest.exists():
                stem = dest.stem
                suffix = dest.suffix
                dest = INPUT_DIR / f"{stem}_{datetime.now().strftime('%H%M%S')}{suffix}"
            
            shutil.copy2(src, dest)
            
            # Crear trabajo
            job = queue_manager.create_job(
                input_file=dest,
                target_language=target_lang,
                source_language=source_lang,
                whisper_model=whisper_model,
                tts_voice=voice
            )
            
            size_mb = dest.stat().st_size / (1024 * 1024)
            msg = f"✅ Trabajo **{job.id}** creado\n\n"
            msg += f"📁 Archivo: `{dest.name}` ({size_mb:.1f} MB)\n"
            msg += f"🌐 {LANGUAGES.get(source_lang, source_lang)} → {LANGUAGES.get(target_lang, target_lang)}\n"
            msg += f"🎤 Voz: {voice.split('-')[0]}"
            
            return msg, get_stats_html(), get_jobs_html()
            
        except Exception as e:
            return f"❌ Error: {str(e)}", get_stats_html(), get_jobs_html()
    
    def download_and_process(url, target_lang, source_lang, whisper_model, voice):
        if not url or not url.strip():
            return "❌ Ingresa una URL", None, get_stats_html(), get_jobs_html()
        
        try:
            # Descargar
            video_path, msg = download_video(url)
            
            if not video_path:
                return msg, None, get_stats_html(), get_jobs_html()
            
            # Mover a input
            dest = INPUT_DIR / video_path.name
            if dest.exists():
                dest = INPUT_DIR / f"{video_path.stem}_{datetime.now().strftime('%H%M%S')}{video_path.suffix}"
            
            shutil.move(str(video_path), str(dest))
            
            # Crear trabajo
            job = queue_manager.create_job(
                input_file=dest,
                target_language=target_lang,
                source_language=source_lang,
                whisper_model=whisper_model,
                tts_voice=voice
            )
            
            result_msg = f"✅ Descargado y trabajo **{job.id}** creado\n\n"
            result_msg += f"📁 {dest.name}\n"
            result_msg += f"🌐 {LANGUAGES.get(source_lang, source_lang)} → {LANGUAGES.get(target_lang, target_lang)}"
            
            # Preview del video
            return result_msg, str(dest), get_stats_html(), get_jobs_html()
            
        except Exception as e:
            return f"❌ Error: {str(e)}", None, get_stats_html(), get_jobs_html()
    
    def cancel_job_fn(job_id):
        if not job_id or not job_id.strip():
            return "⚠️ Ingresa un ID de trabajo", get_jobs_html()
        
        success, msg = queue_manager.cancel_job(job_id.strip())
        return msg, get_jobs_html()
    
    def delete_job_fn(job_id):
        if not job_id or not job_id.strip():
            return "⚠️ Ingresa un ID de trabajo", get_jobs_html()
        
        success, msg = queue_manager.delete_job(job_id.strip())
        return msg, get_jobs_html()
    
    def refresh_all():
        return get_stats_html(), get_jobs_html()
    
    def scan_folder():
        count, files = scan_input_folder()
        if count > 0:
            msg = f"📁 **{count}** archivo(s) añadido(s):\n" + "\n".join([f"• {f}" for f in files[:5]])
            if count > 5:
                msg += f"\n• ... y {count - 5} más"
        else:
            msg = "📭 No hay archivos nuevos en la carpeta input"
        return msg, get_stats_html(), get_jobs_html()
    
    def cleanup_old_jobs():
        cleaned = queue_manager.cleanup_old(days=7)
        return f"🧹 {cleaned} trabajo(s) antiguo(s) eliminado(s)", get_stats_html(), get_jobs_html()
    
    def filter_jobs(status):
        return get_jobs_html(filter_status=status)
    
    def get_output_files():
        files = []
        for f in OUTPUT_DIR.glob('*'):
            if f.is_file() and f.suffix.lower() in CONFIG['video_extensions']:
                size_mb = f.stat().st_size / (1024 * 1024)
                files.append(f"{f.name} ({size_mb:.1f} MB)")
        return "\n".join(files) if files else "No hay archivos de salida"
    
    def get_job_details(job_id):
        if not job_id:
            return "Selecciona un trabajo"
        
        job = queue_manager.get_job(job_id.strip())
        if not job:
            return f"Trabajo {job_id} no encontrado"
        
        details = f"""
### Trabajo: {job.id}

**Estado:** {job.status}
**Progreso:** {job.progress}% - {job.progress_message}

**Archivo:** {job.original_filename}
**Tamaño:** {job.file_size / (1024*1024):.1f} MB
**Duración:** {job.duration:.1f}s si job.duration else 'N/A'}

**Configuración:**
- Origen: {LANGUAGES.get(job.source_language, job.source_language)}
- Destino: {LANGUAGES.get(job.target_language, job.target_language)}
- Modelo: {job.whisper_model}
- Voz: {job.tts_voice}

**Tiempos:**
- Creado: {job.created_at}
- Iniciado: {job.started_at or 'N/A'}
- Completado: {job.completed_at or 'N/A'}

**Archivos:**
- Input: `{job.input_file}`
- Output: `{job.output_file}`
        """
        
        if job.error:
            details += f"\n\n**Error:** {job.error}"
        
        return details
    
    # ============ Construir interfaz ============
    
    with gr.Blocks(css=css, title="SoniTranslate Server", theme=gr.themes.Soft()) as app:
        
        # Header
        gr.HTML("""
        <div class="header">
            <h1>🎬 SoniTranslate Server</h1>
            <p>Sistema de doblaje automático con IA • Transcripción • Traducción • Síntesis de voz</p>
        </div>
        """)
        
        with gr.Tabs():
            # ============ TAB: Añadir Trabajo ============
            with gr.Tab("➕ Nuevo Trabajo"):
                with gr.Row():
                    with gr.Column(scale=1):
                        gr.Markdown("### 📤 Subir Archivo")
                        file_input = gr.File(
                            label="Video o Audio",
                            file_types=['video', 'audio'],
                            type="filepath"
                        )
                        
                        gr.HTML('<div class="tip-box">💡 Formatos: MP4, MKV, AVI, MOV, MP3, WAV, etc.</div>')
                        
                        gr.Markdown("### 🔗 O desde URL")
                        url_input = gr.Textbox(
                            label="URL del video",
                            placeholder="https://youtube.com/watch?v=... o TikTok, Instagram, etc.",
                            lines=1
                        )
                    
                    with gr.Column(scale=1):
                        gr.Markdown("### ⚙️ Configuración")
                        
                        with gr.Row():
                            source_lang = gr.Dropdown(
                                choices=list(LANGUAGES.keys()),
                                value='auto',
                                label="🎤 Idioma origen"
                            )
                            target_lang = gr.Dropdown(
                                choices=list(LANGUAGES.keys()),
                                value='es',
                                label="🌐 Idioma destino"
                            )
                        
                        whisper_model = gr.Dropdown(
                            choices=list(WHISPER_MODELS.keys()),
                            value='base',
                            label="🎯 Modelo de transcripción"
                        )
                        gr.HTML('<div class="tip-box">⚡ En CPU: usa <b>tiny</b> o <b>base</b> para mayor velocidad</div>')
                        
                        voice = gr.Dropdown(
                            choices=list(VOICES.keys()),
                            value='es-ES-AlvaroNeural',
                            label="🎤 Voz para el doblaje"
                        )
                
                with gr.Row():
                    upload_btn = gr.Button("📤 Subir y Procesar", variant="primary", scale=2)
                    download_btn = gr.Button("🔗 Descargar URL y Procesar", variant="secondary", scale=2)
                
                result_msg = gr.Markdown("")
                preview_video = gr.Video(label="Vista previa", visible=False)
            
            # ============ TAB: Cola de Trabajos ============
            with gr.Tab("📋 Cola de Trabajos"):
                stats_html = gr.HTML(get_stats_html())
                
                with gr.Row():
                    refresh_btn = gr.Button("🔄 Actualizar", variant="secondary")
                    scan_btn = gr.Button("📁 Escanear Carpeta Input", variant="secondary")
                    cleanup_btn = gr.Button("🧹 Limpiar Antiguos", variant="secondary")
                
                with gr.Row():
                    filter_dropdown = gr.Dropdown(
                        choices=[('Todos', 'all'), ('Pendientes', 'pending'), ('Procesando', 'processing'),
                                ('Completados', 'completed'), ('Fallidos', 'failed')],
                        value='all',
                        label="Filtrar por estado",
                        scale=1
                    )
                
                jobs_html = gr.HTML(get_jobs_html())
                
                gr.Markdown("### 🛠️ Acciones")
                with gr.Row():
                    job_id_input = gr.Textbox(label="ID del trabajo", placeholder="ej: 143052_a1b2", scale=2)
                    cancel_btn = gr.Button("🚫 Cancelar", variant="stop", scale=1)
                    delete_btn = gr.Button("🗑️ Eliminar", variant="secondary", scale=1)
                
                action_msg = gr.Markdown("")
            
            # ============ TAB: Archivos de Salida ============
            with gr.Tab("📂 Archivos de Salida"):
                gr.Markdown(f"### 📁 Carpeta de salida: `{OUTPUT_DIR}`")
                
                refresh_output_btn = gr.Button("🔄 Actualizar lista")
                output_list = gr.Textbox(
                    label="Archivos disponibles",
                    value=get_output_files(),
                    lines=15,
                    interactive=False
                )
                
                gr.Markdown(f"""
                ### 📥 Descargar archivos
                
                Los archivos procesados se guardan en:
                ```
                {OUTPUT_DIR}
                ```
                
                Puedes acceder a ellos directamente desde el sistema de archivos.
                """)
            
            # ============ TAB: Configuración ============
            with gr.Tab("⚙️ Configuración"):
                gr.Markdown(f"""
                ### 📁 Directorios
                
                | Directorio | Ruta |
                |------------|------|
                | 📥 Input | `{INPUT_DIR}` |
                | 📤 Output | `{OUTPUT_DIR}` |
                | 📋 Cola | `{QUEUE_DIR}` |
                | 📝 Logs | `{LOGS_DIR}` |
                | 💾 Descargas | `{DOWNLOADS_DIR}` |
                
                ### 💡 Modo automático
                
                Coloca archivos en la carpeta **Input** y el sistema los procesará automáticamente.
                
                ### 🎤 Voces disponibles
                """)
                
                # Mostrar voces por idioma
                voices_by_lang = {}
                for voice_id, desc in VOICES.items():
                    lang = voice_id.split('-')[0]
                    if lang not in voices_by_lang:
                        voices_by_lang[lang] = []
                    voices_by_lang[lang].append(f"`{voice_id}`: {desc}")
                
                for lang, voices_list in list(voices_by_lang.items())[:6]:
                    gr.Markdown(f"**{lang.upper()}:** " + " | ".join(voices_list[:3]))
                
                gr.Markdown(f"""
                ### 📊 Modelos Whisper
                
                | Modelo | Descripción | Velocidad CPU |
                |--------|-------------|---------------|
                | tiny | Muy rápido, menos preciso | ⚡⚡⚡⚡ |
                | base | Equilibrado (recomendado) | ⚡⚡⚡ |
                | small | Mejor precisión | ⚡⚡ |
                | medium | Alta precisión | ⚡ |
                
                ### 🖥️ Uso por línea de comandos
                
                ```bash
                # Ver estado
                ./sonitranslate.sh status
                
                # Añadir archivo
                ./sonitranslate.sh add video.mp4
                
                # Ver logs
                ./sonitranslate.sh logs
                ```
                """)
        
        # ============ Eventos ============
        
        # Subir archivo
        upload_btn.click(
            upload_and_process,
            inputs=[file_input, target_lang, source_lang, whisper_model, voice],
            outputs=[result_msg, stats_html, jobs_html]
        )
        
        # Descargar URL
        download_btn.click(
            download_and_process,
            inputs=[url_input, target_lang, source_lang, whisper_model, voice],
            outputs=[result_msg, preview_video, stats_html, jobs_html]
        )
        
        # Actualizar
        refresh_btn.click(refresh_all, outputs=[stats_html, jobs_html])
        
        # Escanear
        scan_btn.click(scan_folder, outputs=[action_msg, stats_html, jobs_html])
        
        # Limpiar
        cleanup_btn.click(cleanup_old_jobs, outputs=[action_msg, stats_html, jobs_html])
        
        # Filtrar
        filter_dropdown.change(filter_jobs, inputs=[filter_dropdown], outputs=[jobs_html])
        
        # Cancelar/Eliminar
        cancel_btn.click(cancel_job_fn, inputs=[job_id_input], outputs=[action_msg, jobs_html])
        delete_btn.click(delete_job_fn, inputs=[job_id_input], outputs=[action_msg, jobs_html])
        
        # Actualizar salida
        refresh_output_btn.click(lambda: get_output_files(), outputs=[output_list])
        
        # Auto-refresh cada 8 segundos
        app.load(refresh_all, outputs=[stats_html, jobs_html], every=8)
    
    return app

# ============================================================
# MAIN
# ============================================================

def main():
    parser = argparse.ArgumentParser(description='SoniTranslate Server')
    parser.add_argument('--port', type=int, default=CONFIG['web_port'], help='Puerto web')
    parser.add_argument('--share', action='store_true', help='Crear enlace público')
    parser.add_argument('--status', action='store_true', help='Ver estado')
    parser.add_argument('--add', metavar='FILE', help='Añadir archivo')
    parser.add_argument('--lang', default='es', help='Idioma destino')
    parser.add_argument('--model', default='base', help='Modelo Whisper')
    parser.add_argument('--voice', default='es-ES-AlvaroNeural', help='Voz TTS')
    parser.add_argument('--scan', action='store_true', help='Escanear input')
    parser.add_argument('--voices', action='store_true', help='Listar voces')
    
    args = parser.parse_args()
    
    # Comandos simples
    if args.status:
        stats = queue_manager.get_stats()
        print("\n" + "=" * 50)
        print("📊 Estado de SoniTranslate")
        print("=" * 50)
        print(f"  ⏳ Pendientes:  {stats['pending']}")
        print(f"  🔄 Procesando:  {stats['processing']}")
        print(f"  ✅ Completados: {stats['completed']}")
        print(f"  ❌ Fallidos:    {stats['failed']}")
        print(f"  📊 Total:       {stats['total']}")
        print(f"  💾 Tamaño:      {stats['total_size_mb']} MB")
        
        pending = queue_manager.get_pending_jobs()
        if pending:
            print(f"\n📋 Próximos en cola:")
            for job in pending[:5]:
                print(f"  • {job.id}: {job.original_filename}")
        print()
        return
    
    if args.voices:
        print("\n🎤 Voces disponibles:\n")
        for voice_id, desc in VOICES.items():
            print(f"  {voice_id}: {desc}")
        return
    
    if args.scan:
        count, files = scan_input_folder()
        print(f"📁 {count} archivo(s) añadido(s)")
        for f in files:
            print(f"  • {f}")
        return
    
    if args.add:
        fp = Path(args.add)
        if not fp.exists():
            print(f"❌ Archivo no encontrado: {fp}")
            return
        job = queue_manager.create_job(fp, args.lang, 'auto', args.model, args.voice)
        print(f"✅ Trabajo creado: {job.id}")
        print(f"   Archivo: {job.original_filename}")
        print(f"   Idioma:  {args.lang}")
        print(f"   Voz:     {args.voice}")
        return
    
    # Servidor completo
    print("=" * 60)
    print("🎬 SoniTranslate Server")
    print("=" * 60)
    print(f"📁 Input:  {INPUT_DIR}")
    print(f"📁 Output: {OUTPUT_DIR}")
    print(f"🌐 Puerto: {args.port}")
    print()
    
    # Manejar señales
    def signal_handler(sig, frame):
        print("\n⏹️ Deteniendo servidor...")
        worker.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Iniciar worker
    worker.start()
    
    # Crear e iniciar Gradio
    app = create_gradio_app()
    
    print(f"\n🌐 Abriendo interfaz web...")
    print(f"   Local:  http://localhost:{args.port}")
    if args.share:
        print("   Creando enlace público...")
    print()
    
    app.launch(
        server_name='0.0.0.0',
        server_port=args.port,
        share=args.share,
        quiet=False,
        show_error=True
    )

if __name__ == '__main__':
    main()
PYTHON_EOF

    chmod +x "$BASE_DIR/server.py"
    log_success "Servidor Python creado en $BASE_DIR/server.py"
}

# ============================================================
# INSTALACIÓN
# ============================================================

cmd_install() {
    print_banner
    log_info "Instalando SoniTranslate..."
    
    mkdir -p "$BASE_DIR"/{input,output,processing,queue,logs,downloads}
    
    # Verificar Miniconda
    if ! command -v conda &> /dev/null; then
        log_warning "Miniconda no encontrado. Instalando..."
        
        cd /tmp
        curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o miniconda.sh
        bash miniconda.sh -b -p "$HOME/miniconda3"
        rm miniconda.sh
        
        export PATH="$HOME/miniconda3/bin:$PATH"
        "$HOME/miniconda3/bin/conda" init bash
        
        log_success "Miniconda instalado"
        echo ""
        log_warning "Ejecuta estos comandos:"
        echo "  source ~/.bashrc"
        echo "  ./sonitranslate.sh install"
        exit 0
    fi
    
    log_success "Miniconda: $(conda --version)"
    
    # Activar conda
    CONDA_BASE=$(conda info --base)
    source "$CONDA_BASE/etc/profile.d/conda.sh"
    
    # Crear entorno
    if ! conda env list | grep -q "^$CONDA_ENV "; then
        log_info "Creando entorno conda '$CONDA_ENV'..."
        conda create -n "$CONDA_ENV" python="$PYTHON_VERSION" -y
    fi
    
    conda activate "$CONDA_ENV"
    log_success "Entorno activado: $CONDA_ENV"
    
    # FFmpeg
    log_info "Instalando FFmpeg..."
    conda install -c conda-forge ffmpeg -y 2>/dev/null || log_warning "FFmpeg ya instalado"
    
    # Crear servidor Python
    create_server
    
    # Dependencias Python
    log_info "Instalando dependencias Python..."
    
    cd "$BASE_DIR"
    
    pip install -q "numpy<2.0"
    
    log_info "Instalando PyTorch (CPU)..."
    pip install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
    
    log_info "Instalando Whisper..."
    pip install -q openai-whisper
    
    log_info "Instalando TTS y traducción..."
    pip install -q edge-tts deep-translator
    
    log_info "Instalando Gradio..."
    pip install -q gradio
    
    pip install -q yt-dlp pydub librosa soundfile
    
    # Verificar
    log_info "Verificando instalación..."
    python -c "import torch; print(f'  ✅ PyTorch {torch.__version__}')" || log_error "PyTorch"
    python -c "import whisper; print('  ✅ Whisper')" || log_error "Whisper"
    python -c "import edge_tts; print('  ✅ Edge-TTS')" || log_error "Edge-TTS"
    python -c "import gradio; print(f'  ✅ Gradio {gradio.__version__}')" || log_error "Gradio"
    ffmpeg -version 2>/dev/null | head -1 && echo "  ✅ FFmpeg" || log_error "FFmpeg"
    
    echo ""
    log_success "¡Instalación completada!"
    echo ""
    echo -e "${CYAN}Directorios:${NC}"
    echo "  📥 Input:  $BASE_DIR/input"
    echo "  📤 Output: $BASE_DIR/output"
    echo ""
    echo -e "${CYAN}Para iniciar:${NC}"
    echo "  ./sonitranslate.sh start"
    echo ""
}

# ============================================================
# COMANDOS
# ============================================================

activate_env() {
    CONDA_BASE=$(conda info --base 2>/dev/null)
    if [ -z "$CONDA_BASE" ]; then
        log_error "Conda no encontrado. Ejecuta: ./sonitranslate.sh install"
        exit 1
    fi
    source "$CONDA_BASE/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV" 2>/dev/null || {
        log_error "Entorno '$CONDA_ENV' no existe. Ejecuta: ./sonitranslate.sh install"
        exit 1
    }
    export SONITRANSLATE_BASE="$BASE_DIR"
    export SONITRANSLATE_PORT="$WEB_PORT"
}

cmd_start() {
    print_banner
    activate_env
    
    # Verificar que existe el servidor
    if [ ! -f "$BASE_DIR/server.py" ]; then
        log_warning "Servidor no encontrado, creando..."
        create_server
    fi
    
    log_info "Iniciando servidor Gradio en puerto $WEB_PORT..."
    cd "$BASE_DIR"
    python server.py --port "$WEB_PORT"
}

cmd_start_share() {
    print_banner
    activate_env
    
    if [ ! -f "$BASE_DIR/server.py" ]; then
        create_server
    fi
    
    log_info "Iniciando con enlace público..."
    cd "$BASE_DIR"
    python server.py --port "$WEB_PORT" --share
}

cmd_status() {
    activate_env
    cd "$BASE_DIR"
    python server.py --status
}

cmd_add() {
    if [ -z "$2" ]; then
        log_error "Uso: ./sonitranslate.sh add <archivo> [--lang es] [--model base] [--voice VOICE]"
        exit 1
    fi
    
    activate_env
    cd "$BASE_DIR"
    
    FILE="$2"
    shift 2
    
    python server.py --add "$FILE" "$@"
}

cmd_scan() {
    activate_env
    cd "$BASE_DIR"
    python server.py --scan
}

cmd_voices() {
    activate_env
    cd "$BASE_DIR"
    python server.py --voices
}

cmd_logs() {
    LOG_FILE="$BASE_DIR/logs/server_$(date +%Y%m%d).log"
    if [ -f "$LOG_FILE" ]; then
        echo -e "${CYAN}📝 Mostrando logs (Ctrl+C para salir)${NC}"
        tail -f "$LOG_FILE"
    else
        log_warning "No hay logs de hoy"
        ls -la "$BASE_DIR/logs/" 2>/dev/null || echo "Sin logs"
    fi
}

cmd_stop() {
    log_info "Deteniendo servidor..."
    pkill -f "python.*server.py" 2>/dev/null && log_success "Servidor detenido" || log_warning "No había servidor activo"
}

cmd_help() {
    print_banner
    echo -e "${CYAN}Uso:${NC} ./sonitranslate.sh <comando> [opciones]"
    echo ""
    echo -e "${GREEN}Comandos principales:${NC}"
    echo "  install          Instalar dependencias (primera vez)"
    echo "  start            Iniciar servidor Gradio"
    echo "  start-share      Iniciar con enlace público (ngrok)"
    echo "  stop             Detener servidor"
    echo ""
    echo -e "${GREEN}Gestión de cola:${NC}"
    echo "  status           Ver estado de la cola"
    echo "  add <archivo>    Añadir archivo a la cola"
    echo "      --lang es        Idioma destino (default: es)"
    echo "      --model base     Modelo:
