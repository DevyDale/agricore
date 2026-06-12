"""
Data tools for the Dale agricultural assistant.

Each function returns a compact block of REAL platform data so Gemini answers
from facts, not guesses. build_grounding() detects what the user is asking about
and assembles only the relevant blocks. All model imports are local to keep this
module import-safe and avoid circular imports.
"""
from django.db.models import Avg, Count


# ---- intent detection ------------------------------------------------------

INTENT_KEYWORDS = {
    "prices": [
        "price", "prices", "worth", "value", "market rate", "going rate",
        "how much", "cost of", "selling for", "sell now", "should i sell",
        "negotiat", "offer", "store or sell", "store it",
    ],
    "buyers": [
        "buyer", "buyers", "sell to", "who should i sell", "who buys",
        "best buyer", "purchaser", "market for my",
    ],
    "transport": [
        "transport", "ship", "shipping", "deliver", "delivery", "logistics",
        "move", "truck", "haul", "carry", "freight", "refrigerated",
    ],
    "produce": [
        "my produce", "my harvest", "what i have", "my stock", "to sell",
    ],
}


def detect_intents(prompt):
    p = (prompt or "").lower()
    return {intent for intent, kws in INTENT_KEYWORDS.items() if any(k in p for k in kws)}


def _commodity_in(prompt, known):
    p = (prompt or "").lower()
    for c in known:
        if c and c.lower() in p:
            return c
    return None


# ---- tools -----------------------------------------------------------------

def market_snapshot(prompt=None, limit=15):
    from marketprices.models import MarketPrice
    known = list(MarketPrice.objects.values_list("commodity", flat=True).distinct()[:200])
    qs = MarketPrice.objects.all()
    commodity = _commodity_in(prompt, known)
    if commodity:
        qs = qs.filter(commodity__iexact=commodity)
    rows = list(qs.order_by("-recorded_on")[:limit])
    if not rows:
        return None
    lines = ["MARKET PRICES (most recent recorded on the platform):"]
    for r in rows:
        loc = r.region or r.country
        variety = f" ({r.variety})" if r.variety else ""
        lines.append(
            f"- {r.commodity}{variety}: {r.price} {r.currency}/{r.unit} "
            f"[{r.get_price_type_display()}, {loc}, {r.recorded_on}]"
        )
    return "\n".join(lines)


def buyer_options(prompt=None, limit=10):
    from marketplace.models import Store
    qs = (
        Store.objects
        .annotate(rating=Avg("store_reviews__rating"), reviews=Count("store_reviews"))
        .order_by("-is_verified", "-rating", "-reviews")
    )
    rows = list(qs[:limit])
    if not rows:
        return None
    lines = ["BUYERS / STORES on the platform (verified and higher-rated first):"]
    for s in rows:
        rating = f"{s.rating:.1f} stars ({s.reviews} reviews)" if s.rating else "no ratings yet"
        loc = s.countries_of_operation or "location not set"
        verified = "verified" if s.is_verified else "unverified"
        lines.append(f"- {s.name} [{verified}, {rating}, operates: {loc}]")
    return "\n".join(lines)


def transport_options(prompt=None, limit=10):
    from logistics.models import Vehicle, TransportBid
    vehicles = list(Vehicle.objects.filter(is_available=True)[:limit])
    bids = list(TransportBid.objects.order_by("-created_at")[:limit])
    if not vehicles and not bids:
        return None
    lines = ["TRANSPORT on the platform:"]
    if vehicles:
        lines.append("Available vehicles:")
        for v in vehicles:
            cap = f"{v.capacity_kg:.0f} kg" if v.capacity_kg else "capacity n/a"
            lines.append(f"- {v.get_vehicle_type_display()} ({cap}, reg {v.registration_number})")
    if bids:
        amounts = [b.amount for b in bids]
        lines.append(
            f"Recent transport bid prices (rate reference): "
            f"{min(amounts)}-{max(amounts)} {bids[0].currency}"
        )
    return "\n".join(lines)


def my_produce(user, limit=15):
    from produce.models import ProduceCollection
    rows = list(
        ProduceCollection.objects
        .filter(farm__owner=user)
        .order_by("-collection_date")[:limit]
    )
    if not rows:
        return None
    lines = ["THIS USER'S PRODUCE available to sell:"]
    for p in rows:
        grade = f", grade {p.quality_grade}" if p.quality_grade else ""
        lines.append(f"- {p.quantity} {p.unit} {p.product_name}{grade} (collected {p.collection_date})")
    return "\n".join(lines)


# ---- assembler -------------------------------------------------------------

GROUNDING_PREAMBLE = (
    "You are Dale, an agricultural business assistant for African farmers, traders, "
    "and transporters. Use the LIVE PLATFORM DATA below to answer with specifics. "
    "Rules: "
    "(1) Base any prices, buyers, or transport facts ONLY on this data - if something "
    "isn't here, say you don't have that data yet rather than inventing numbers. "
    "(2) Be concise and practical, and show your reasoning briefly (e.g. why one buyer "
    "or option beats another). "
    "(3) For high-stakes decisions (when to sell, loans, disease, exports) add a short "
    "caveat to confirm with a local expert or agronomist. "
    "(4) Never guarantee future prices - describe them as estimates or trends."
)


def build_grounding(user, prompt, context=None):
    """Return a system-message string of relevant live data, or None."""
    intents = detect_intents(prompt)
    if not intents:
        return None

    candidates = []
    if "prices" in intents:
        candidates.append(market_snapshot(prompt))
    if "buyers" in intents:
        candidates.append(buyer_options(prompt))
    if "transport" in intents:
        candidates.append(transport_options(prompt))
    if "produce" in intents or "prices" in intents:
        candidates.append(my_produce(user))

    blocks = [b for b in candidates if b]
    if not blocks:
        return None
    return GROUNDING_PREAMBLE + "\n\nLIVE PLATFORM DATA:\n" + "\n\n".join(blocks)
