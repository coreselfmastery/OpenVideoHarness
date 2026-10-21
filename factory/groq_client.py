"""Groq API client — text generation, vision QA, model auto-detection.

Pure httpx (no SDK): OpenAI-compatible chat completions at
https://api.groq.com/openai/v1. The model is a config knob:

    GROQ_TEXT_MODEL   = "auto"  -> resolved from TEXT_MODEL_PREFERENCE
    GROQ_VISION_MODEL = "auto"  -> resolved from VISION_MODEL_PREFERENCE

"we can change it easily and add new" — add a model id to the front of a
preference list and it is used the moment it appears in /models.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import time
from pathlib import Path
from typing import Any, Optional

import httpx

log = logging.getLogger("factory.groq")

DEFAULT_BASE_URL = "https://api.groq.com/openai/v1"
# Preference order, resolved against live /models at boot. New Groq models get
# added here (front = preferred). Anything missing on the account is skipped.
TEXT_MODEL_PREFERENCE = [
    "openai/gpt-oss-120b",
    "llama-3.3-70b-versatile",
    "openai/gpt-oss-20b",
    "qwen/qwen3-32b",
    "llama-3.1-8b-instant",
]
VISION_MODEL_PREFERENCE = [
    "meta-llama/llama-4-scout-17b-16e-instruct",
    "meta-llama/llama-4-maverick-17b-128e-instruct",
]


class GroqError(RuntimeError):
    pass


class GroqClient:
    """Chat + vision with retries, timeouts, and JSON-mode helpers."""

    def __init__(self, api_key: str, base_url: str = DEFAULT_BASE_URL, timeout: float = 90.0):
        self.api_key = (api_key or "").strip()
        if not self.api_key:
            raise GroqError("GROQ_API_KEY is empty — pass one or set the env var")
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self._models: Optional[list[str]] = None
        self.text_model: Optional[str] = None
        self.vision_model: Optional[str] = None

    # ── low level ─────────────────────────────────────────────────────────
    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"}

    def _post(self, path: str, payload: dict, retries: int = 3, timeout: Optional[float] = None) -> dict:
        url = f"{self.base_url}{path}"
        last: Optional[Exception] = None
        for attempt in range(retries):
            try:
                r = httpx.post(url, headers=self._headers(), json=payload,
                               timeout=timeout or self.timeout)
                if r.status_code == 200:
                    return r.json()
                if r.status_code in (429, 500, 502, 503, 504):
                    wait = min(2 ** attempt * 1.5, 12.0)
                    log.warning("groq %s -> %s, retry %s/%s in %.1fs", path, r.status_code, attempt + 1, retries, wait)
                    time.sleep(wait)
                    last = GroqError(f"HTTP {r.status_code}: {r.text[:300]}")
                    continue
                raise GroqError(f"HTTP {r.status_code}: {r.text[:400]}")
            except httpx.HTTPError as e:
                last = e
                wait = min(2 ** attempt * 1.5, 12.0)
                log.warning("groq %s network error (%s), retry %s/%s in %.1fs", path, e.__class__.__name__, attempt + 1, retries, wait)
                time.sleep(wait)
        raise GroqError(f"groq {path} failed after {retries} attempts: {last}")

    # ── models ────────────────────────────────────────────────────────────
    def list_models(self, refresh: bool = False) -> list[str]:
        if self._models is None or refresh:
            r = httpx.get(f"{self.base_url}/models", headers=self._headers(), timeout=30)
            if r.status_code != 200:
                raise GroqError(f"list models -> HTTP {r.status_code}: {r.text[:300]}")
            self._models = sorted(m["id"] for m in r.json().get("data", []))
        return self._models

    def resolve_models(self, text_pref: list[str] | None = None, vision_pref: list[str] | None = None) -> dict:
        """Pick text/vision models from the live model list (first hit wins)."""
        models = set(self.list_models(refresh=True))
        tp = text_pref or TEXT_MODEL_PREFERENCE
        vp = vision_pref or VISION_MODEL_PREFERENCE
        self.text_model = next((m for m in tp if m in models), None)
        self.vision_model = next((m for m in vp if m in models), None)
        return {"text": self.text_model, "vision": self.vision_model, "available": len(models)}

    # ── chat ──────────────────────────────────────────────────────────────
    def chat(self, messages: list[dict], model: Optional[str] = None, *,
             json_mode: bool = False, temperature: float = 0.7, max_tokens: int = 2048,
             retries: int = 3) -> str:
        payload: dict[str, Any] = {
            "model": model or self.text_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}
        out = self._post("/chat/completions", payload, retries=retries)
        try:
            return out["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError) as e:
            raise GroqError(f"unexpected chat shape: {e}: {json.dumps(out)[:300]}") from e

    def chat_json(self, messages: list[dict], model: Optional[str] = None, **kw) -> dict:
        """Chat that must answer JSON; strips code fences, parses, re-asks once on junk."""
        msgs = list(messages)
        if not any("json" in (m.get("content") or "").lower() for m in msgs if m.get("role") == "system"):
            msgs.append({"role": "system", "content": "Answer with a single valid JSON object. No markdown, no prose."})
        for attempt in range(2):
            raw = self.chat(msgs, model=model, json_mode=True, **kw)
            txt = raw.strip()
            if txt.startswith("```"):
                txt = txt.strip("`")
                if txt.lower().startswith("json"):
                    txt = txt[4:]
                txt = txt.strip()
            try:
                parsed = json.loads(txt)
                return parsed if isinstance(parsed, dict) else {"value": parsed}
            except json.JSONDecodeError:
                if attempt == 0:
                    msgs.append({"role": "user", "content": "That was not valid JSON. Reply again with ONLY the JSON object."})
                    continue
                raise GroqError(f"model returned unparseable JSON: {txt[:200]}")
        raise GroqError("unreachable")

    # ── vision ────────────────────────────────────────────────────────────
    def vision(self, prompt: str, image_path: str | Path, model: Optional[str] = None,
               *, json_mode: bool = True, max_tokens: int = 1600) -> dict | str:
        p = Path(image_path)
        if not p.is_file():
            raise GroqError(f"vision: no image at {p}")
        b64 = base64.b64encode(p.read_bytes()).decode()
        mime = "image/png" if p.suffix.lower() == ".png" else "image/jpeg"
        msgs = [{
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}},
            ],
        }]
        if json_mode:
            return self.chat_json(msgs, model=model or self.vision_model, temperature=0.2, max_tokens=max_tokens)
        return self.chat(msgs, model=model or self.vision_model, temperature=0.2, max_tokens=max_tokens)

    # ── health ────────────────────────────────────────────────────────────
    def ping(self) -> dict:
        """One tiny completion to prove the key + reachability end-to-end."""
        t0 = time.time()
        out = self.chat([{"role": "user", "content": "Reply with exactly: OK"}],
                        temperature=0.0, max_tokens=4, retries=1)
        return {"ok": True, "latency_s": round(time.time() - t0, 2), "reply": out.strip()[:20]}
