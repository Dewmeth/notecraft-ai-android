"""Optional NoteCraft AI server (not needed for local scanning / exporting).

Security: DEMO ONLY. Protect behind authentication and rate limits before exposing
publicly. Never ship a provider API key in the Android client. An HTTPS gateway
or reverse proxy is required because the Flutter app refuses plain HTTP.
"""
from __future__ import annotations
import base64
import json
import os
import re
from typing import List

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from openai import OpenAI

app = FastAPI(title="NoteCraft AI explanations")
client = OpenAI()  # Reads OPENAI_API_KEY from server-side environment only.


class NoteRequest(BaseModel):
    ocr_text: str = Field(default="", max_length=12000)
    images_base64: List[str] = Field(default_factory=list, max_length=3)


@app.get('/health')
def health():
    return {'ok': True, 'service': 'NoteCraft AI'}


@app.post('/explain')
def explain(req: NoteRequest):
    """Explain apparent subject based on OCR and actual page images, not guessed facts."""
    content = [{
        'type': 'input_text',
        'text': (
            'Analyze the photographed handwritten study notes. Identify the subject, '
            'summarize the main ideas and diagrams, and offer up to 5 useful, concrete '
            'explanations / corrections. Explain uncertainty; do not invent words or '
            'unreadable symbols. Output ONLY a JSON object with keys topic (string), '
            'summary (string), explanations (array of strings). OCR text follows:\n' + req.ocr_text
        ),
    }]
    for encoded in req.images_base64:
        # Validate count/size before forwarding images to the model.
        if len(encoded) > 2_800_000 or not re.fullmatch(r'[A-Za-z0-9+/=]+', encoded):
            raise HTTPException(400, 'Invalid image encoding/size')
        try:
            decoded = base64.b64decode(encoded, validate=True)
            if len(decoded) > 2_100_000:
                raise ValueError('Too large')
        except Exception as exc:
            raise HTTPException(400, 'Corrupt image payload') from exc
        content.append({'type': 'input_image',
                        'image_url': 'data:image/jpeg;base64,' + encoded})
    try:
        result = client.responses.create(
            model=os.getenv('OPENAI_MODEL', 'gpt-4.1-mini'),
            input=[{'role': 'user', 'content': content}],
            max_output_tokens=750,
        )
        raw = result.output_text.strip()
        raw = re.sub(r'^```(?:json)?\s*|\s*```$', '', raw).strip()
        parsed = json.loads(raw)
        if not isinstance(parsed.get('explanations'), list):
            raise ValueError('AI output missing explanations')
        return {
            'topic': str(parsed.get('topic', 'Study notes'))[:120],
            'summary': str(parsed.get('summary', ''))[:1800],
            'explanations': [str(x)[:750] for x in parsed['explanations'][:5]],
        }
    except Exception as exc:
        # Never forward keys, server environment data or raw exception details.
        raise HTTPException(502, 'AI provider failed or returned malformed output') from exc
