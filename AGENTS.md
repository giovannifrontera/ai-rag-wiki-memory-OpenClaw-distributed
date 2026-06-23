# AGENTS.md — ai-rag-wiki-memory-OpenClaw-distributed

> ## ⛔ STOP — LEGGI PRIMA DI QUALSIASI AZIONE
>
> Questo è un sistema distribuito. Le istruzioni variano in base alla macchina su cui sei.
>
> **Prima di qualsiasi altra cosa: determina su quale macchina stai girando.**
>
> ---

## Quale macchina sono?

Esegui questo controllo:

```bash
# Qdrant gira localmente?
curl http://localhost:6333/health 2>/dev/null && echo "SEI SUL SERVER" || echo "SEI SU UN CLIENT"
```

Poi leggi il file corretto:

| Macchina | File da leggere |
|----------|-----------------|
| **Server** (macchina con Qdrant locale) | [`AGENTS-server.md`](AGENTS-server.md) |
| **Client** (qualsiasi altra macchina) | [`AGENTS-client.md`](AGENTS-client.md) |

---

## Differenze chiave server vs client

| | Server | Client |
|---|---|---|
| Qdrant | `localhost:6333` | `<qdrant-server>:6333` via Tailscale |
| `wiki.py rebuild` | ✅ Esegui qui | ⛔ Evita (operazione pesante) |
| Syncthing | Nodo primario | Riceve file da server |
| `wiki.py ingest` | ✅ Sì | ✅ Sì (scrive file locali + vettori remoti) |
| Migrazione LanceDB → Qdrant | Eseguita qui | Non applicabile |

---

## Precondizioni comuni (tutte le macchine)

Prima di qualsiasi sessione:

1. `Read wiki-session.md` — controlla `status`
2. `Read skills/wiki-core.md` — carica il protocollo
3. Verifica Qdrant raggiungibile (locale o remoto)
4. Scansiona `*.sync-conflict-*` in `wiki/` e `wiki-works/` — se trovati, **fermati**
5. Se `status ≠ ok` — avvisa l'utente prima di procedere

---

## Struttura repo

```
scripts/
├── wiki.py                       ← CLI unificata
├── wiki_qdrant.py                ← ops Qdrant (sostituisce wiki_lancedb.py)
├── wiki_context.py               ← hook pre-prompt
├── migrate_lancedb_to_qdrant.py  ← migrazione one-shot (solo su server)
└── ...

deploy/
├── qdrant.service                ← systemd per il server
├── syncthing-stignore            ← da copiare in workspace/.stignore
└── setup-client.sh               ← setup automatico client

AGENTS-server.md                  ← istruzioni per la macchina server
AGENTS-client.md                  ← istruzioni per le macchine client
skills/wiki-core.md               ← protocollo agente (tutti leggono questo)
```
