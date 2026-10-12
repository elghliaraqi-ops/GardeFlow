#!/usr/bin/env python3
"""Static regression guard for Practice's AI generation/data contracts.

The production database must still be checked using pg_constraint after a
migration is applied; this test prevents the exact October 12 source mismatch
from being silently reintroduced in the repository.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = (
    "generate-clinical-case-qcm",
    "generate-practice-daily-challenge",
    "generate-practice-progressive-case",
    "generate-random-clinical-case",
    "generate-visceral-radio",
    "preview-clinical-case-qcm",
    "practice-medical-images",
    "process-clinical-case-qcm-queue",
    "practice-context-glossary",
)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(condition: bool, explanation: str) -> None:
    if not condition:
        raise AssertionError(explanation)


for name in FUNCTIONS:
    left = read(f"supabase/functions/{name}/index.ts")
    right = read(f"source/supabase/functions/{name}/index.ts")
    require(left == right, f"Unsynchronized Edge source: {name}")

migration = read(
    "supabase/migrations/20261012095000_practice_daily_single_batch_ten_qcms.sql"
)
daily = read("supabase/functions/generate-practice-daily-challenge/index.ts")
progressive = read("supabase/functions/generate-practice-progressive-case/index.ts")
preview = read("supabase/functions/preview-clinical-case-qcm/index.ts")
clinical = read("supabase/functions/generate-clinical-case-qcm/index.ts")
random_case = read("supabase/functions/generate-random-clinical-case/index.ts")
visceral = read("supabase/functions/generate-visceral-radio/index.ts")
queue = read("supabase/functions/process-clinical-case-qcm-queue/index.ts")
glossary = read("supabase/functions/practice-context-glossary/index.ts")

# The DB must accept at least the maximum generated checkpoint cardinality.
require("jsonb_array_length(questions) between 1 and 10" in migration,
        "Daily checkpoint migration still limits batches to five")
require("drop constraint if exists practice_daily_generation_batches_questions_check" in migration,
        "Missing safe schema upgrade")

# One Groq call generates the ten daily questions. Saving the result may use two
# SQL rows, but the cache cannot block the successful authoritative write.
require("const missing=10-questions.length" in daily,
        "Daily QCM count is no longer ten")
require("newGroqBatch(prompt,dailyBatchSchema(missing)" in daily,
        "Daily QCM count and JSON output must share one contract")
require("questions.slice(0,5)" in daily and "questions.slice(5,10)" in daily,
        "Two five-question checkpoint rows not supported")
require("daily_checkpoint_write_failed_nonblocking" in daily,
        "A cache error may discard ten successfully generated questions")
require("for(let attempt=0;attempt<3" not in daily,
        "Automatic daily Groq retry loop returned")
require("if(questions.length!==10)" in daily,
        "Daily QCM count contract is not enforced")

# The clinical dossier is a separate generation; its ten progressive questions
# must come back in ONE structured answer, checked against stages 1..4.
require("decoded.qcms.length!==10" in progressive,
        "Progressive case QCM count is no longer ten")
require("const questions=[...first,...last]" in progressive,
        "Progressive clinical sequence no longer validated in both halves")
require("const batch=await newGroqBatch(prompt" in progressive,
        "Single-request progressive question generation missing")
require("for(let attempt=0;attempt<2" not in progressive,
        "A progressive Groq hot-retry loop returned")

# Preview has one request with the exact selected cardinality, and SQL supports
# 5, 10 or 20 questions via clinical_case_stage_qcm_preview.
require("![5,10,20].includes(qty)" in preview,
        "Clinical preview quantities changed")
require("decoded.qcms.length!==qty" in preview,
        "Preview output count and requested count diverged")
require("for(let part=0;part<qty/5" not in preview,
        "Preview has reverted to multiple Groq calls")

# Published clinical QCM and its SQL commit RPC use five-question lots.
require("minItems:5,maxItems:5" in clinical,
        "Published clinical QCM schema no longer matches five-question SQL commit")
require("clinical_case_commit_generated_qcms" in clinical,
        "Published clinical QCM persistence path changed")

# Viscéral × Radio batches of ten build to twenty, with a terminal five-count
# recovery and a quota-aware, no-hot-retry HTTP 429 response.
require("Math.min(10,20-existing.length)" in visceral,
        "Viscéral Radio no longer caps one Groq call to ten")
require("groq_rate_limited" in visceral and "retry_after_seconds" in visceral,
        "Quota handling disappeared from Viscéral Radio")

# Production-specific generators remain versioned; technical fallbacks must
# never specifically auto-retry on 429/quota rejection.
require("random_case_json_schema_recovery" in random_case,
        "Deployed random-case JSON-format fallback disappeared from source")
require("provider.status===400" in queue and "provider.status===413" in queue,
        "Published QCM worker's bounded technical recovery path changed")
require("statusCode === 429" in glossary,
        "Gemini glossary quota status is no longer recognized")

print("OK: nine Practice Edge source pairs and AI/SQL contracts checked")
