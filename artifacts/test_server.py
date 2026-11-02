import base64
import hashlib
import http.client
import io
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile

import server


class ArtifactSmokeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.storage = tempfile.TemporaryDirectory()
        cls.token = "test-token-32-characters-long-secret"
        cls.http = server.ArtifactServer(("127.0.0.1", 0), cls.token, cls.storage.name)
        cls.worker = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.worker.join(timeout=3)
        cls.storage.cleanup()

    def request(self, payload=None, token=None, path="/compile", method="POST", raw=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.http.server_port, timeout=10)
        body = raw if raw is not None else json.dumps(payload).encode() if payload is not None else None
        headers = {"Content-Type": "application/json"}
        if token is not None:
            headers["X-Artifact-Token"] = token
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        status, result = response.status, json.loads(response.read())
        connection.close()
        return status, result

    def payload(self, channel="report"):
        return {"artifact_id": "asset_42", "channel": channel,
                "title": "Quarterly results", "body": "Latency improved 42% [chunk_1].\n\nEscaped <b>text</b> & symbols."}

    def assert_artifact(self, result, signature):
        data = base64.b64decode(result["base64"], validate=True)
        self.assertTrue(data.startswith(signature))
        self.assertEqual(result["size_bytes"], len(data))
        self.assertEqual(result["sha256"], hashlib.sha256(data).hexdigest())
        self.assertTrue(result["visual_review_required"])
        self.assertEqual((Path(self.storage.name) / result["filename"]).read_bytes(), data)
        self.assertEqual(set(result), {"filename", "mime_type", "base64", "sha256", "size_bytes", "visual_review_required"})
        return data

    def test_health_and_authentication(self):
        self.assertEqual(self.request(path="/health", method="GET"), (200, {"status": "ok", "visual_review_required": True}))
        self.assertEqual(self.request(self.payload())[0], 401)
        self.assertEqual(self.request(self.payload(), token="incorrect")[0], 401)
        self.assertEqual(self.request(path="/data/asset_42.pdf", method="GET")[0], 401)
        self.assertEqual(self.request(path="/data/asset_42.pdf", method="GET", token=self.token)[0], 404)

    def test_fetch_requires_auth_and_returns_identical_envelope(self):
        for channel in ("report", "pptx"):
            status, created = self.request(self.payload(channel), self.token)
            self.assertEqual(status, 200)
            path = "/artifacts/" + created["filename"]
            self.assertEqual(self.request(path=path, method="GET")[0], 401)
            self.assertEqual(self.request(path=path, method="GET", token="wrong")[0], 401)
            self.assertEqual(self.request(path=path, method="GET", token=self.token), (200, created))

    def test_fetch_rejects_traversal_symlinks_and_bad_content(self):
        for filename in ("../secret", "%2e%2e%2fsecret", "/tmp/a.pdf", "a\\b.pdf", "a.pdf", "a-1234.pdf",
                         "a-0123456789abcdef.pdf?download=1", "a-0123456789abcdef.pdf/extra"):
            self.assertEqual(self.request(path="/artifacts/" + filename, method="GET", token=self.token)[0], 400)
        name = "missing-0123456789abcdef.pdf"
        self.assertEqual(self.request(path="/artifacts/" + name, method="GET", token=self.token)[0], 404)
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "private.pdf"
            target.write_bytes(b"private")
            link = Path(self.storage.name) / "link-0123456789abcdef.pdf"
            link.symlink_to(target)
            try:
                self.assertEqual(self.request(path="/artifacts/" + link.name, method="GET", token=self.token)[0], 404)
            finally:
                link.unlink()
        corrupt = Path(self.storage.name) / "corrupt-0123456789abcdef.pdf"
        corrupt.write_bytes(b"wrong checksum")
        try:
            self.assertEqual(self.request(path="/artifacts/" + corrupt.name, method="GET", token=self.token)[0], 409)
            with patch.object(server, "MAX_FILE_BYTES", 1):
                self.assertEqual(self.request(path="/artifacts/" + corrupt.name, method="GET", token=self.token)[0], 413)
        finally:
            corrupt.unlink()

    def test_report_pdf_and_escaped_markup(self):
        status, result = self.request(self.payload(), self.token)
        self.assertEqual(status, 200, result)
        self.assertEqual(result["mime_type"], "application/pdf")
        data = self.assert_artifact(result, b"%PDF-")
        self.assertNotIn(b"/Subtype /Link", data)

    def test_banner_validation_and_presence_on_every_page_and_slide(self):
        from pypdf import PdfReader
        from pptx import Presentation
        payload = self.payload()
        for invalid in ("", "x" * 161, 42, "invalid\nsecond line"):
            payload["banner"] = invalid
            self.assertEqual(self.request(payload, self.token)[0], 400)
        payload.pop("banner")
        status, created = self.request(payload, self.token)
        self.assertEqual(status, 200)
        reader = PdfReader(io.BytesIO(base64.b64decode(created["base64"])))
        self.assertIn("DRAFT — HUMAN REVIEW REQUIRED", reader.pages[0].extract_text())
        payload["banner"] = "SYNTHETIC FIXTURE — NOT APPROVED FOR EXTERNAL USE"
        payload["body"] = "\n\n".join(["A paragraph with verified example content. " * 5] * 60)
        status, created = self.request(payload, self.token)
        self.assertEqual(status, 200)
        reader = PdfReader(io.BytesIO(base64.b64decode(created["base64"])))
        self.assertGreater(len(reader.pages), 1)
        for page in reader.pages:
            self.assertIn(payload["banner"], page.extract_text())
        payload = self.payload("pptx")
        payload["banner"] = "UNVERIFIED DRAFT — DO NOT SEND"
        payload["slides"] = [{"title": "Slide"}] * 3
        status, created = self.request(payload, self.token)
        self.assertEqual(status, 200)
        for slide in Presentation(io.BytesIO(base64.b64decode(created["base64"])) ).slides:
            self.assertIn(payload["banner"], [shape.text for shape in slide.shapes if shape.has_text_frame])

    def test_pptx_preserves_slide_text_and_notes(self):
        from pptx import Presentation
        payload = self.payload("pptx")
        payload["slides"] = [{"title": "Results", "bullets": ["Latency improved 42%"], "speaker_notes": "Source: chunk_1"}]
        status, result = self.request(payload, self.token)
        self.assertEqual(status, 200, result)
        data = self.assert_artifact(result, b"PK")
        with ZipFile(io.BytesIO(data)) as archive:
            self.assertIn("ppt/slides/slide1.xml", archive.namelist())
        deck = Presentation(io.BytesIO(data))
        self.assertEqual(len(deck.slides), 1)
        self.assertIn("Latency improved 42%", " ".join(s.text for s in deck.slides[0].shapes if s.has_text_frame))
        self.assertIn("Source: chunk_1", deck.slides[0].notes_slide.notes_text_frame.text)

    def test_identifier_rejects_path_traversal(self):
        for value in ("../escape", "/tmp/file", "a/b", "a\\b", "a.pdf", "", "a" * 65):
            payload = self.payload()
            payload["artifact_id"] = value
            self.assertEqual(self.request(payload, self.token)[0], 400, value)

    def test_slide_and_bullet_limits(self):
        payload = self.payload("pptx")
        payload["slides"] = [{"title": "slide"}] * 13
        self.assertEqual(self.request(payload, self.token)[0], 400)
        payload["slides"] = [{"title": "slide", "bullets": ["a"] * 9}]
        self.assertEqual(self.request(payload, self.token)[0], 400)
        payload["slides"] = [{"title": "slide", "bullets": ["a" * 241]}]
        self.assertEqual(self.request(payload, self.token)[0], 400)
        payload["slides"] = [{"title": "slide"}] * 12
        self.assertEqual(self.request(payload, self.token)[0], 200)

    def test_request_and_artifact_byte_limits(self):
        with patch.object(server, "MAX_REQUEST_BYTES", 20):
            self.assertEqual(self.request(self.payload(), self.token)[0], 413)
        with patch.object(server, "MAX_FILE_BYTES", 100):
            self.assertEqual(self.request(self.payload(), self.token)[0], 413)

    def test_invalid_input_and_quota(self):
        self.assertEqual(self.request(token=self.token, raw=b"{broken")[0], 400)
        payload = self.payload()
        payload["body"] = ""
        self.assertEqual(self.request(payload, self.token)[0], 400)
        payload = self.payload()
        payload["url"] = "https://example.com/"
        self.assertEqual(self.request(payload, self.token)[0], 400)
        with patch.object(server, "MAX_STORAGE_BYTES", 1):
            self.assertEqual(self.request(self.payload(), self.token)[0], 507)


if __name__ == "__main__":
    unittest.main()
