#!/usr/bin/env python3
"""TF-IDF semantic search over lessons.json"""
import json, sys, math, re, os
from collections import Counter

LESSONS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "learning", "lessons.json")

SEVERITY_WEIGHT = {"critical": 3, "high": 2.5, "medium": 2, "low": 1}
SEVERITY_EMOJI = {"critical": "🔴", "high": "🔴", "medium": "🟡", "low": "🟢"}
VALID_SEVERITIES = set(SEVERITY_WEIGHT.keys())
VALID_AGENTS = {"or", "koder", "shomer", "tzayar", "worker", "researcher", "bodek"}

STOP_WORDS = set("the a an is was were be been being have has had do does did will would shall should may might can could and but or nor for yet so at by in on to from with as of it its this that these those i me my we our you your he him his she her they them their what which who whom how when where why all each every both few more most other some such no not only own same than too very".split())

def tokenize(text):
    return [w for w in re.findall(r'[a-z0-9]+', text.lower()) if w not in STOP_WORDS and len(w) > 1]

def normalize_lesson(l):
    """Handle both normal and swapped-field formats"""
    sev = l.get("severity", "low")
    agent = l.get("agent", "?")
    what = l.get("what", "") or ""
    lesson = (l.get("lesson", "") or "")[:200]
    title = l.get("title", "") or ""

    # Detect swapped format: severity contains a title, agent contains actual severity
    if sev not in VALID_SEVERITIES:
        if agent in VALID_SEVERITIES:
            # Fields are: severity=title, agent=real_severity, lesson=real_agent
            real_sev = agent
            real_agent = lesson[:20].strip() if lesson else "?"
            real_title = sev
            real_lesson = what[:200] if what else sev
            return real_agent, real_sev, real_title, real_lesson
        else:
            # severity=high or unknown, treat as medium
            pass

    return agent, sev if sev in VALID_SEVERITIES else "medium", title or what[:80], lesson or what[:200]

def get_text(l):
    agent, sev, title, lesson = normalize_lesson(l)
    what = l.get("what", "") or ""
    return f"{title} {what} {lesson}"

def tfidf_search(query, lessons):
    docs = [tokenize(get_text(l)) for l in lessons]
    query_tokens = tokenize(query)
    if not query_tokens:
        return []

    df = Counter()
    for doc in docs:
        for w in set(doc):
            df[w] += 1
    N = len(docs)

    results = []
    for i, doc in enumerate(docs):
        if not doc:
            continue
        tf = Counter(doc)
        max_tf = max(tf.values())
        score = 0.0
        for qt in query_tokens:
            if qt in tf:
                tf_val = 0.5 + 0.5 * tf[qt] / max_tf
                idf_val = math.log((N + 1) / (df.get(qt, 0) + 1)) + 1
                score += tf_val * idf_val
        if score > 0:
            _, sev, _, _ = normalize_lesson(lessons[i])
            weighted = SEVERITY_WEIGHT.get(sev, 1) * score
            results.append((weighted, i))

    results.sort(key=lambda x: -x[0])
    return results[:5]

def main():
    if len(sys.argv) < 2:
        print("Usage: semantic-search.py <query>", file=sys.stderr)
        sys.exit(1)

    query = " ".join(sys.argv[1:])
    with open(LESSONS_PATH) as f:
        data = json.load(f)
    lessons = data.get("lessons", [])

    results = tfidf_search(query, lessons)
    if not results:
        print(f"No lessons found for: {query}")
        sys.exit(0)

    print(f"📚 {len(results)} lessons found for \"{query}\":")
    for score, idx in results:
        l = lessons[idx]
        agent, sev, title, lesson = normalize_lesson(l)
        emoji = SEVERITY_EMOJI.get(sev, "⚪")
        desc = lesson[:100]
        print(f"  {emoji} [{agent}] {title} — {desc}")

if __name__ == "__main__":
    main()
