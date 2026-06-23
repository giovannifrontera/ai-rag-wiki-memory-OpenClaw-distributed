# AGENTS-client.md — Macchina Client

> ## ⛔ STOP — LEGGI PRIMA DI QUALSIASI AZIONE
>
> **Ogni sessione, prima di qualsiasi azione:**
> 1. `Read wiki-session.md` nel workspace — controlla lo status
> 2. `Read skills/wiki-core.md` — carica il protocollo completo
> 3. Verifica connettività Qdrant: `curl http://<bazzite-tailscale>:6333/health`
> 4. Verifica Syncthing sincronizzato (file recenti presenti in `wiki/`)
> 5. Scansiona `wiki/` e `wiki-works/` per file `*.sync-conflict-*` — se trovati, **fermati e avvisa**
>
> Questi sono file locali. Usa il tool **Read**, non una Skill o Tool call.
>
> ---

Questa è una **macchina client**: non esegue Qdrant localmente. Si connette al server Bazzite via Tailscale per le query vettoriali, e riceve i file wiki via Syncthing.

---

## Stato di salute — controlla prima di ogni sessione

```bash
# Qdrant raggiungibile via Tailscale?
curl http://<bazzite-tailscale>:6333/health
# Atteso: {"title":"qdrant - vector search engine","version":"..."}
# Se fallisce: verifica che Tailscale sia connesso e Qdrant sia in esecuzione su Bazzite

# Tailscale connesso?
tailscale status

# Syncthing: file recenti presenti?
ls -lt ~/.openclaw/workspace/wiki/ | head -5
# I file devono essere aggiornati — se sono vecchi, Syncthing potrebbe non essere attivo
```

Se Qdrant non è raggiungibile:
- Verifica `tailscale status` — sei connesso alla rete?
- Verifica che Qdrant sia in esecuzione su Bazzite: chiedi all'utente di controllare `systemctl status qdrant`
- **Non procedere** con ingest se Qdrant non risponde — i vettori non verrebbero scritti

---

## Struttura workspace

```
~/.openclaw/workspace/          ← sincronizzato via Syncthing da Bazzite
├── wiki.config.json            ← qdrant.host = "<bazzite-tailscale>" (NON localhost)
├── wiki-session.md             ← stato sessione corrente
├── wiki/                       ← livello Distillato + Identity (ricevuto via Syncthing)
│   └── identity/               ← solo wiki.py self-reflect scrive qui
├── wiki-works/<topic>/         ← livello Dominio (sync bidirezionale Syncthing)
└── .stignore                   ← regole esclusione Syncthing
```

> **Importante:** `wiki.config.json` su questa macchina deve avere `qdrant.host` impostato
> al nome Tailscale di Bazzite, **non** `localhost`. Verifica con:
> ```bash
> python -c "import json; cfg=json.load(open('~/.openclaw/workspace/wiki.config.json'.replace('~', __import__('os').path.expanduser('~')))); print(cfg['qdrant']['host'])"
> # Atteso: bazzite.tail (o simile), NON localhost
> ```

---

## Comandi disponibili

I client eseguono gli stessi comandi del server, con due eccezioni:

| Comando | Client | Note |
|---------|--------|------|
| `ingest` | ✅ Sì | Scrive file Markdown localmente (Syncthing li propaga) + vettori su Qdrant remoto |
| `query` | ✅ Sì | Query su Qdrant remoto via Tailscale |
| `lint` | ✅ Sì (leggero) | Controlla consistenza file locali |
| `index` | ✅ Sì | Genera index.md locale |
| `serve` | ✅ Sì | Dashboard locale (legge Qdrant remoto) |
| `ingest-pdf` | ✅ Sì | Estrae PDF localmente, file va in Syncthing |
| `self-reflect` | ✅ Sì | Scrive in `wiki/identity/` (propagato da Syncthing) |
| `rebuild` | ⛔ Evita | Operazione pesante — preferibilmente eseguita su Bazzite |

### Ingestione

```bash
python scripts/wiki.py ingest \
    --workspace ~/.openclaw/workspace \
    --pages wiki-works/trading/concetti/nuovo.md.tmp \
    --log "ingest | Nuovo concetto trading"
```

Il file Markdown viene scritto localmente; Syncthing lo propaga a Bazzite entro pochi secondi. I vettori vengono scritti su Qdrant via Tailscale.

### Query e contesto

```bash
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "domanda utente" --k 3
```

---

## Protocollo conflitti Syncthing

I file `*.sync-conflict-*` si creano quando questa macchina e Bazzite (o un'altra macchina) modificano la stessa pagina wiki contemporaneamente.

Se trovi file `*.sync-conflict-*` in `wiki/` o `wiki-works/`:

1. **Non procedere** con nessuna operazione wiki
2. Avvisa l'utente: "Conflitto Syncthing trovato: [lista file]. Due istanze hanno scritto la stessa pagina contemporaneamente. Quale versione vuoi tenere?"
3. Mostra il contenuto di entrambi i file
4. Aspetta la decisione dell'utente
5. Dopo la risoluzione: elimina il file scartato, esegui `wiki.py lint`
6. Aggiorna `wiki-session.md` con `status: ok`

Non cancellare mai file di conflitto automaticamente.

---

## Wiki context injection

Ogni prompt arriva preceduto da:

```
<wiki-context>
Contesto wiki pre-caricato (top 3 pagine per rilevanza semantica):
### wiki/concepts/rag.md  [rilevanza: 0.91]
[contenuto pagina...]
</wiki-context>
```

Usa questo direttamente. Non rieseguire `wiki.py query` per lo stesso prompt.
Se tutti i punteggi di rilevanza < 0.4 → il wiki non ha conoscenza rilevante, procedi normalmente.

---

## PDF ingestion

```bash
python scripts/wiki.py ingest-pdf --workspace <path> --file <path|url>
```

Il testo estratto viene depositato in `wiki-works/<progetto>/raw/` localmente. Syncthing lo propaga. Poi segui il workflow standard:

1. Leggi ogni file in `raw/`
2. Scrivi pagine `.tmp` strutturate
3. Chiama `wiki.py ingest`

---

## Architettura — tre livelli, un cervello

| Livello | Directory | Contenuti | Chi scrive |
|---------|-----------|-----------|------------|
| **Dominio** | `wiki-works/<topic>/` | Conoscenza profonda per topic | Workflow INGEST |
| **Distillato** | `wiki/` | Conoscenza cross-domain, promossa autonomamente | Agente (autonomo) |
| **Identità** | `wiki/identity/` | Valori, stile, pattern comportamentali | Solo `wiki.py self-reflect` |

---

## Comandi (riferimento)

```
wiki.py ingest         --workspace <path> --pages <p1.tmp,...> --log <str>
wiki.py query          --workspace <path> --q <string> [--k 5]
wiki.py lint           --workspace <path> [--full]
wiki.py index          --workspace <path>
wiki.py scan-inbox     --workspace <path>
wiki.py ingest-pdf     --workspace <path> --file <path|url>
wiki.py serve          --workspace <path> [--port 7331] [--no-auth]
wiki.py behavior-log   --workspace <path> --event "<correzione>"
wiki.py self-reflect   --workspace <path>

wiki_context.py        --workspace <path> --q <string> [--k 3] [--max-chars 600]
```
