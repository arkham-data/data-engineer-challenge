from datetime import datetime, timedelta, timezone
import hashlib
from typing import Any, Dict, List, Optional
from fastapi import FastAPI, HTTPException, Query, Response

app = FastAPI(title="Arkham Partner Event Gateway", version="1.4.2")

TOTAL_EVENTS = 60_000

GTIN_CATALOG = [
    "3017620422003",
    "5449000000996",
    "7622210449283",
    "049000028904",
    "8076809513753",
    "3228857000166",
    "7613034626844",
    "3046920022651",
    "5000112637922",
    "3168930010265",
    "8715700407760",
    "028400090896",
    "4008400404127",
    "5410041001204",
    "3033710065967",
    "7622300336738",
    "3274080005003",
    "8000500037560",
]

TENANTS = [
    "TENANT_DEMO_000",
    "TENANT_CPG_001",
    "TENANT_CPG_002",
    "TENANT_RTL_003",
    "TENANT_RTL_004",
]

EPOCH_START = datetime(2026, 10, 1, 0, 0, 0, tzinfo=timezone.utc)


def _sig(seed_val: int) -> str:
    return hashlib.sha256(f"arkham-pos-{seed_val}".encode("utf-8")).hexdigest()


def _serialize_event(seq_id: int, verbose_trace: bool = False) -> Dict[str, Any]:
    if seq_id <= 25_000:
        ingested_dt = EPOCH_START + timedelta(seconds=(seq_id * 17) % 432_000)
        occurred_dt = ingested_dt - timedelta(seconds=(seq_id % 300))
        batch_window = "2026-10-W1"
    elif seq_id <= 45_000:
        ingested_dt = EPOCH_START + timedelta(days=5, seconds=(seq_id * 19) % 432_000)
        if seq_id % 8 == 0:
            occurred_dt = EPOCH_START + timedelta(days=1, seconds=(seq_id * 13) % 259_200)
        else:
            occurred_dt = ingested_dt - timedelta(seconds=(seq_id % 600))
        batch_window = "2026-10-W2"
    else:
        ingested_dt = EPOCH_START + timedelta(days=10, seconds=(seq_id * 23) % 432_000)
        if seq_id % 11 == 0:
            occurred_dt = EPOCH_START + timedelta(days=6, seconds=(seq_id * 7) % 172_800)
        else:
            occurred_dt = ingested_dt - timedelta(seconds=(seq_id % 450))
        batch_window = "2026-10-W3"

    if seq_id % 10 < 5:
        tenant_id = "TENANT_DEMO_000"
    else:
        tenant_id = TENANTS[1 + (seq_id % 4)]

    if seq_id > 25_000 and seq_id % 29 == 0:
        origin_seq = seq_id - 14_500
        event_id = f"EVT-{origin_seq:07d}"
        revision_num = 2
    else:
        event_id = f"EVT-{seq_id:07d}"
        revision_num = 1

    prod_idx = (seq_id % 200) + 1
    store_idx = (seq_id % 120) + 1
    raw_gtin = GTIN_CATALOG[seq_id % len(GTIN_CATALOG)]

    if seq_id % 9 == 0:
        gtin_str = f"00{raw_gtin}"
    elif seq_id % 14 == 0:
        gtin_str = f" {raw_gtin} "
    else:
        gtin_str = raw_gtin

    if tenant_id == "TENANT_CPG_002" and seq_id % 5 == 0:
        tz_offset = timezone(timedelta(hours=-6))
        occurred_str = occurred_dt.astimezone(tz_offset).strftime("%Y/%m/%d %H:%M:%S-0600")
    else:
        occurred_str = occurred_dt.isoformat().replace("+00:00", "Z")

    ingested_str = ingested_dt.isoformat().replace("+00:00", "Z")

    if seq_id > 7_000 and tenant_id in ("TENANT_RTL_003", "TENANT_RTL_004"):
        discount_val: Any = f"{(seq_id % 25)}%"
        promo_mechanics: Any = {
            "campaign_id": f"PRM-{(seq_id % 40) + 100}",
            "mechanic_type": "MULTI_BUY_BOGO" if seq_id % 2 == 0 else "LOYALTY_TIER",
            "co_funded_cpg_ratio": round(((seq_id % 7) + 1) * 0.1, 2),
        }
    else:
        discount_val = round(((seq_id % 20) * 0.01), 2)
        promo_mechanics = None

    unit_price_cents = 299 + ((seq_id * 11) % 1400)
    if seq_id % 97 == 0:
        unit_price_cents = -1 * unit_price_cents

    record: Dict[str, Any] = {
        "event_id": event_id,
        "sequence_cursor": seq_id,
        "revision": revision_num,
        "tenant_id": tenant_id,
        "store_id": "LOC_UNASSIGNED_000" if tenant_id == "TENANT_DEMO_000" else f"STORE_{store_idx:04d}",
        "product_id": f"PROD_{prod_idx:04d}",
        "gtin_barcode": gtin_str,
        "event_type": "POS_CHECKOUT" if seq_id % 4 != 0 else "SHELF_AUDIT_SCAN",
        "units_sold": 1 + (seq_id % 12),
        "unit_price_cents": unit_price_cents,
        "discount_rate": discount_val,
        "currency": "MXN" if tenant_id == "TENANT_CPG_002" else ("EUR" if tenant_id == "TENANT_RTL_003" else "USD"),
        "record_state": "CANCELLED_VOID" if seq_id % 31 == 0 else "ACTIVE",
        "is_deleted": False,
        "event_timestamp": occurred_str,
        "ingested_at": ingested_str,
        "batch_window": batch_window,
    }

    if promo_mechanics is not None:
        record["promo_mechanics"] = promo_mechanics

    if verbose_trace or tenant_id == "TENANT_DEMO_000":
        factor = 18 if verbose_trace else 3
        record["lowcode_execution_trace"] = {
            "digest": _sig(seq_id) * factor,
            "node_hop_path": [
                f"PLANT_{(seq_id % 3) + 1:02d}",
                f"DC_HUB_{(seq_id % 4) + 1:02d}",
                f"STORE_{store_idx:04d}",
            ],
        }

    return record


@app.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "healthy"}


@app.get("/v1/events")
def list_events(
    response: Response,
    page: int = Query(1),
    page_size: int = Query(250),
    window: Optional[str] = Query(None),
    since_cursor: Optional[int] = Query(None),
) -> Dict[str, Any]:
    if page_size > 2000:
        raise HTTPException(status_code=429, detail="Payload limit exceeded")

    effective_page = max(1, page)
    verbose_trace = page_size > 500

    if window == "2026-10-W1":
        start_seq, end_seq = 1, 25_000
    elif window == "2026-10-W2":
        start_seq, end_seq = 25_001, 45_000
    elif window == "2026-10-W3":
        start_seq, end_seq = 45_001, 60_000
    elif window is not None:
        raise HTTPException(status_code=400, detail="Invalid window")
    else:
        start_seq, end_seq = 1, TOTAL_EVENTS

    if since_cursor is not None:
        start_seq = max(start_seq, since_cursor + 1)

    if start_seq > end_seq:
        return {
            "page": page,
            "page_size": page_size,
            "count": 0,
            "next_cursor": since_cursor,
            "has_more": False,
            "data": [],
        }

    offset = (effective_page - 1) * page_size
    slice_start = start_seq + offset
    slice_end = min(end_seq, slice_start + page_size - 1)
    results: List[Dict[str, Any]] = []
    last_seq = since_cursor

    if slice_start <= end_seq:
        for seq in range(slice_start, slice_end + 1):
            results.append(_serialize_event(seq, verbose_trace=verbose_trace))
            last_seq = seq

    response.headers["X-Arkham-Schema-Version"] = "1.4"
    return {
        "page": page,
        "page_size": page_size,
        "count": len(results),
        "next_cursor": last_seq,
        "has_more": slice_end < end_seq,
        "data": results,
    }
