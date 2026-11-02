"""Internal, authenticated PDF/PPTX compiler. Never fetches URLs or executes commands."""
import base64
import hashlib
import hmac
import io
import json
import os
import re
import stat
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from xml.sax.saxutils import escape

MAX_REQUEST_BYTES = 1024 * 1024
MAX_FILE_BYTES = 5 * 1024 * 1024
MAX_STORAGE_BYTES = 100 * 1024 * 1024
MAX_SLIDES = 12
MAX_BULLETS = 8
MAX_BULLET_CHARS = 240
IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}\Z")
ARTIFACT_FILENAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}-(?P<digest>[a-f0-9]{16})\.(?P<extension>pdf|pptx)\Z")
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\ud800-\udfff\ufffe\uffff]")
COMPILE_LOCK = threading.Lock()


class CompileError(ValueError):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


class BoundedBuffer(io.BytesIO):
    def write(self, data):
        if self.tell() + len(data) > MAX_FILE_BYTES:
            raise CompileError("compiled artifact exceeds byte limit", 413)
        return super().write(data)


def text(value, field, limit, required=False):
    if not isinstance(value, str) or len(value) > limit or CONTROL.search(value):
        raise CompileError(f"invalid {field}")
    if required and not value.strip():
        raise CompileError(f"{field} is required")
    return value.strip()


def validate(payload):
    if not isinstance(payload, dict):
        raise CompileError("request must be an object")
    allowed = {"artifact_id", "channel", "title", "body", "slides", "banner"}
    if set(payload) - allowed:
        raise CompileError("unknown request field")
    identifier = payload.get("artifact_id")
    if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier):
        raise CompileError("invalid artifact_id")
    channel = payload.get("channel")
    if channel not in ("report", "pptx"):
        raise CompileError("channel must be report or pptx")
    result = {"artifact_id": identifier, "channel": channel,
              "title": text(payload.get("title"), "title", 200, True),
              "body": text(payload.get("body", ""), "body", 120000),
              "banner": text(payload.get("banner", "DRAFT — HUMAN REVIEW REQUIRED"), "banner", 160, True)}
    if any(character in result["banner"] for character in "\r\n\t"):
        raise CompileError("banner must be a single line")
    if channel == "report":
        if not result["body"]:
            raise CompileError("body is required for report")
        if payload.get("slides"):
            raise CompileError("slides are only accepted for pptx")
        return result
    slides = payload.get("slides")
    if slides is None:
        slides = [{"title": result["title"], "body": result["body"]}]
    if not isinstance(slides, list) or not 1 <= len(slides) <= MAX_SLIDES:
        raise CompileError("slides must contain 1 to 12 items")
    result["slides"] = []
    for slide in slides:
        if not isinstance(slide, dict) or set(slide) - {"title", "body", "bullets", "speaker_notes"}:
            raise CompileError("invalid slide")
        bullets = slide.get("bullets", [])
        if not isinstance(bullets, list) or len(bullets) > MAX_BULLETS:
            raise CompileError("at most 8 bullets per slide")
        result["slides"].append({
            "title": text(slide.get("title"), "slide title", 160, True),
            "body": text(slide.get("body", ""), "slide body", 2000),
            "bullets": [text(b, "bullet", MAX_BULLET_CHARS, True) for b in bullets],
            "speaker_notes": text(slide.get("speaker_notes", ""), "speaker_notes", 12000),
        })
    return result


def compile_pdf(payload):
    import reportlab
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_LEFT
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.lib.utils import simpleSplit
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

    # ReportLab bundles Vera: no system font installs, URLs, or shell commands.
    if "ArtifactVera" not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont("ArtifactVera", str(Path(reportlab.__file__).parent / "fonts" / "Vera.ttf")))
    output = BoundedBuffer()
    doc = SimpleDocTemplate(output, pagesize=(8.5 * inch, 11 * inch),
                            rightMargin=54, leftMargin=54, topMargin=54, bottomMargin=54,
                            title=payload["title"], author="Enterprise communications")
    title_style = ParagraphStyle("Title", fontName="ArtifactVera", fontSize=20,
                                 leading=26, textColor=colors.HexColor("#17324d"), spaceAfter=18)
    body_style = ParagraphStyle("Body", fontName="ArtifactVera", fontSize=10.5,
                                leading=16, alignment=TA_LEFT, splitLongWords=True)
    story = [Paragraph(escape(payload["title"]), title_style)]
    # Escape every character with markup meaning: source text never becomes links or XML.
    for paragraph in re.split(r"\n\s*\n", payload["body"]):
        story.append(Paragraph(escape(paragraph).replace("\n", "<br/>"), body_style))
        story.append(Spacer(1, 10))
    def mark_page(canvas, _doc):
        canvas.saveState()
        canvas.setFont("ArtifactVera", 8)
        canvas.setFillColor(colors.HexColor("#9A3412"))
        lines = simpleSplit(payload["banner"], "ArtifactVera", 8, 504)
        for index, line in enumerate(lines):
            canvas.drawString(54, 24 + (len(lines) - index - 1) * 10, line)
        canvas.restoreState()

    doc.build(story, onFirstPage=mark_page, onLaterPages=mark_page)
    return output.getvalue(), "pdf", "application/pdf"


def compile_pptx(payload):
    from pptx import Presentation
    from pptx.dml.color import RGBColor
    from pptx.util import Inches, Pt

    deck = Presentation()
    deck.slide_width, deck.slide_height = Inches(13.333), Inches(7.5)
    deck.core_properties.title = payload["title"]
    deck.core_properties.author = "Enterprise communications"
    for number, data in enumerate(payload["slides"], 1):
        slide = deck.slides.add_slide(deck.slide_layouts[6])
        title = slide.shapes.add_textbox(Inches(.65), Inches(.45), Inches(12), Inches(1.2)).text_frame
        title.word_wrap = True
        title.paragraphs[0].text = data["title"]
        title.paragraphs[0].font.size = Pt(30)
        title.paragraphs[0].font.bold = True
        title.paragraphs[0].font.color.rgb = RGBColor.from_string("17324D")
        frame = slide.shapes.add_textbox(Inches(.7), Inches(1.85), Inches(11.9), Inches(4.8)).text_frame
        frame.word_wrap = True
        lines = ([data["body"]] if data["body"] else []) + ["• " + b for b in data["bullets"]]
        for index, line in enumerate(lines):
            p = frame.paragraphs[0] if index == 0 else frame.add_paragraph()
            p.text, p.font.size, p.space_after = line, Pt(20), Pt(12)
        footer = slide.shapes.add_textbox(Inches(12), Inches(7), Inches(.6), Inches(.25)).text_frame
        footer.paragraphs[0].text = str(number)
        footer.paragraphs[0].font.size = Pt(10)
        banner = slide.shapes.add_textbox(Inches(.7), Inches(6.83), Inches(10.8), Inches(.6)).text_frame
        banner.word_wrap = True
        banner.paragraphs[0].text = payload["banner"]
        banner.paragraphs[0].font.size = Pt(10)
        banner.paragraphs[0].font.color.rgb = RGBColor.from_string("9A3412")
        if data["speaker_notes"]:
            slide.notes_slide.notes_text_frame.text = data["speaker_notes"]
    output = BoundedBuffer()
    deck.save(output)
    return output.getvalue(), "pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation"


def compile_artifact(payload, data_dir):
    payload = validate(payload)
    # Single bounded worker also avoids font-registration and persistence races.
    if not COMPILE_LOCK.acquire(blocking=False):
        raise CompileError("compiler busy; retry later", 503)
    try:
        content, extension, mime = compile_pdf(payload) if payload["channel"] == "report" else compile_pptx(payload)
        if len(content) > MAX_FILE_BYTES:
            raise CompileError("compiled artifact exceeds byte limit", 413)
        digest = hashlib.sha256(content).hexdigest()
        filename = f"{payload['artifact_id']}-{digest[:16]}.{extension}"
        directory = Path(data_dir)
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = directory / filename
        used = sum(p.stat().st_size for p in directory.iterdir() if p.is_file())
        if used + len(content) > MAX_STORAGE_BYTES:
            raise CompileError("artifact storage quota reached", 507)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(path, flags, 0o600)
        except FileExistsError:
            if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise CompileError("artifact filename conflict", 409)
        else:
            try:
                with os.fdopen(descriptor, "wb") as stream:
                    stream.write(content)
                    stream.flush()
                    os.fsync(stream.fileno())
            except BaseException:
                path.unlink(missing_ok=True)
                raise
        return {"filename": filename, "mime_type": mime,
                "base64": base64.b64encode(content).decode("ascii"),
                "sha256": digest, "size_bytes": len(content),
                "visual_review_required": True}
    finally:
        COMPILE_LOCK.release()


def fetch_artifact(filename, data_dir):
    match = ARTIFACT_FILENAME.fullmatch(filename)
    if not match:
        raise CompileError("invalid artifact filename")
    if not COMPILE_LOCK.acquire(blocking=False):
        raise CompileError("compiler busy; retry later", 503)
    try:
        # dir_fd prevents path re-interpretation; O_NOFOLLOW rejects final symlinks
        # atomically. O_NONBLOCK avoids waiting on a malicious FIFO before fstat.
        try:
            directory = os.open(data_dir, os.O_RDONLY | os.O_DIRECTORY)
            try:
                descriptor = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                                     dir_fd=directory)
            finally:
                os.close(directory)
        except OSError:
            raise CompileError("artifact not found", 404)
        with os.fdopen(descriptor, "rb") as stream:
            details = os.fstat(stream.fileno())
            if not stat.S_ISREG(details.st_mode):
                raise CompileError("artifact not found", 404)
            if not 0 < details.st_size <= MAX_FILE_BYTES:
                raise CompileError("artifact exceeds byte limit", 413)
            content = stream.read(MAX_FILE_BYTES + 1)
        if len(content) > MAX_FILE_BYTES:
            raise CompileError("artifact exceeds byte limit", 413)
        digest = hashlib.sha256(content).hexdigest()
        if not hmac.compare_digest(digest[:16], match["digest"]):
            raise CompileError("artifact integrity check failed", 409)
        mime = ("application/pdf" if match["extension"] == "pdf" else
                "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        return {"filename": filename, "mime_type": mime,
                "base64": base64.b64encode(content).decode("ascii"),
                "sha256": digest, "size_bytes": len(content),
                "visual_review_required": True}
    finally:
        COMPILE_LOCK.release()


class ArtifactServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8

    def __init__(self, address, token, data_dir):
        if not isinstance(token, str) or len(token) < 24:
            raise ValueError("ARTIFACT_TOKEN must contain at least 24 characters")
        self.artifact_token = token.encode("utf-8")
        self.data_dir = data_dir
        super().__init__(address, ArtifactHandler)


class ArtifactHandler(BaseHTTPRequestHandler):
    server_version = "ArtifactCompiler"
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, _format, *args):
        pass  # Never log payloads, authentication headers, or returned base64.

    def respond(self, status, payload):
        body = json.dumps(payload, allow_nan=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self.respond(200, {"status": "ok", "visual_review_required": True})
        if not self.authenticated():
            return self.respond(401, {"error": "unauthorized"})
        if not self.path.startswith("/artifacts/"):
            return self.respond(404, {"error": "not found"})
        try:
            self.respond(200, fetch_artifact(self.path[len("/artifacts/"):], self.server.data_dir))
        except CompileError as error:
            self.respond(error.status, {"error": str(error)})
        except Exception:
            self.respond(500, {"error": "artifact fetch failed"})

    def authenticated(self):
        values = self.headers.get_all("X-Artifact-Token", [])
        token = values[0].encode("utf-8") if len(values) == 1 else b""
        return hmac.compare_digest(token, self.server.artifact_token)

    def do_POST(self):
        if not self.authenticated():
            return self.respond(401, {"error": "unauthorized"})
        if self.path != "/compile":
            return self.respond(404, {"error": "not found"})
        try:
            if self.headers.get("Transfer-Encoding"):
                raise CompileError("transfer encoding is unsupported", 400)
            if self.headers.get_content_type() != "application/json":
                raise CompileError("Content-Type must be application/json", 415)
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1 or not lengths[0].isdigit():
                raise CompileError("one valid Content-Length is required", 411)
            length = int(lengths[0])
            if not 0 < length <= MAX_REQUEST_BYTES:
                raise CompileError("request exceeds byte limit", 413)
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise CompileError("incomplete request")
            payload = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))
            result = compile_artifact(payload, self.server.data_dir)
            self.respond(200, result)
        except CompileError as error:
            self.respond(error.status, {"error": str(error)})
        except (ValueError, UnicodeError):
            self.respond(400, {"error": "invalid JSON"})
        except Exception:
            self.respond(500, {"error": "artifact compilation failed"})


if __name__ == "__main__":
    # Bind to the container network; compose must not publish this port on the host.
    ArtifactServer(("0.0.0.0", 8000), os.environ.get("ARTIFACT_TOKEN", ""),
                   os.environ.get("ARTIFACT_DATA_DIR", "/data")).serve_forever()
